#!/usr/bin/python3
# MTP and adb with a PC that connected before the session could serve it
# (docs/roadmap-release.md item 2). Runs in the user session.
#
# UBports' mtp-server only adds its storages once the greeter is no longer
# active ("device is not locked, adding storage"), and PC-side MTP clients
# (libmtp, KDE's kmtpd, GNOME's gvfs) read the storage list once, when the
# device appears: a PC that connected while the phone was locked shows "Could
# not access device ... make sure it is unlocked" even after the unlock.
# Android avoids this by re-enumerating USB on unlock. At boot it is worse:
# usb-moded enters mtp_adb about 15 s before mtp-server even starts, the PC's
# libmtp times out and resets the device, and that reset also ends adbd's USB
# session for good.
#
# So, like a replug in software (usb-moded to charging_only and back: it
# restarts adbd, UBports' watcher restarts mtp-server, the PC sees a new
# device):
# - once when this session starts, if a PC is attached in an MTP mode (the
#   boot case: the PC met no mtp-server);
# - on an unlock, if a PC got the MTP device while the phone was locked.
import time

from gi.repository import Gio, GLib

UDC_STATE = "/sys/class/udc/4e00000.dwc3/state"
MTP_MODES = ("mtp", "mtp_adb")


def log(msg):
    print(f"stone-usb-mtp-reconnect: {msg}", flush=True)


def pc_attached():
    try:
        with open(UDC_STATE) as f:
            return f.read().strip() == "configured"
    except OSError:
        return False


usb_moded = Gio.DBusProxy.new_for_bus_sync(
    Gio.BusType.SYSTEM, Gio.DBusProxyFlags.DO_NOT_LOAD_PROPERTIES, None,
    "com.meego.usb_moded", "/com/meego/usb_moded", "com.meego.usb_moded", None)
# Properties are loaded and kept current; while the greeter is not on the bus
# yet, IsActive is None and counts as locked.
greeter = Gio.DBusProxy.new_for_bus_sync(
    Gio.BusType.SESSION, Gio.DBusProxyFlags.DO_NOT_AUTO_START, None,
    "com.lomiri.LomiriGreeter", "/com/lomiri/LomiriGreeter",
    "com.lomiri.LomiriGreeter", None)


def locked():
    v = greeter.get_cached_property("IsActive")
    return v is None or v.get_boolean()


def current_mode():
    return usb_moded.call_sync("mode_request", None, Gio.DBusCallFlags.NONE,
                               1000, None).get_child_value(0).get_string()


state = {"mode": current_mode(), "stale": False, "busy": False}


def set_mode(mode):
    usb_moded.call_sync("set_mode", GLib.Variant("(s)", (mode,)),
                        Gio.DBusCallFlags.NONE, 5000, None)


def wait_mode(mode, timeout):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if current_mode() == mode:
            return True
        time.sleep(0.25)
    return False


def reconnect(why):
    mode = state["mode"]
    if mode not in MTP_MODES or not pc_attached():
        return
    log(f"{why}: reconnecting USB ({mode})")
    state["busy"] = True
    try:
        try:
            set_mode("charging_only")
        except GLib.Error as e:
            # Nothing changed; the PC keeps the device it has.
            log(f"reconnect not started: {e.message}")
            return
        wait_mode("charging_only", 10)
        time.sleep(1)
        # usb-moded rejects set_mode while "busy" (and in other transient
        # states): retry, never leave the phone in charging_only.
        ok = False
        for attempt in range(10):
            try:
                set_mode(mode)
            except GLib.Error as e:
                log(f"back to {mode}, attempt {attempt + 1}: {e.message}")
            if wait_mode(mode, 5):
                ok = True
                break
        log(f"mode now {current_mode()}" + ("" if ok else " (expected %s)" % mode))
    except GLib.Error as e:
        log(f"reconnect failed: {e.message}")
    finally:
        state["busy"] = False
        state["mode"] = current_mode()
        state["stale"] = False


def on_usb_signal(proxy, sender, signal, params):
    if signal != "sig_usb_current_state_ind" or state["busy"]:
        return
    mode = params.get_child_value(0).get_string()
    if mode == "busy":
        return
    state["mode"] = mode
    if mode in MTP_MODES:
        # A PC that gets the device now while locked sees no storages.
        state["stale"] = locked()
    else:
        state["stale"] = False


def on_greeter_props(proxy, changed, invalidated):
    v = changed.lookup_value("IsActive", None)
    if v is not None and not v.get_boolean() and state["stale"]:
        # Let mtp-server add its storages first.
        GLib.timeout_add(1500, lambda: reconnect("unlocked") or False)


usb_moded.connect("g-signal", on_usb_signal)
greeter.connect("g-properties-changed", on_greeter_props)

if state["mode"] in MTP_MODES and pc_attached():
    # Give UBports' watcher time to start mtp-server, which also starts now.
    def at_start():
        reconnect("session start with a PC attached")
        state["stale"] = locked()
        return False
    GLib.timeout_add(3000, at_start)

GLib.MainLoop().run()
