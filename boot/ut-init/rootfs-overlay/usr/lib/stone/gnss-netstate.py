#!/usr/bin/env python3
"""Give Qualcomm's GNSS stack what Android's framework would: network state.

Without this the GNSS engine starts cold every time (no time, no satellite
orbit data) and a first fix takes many minutes outdoors, or never comes.

1. persist.sys.xtra-daemon.enabled=true. The vendor's loc_launcher starts
   xtra-daemon (NTP time and XTRA orbit data, injected into the modem's GNSS
   engine) only with it; on Android Qualcomm's framework apps set it.
   init.qcom.rc restarts loc_launcher when it changes.
2. IAGnssRil::updateNetworkState(connected, type, roaming) on
   android.hardware.gnss@1.0::IGnss/default (hwbinder). xtra-daemon only
   downloads when the HAL believes there is a data connection ("isCon:0"
   otherwise); on Android, GnssNetworkConnectivityHandler reports every
   connectivity change. Here the state comes from NetworkManager: connected
   when NM's State is CONNECTED_SITE (60) or CONNECTED_GLOBAL (70), type
   WIFI or MOBILE from PrimaryConnectionType.

Sent at start, on every NetworkManager State/PrimaryConnectionType change,
whenever the GNSS HAL registers again (HAL restart), and every 10 minutes.
lomiri-location-service owns the IGnss callbacks; this only uses the
IAGnssRil extension, which does not touch them.
"""
import subprocess
import sys

import dbus
import dbus.mainloop.glib
import gbinder
from gi.repository import GLib

IGNSS = "android.hardware.gnss@1.0::IGnss"
IAGNSSRIL = "android.hardware.gnss@1.0::IAGnssRil"
GNSS_FQNAME = IGNSS + "/default"
TX_GET_EXTENSION_AGNSS_RIL = 9     # IGnss@1.0, 9th method
TX_UPDATE_NETWORK_STATE = 4        # IAGnssRil@1.0
TX_UPDATE_NETWORK_AVAILABILITY = 5
TYPE_MOBILE, TYPE_WIFI = 0, 1      # IAGnssRil::NetworkType
NM = "org.freedesktop.NetworkManager"
NM_PATH = "/org/freedesktop/NetworkManager"
REFRESH_S = 600



class HwServiceManager(gbinder.ServiceManager):
    # add_registration_handler(name, func) stores func as an instance
    # attribute (registration_func), which the Cython base class cannot hold.
    pass


sm = HwServiceManager("/dev/hwbinder")
bus = None
last = None


def log(msg):
    print(msg, flush=True)


def ensure_xtra_daemon_enabled():
    try:
        cur = subprocess.run(["getprop", "persist.sys.xtra-daemon.enabled"],
                             capture_output=True, text=True).stdout.strip()
        if cur != "true":
            subprocess.run(["setprop", "persist.sys.xtra-daemon.enabled", "true"])
            log("persist.sys.xtra-daemon.enabled: %r -> true" % cur)
    except OSError as e:
        log("setprop failed: %s" % e)


def network_state():
    try:
        nm = bus.get_object(NM, NM_PATH)
        props = dbus.Interface(nm, "org.freedesktop.DBus.Properties")
        state = int(props.Get(NM, "State"))
        ctype = str(props.Get(NM, "PrimaryConnectionType"))
    except dbus.exceptions.DBusException as e:
        log("NetworkManager not available: %s" % e.get_dbus_name())
        return False, TYPE_MOBILE, "none"
    connected = state >= 60
    ntype = TYPE_WIFI if ctype in ("802-11-wireless", "802-3-ethernet") else TYPE_MOBILE
    return connected, ntype, "%s/%d" % (ctype or "none", state)


def agnss_ril():
    gnss, status = sm.get_service_sync(GNSS_FQNAME)
    if gnss is None:
        raise RuntimeError("%s not registered (status %s)" % (GNSS_FQNAME, status))
    client = gbinder.Client(gnss, IGNSS)
    reply, status = client.transact_sync_reply(TX_GET_EXTENSION_AGNSS_RIL, client.new_request())
    if reply is None:
        raise RuntimeError("getExtensionAGnssRil failed: %s" % status)
    reader = reply.init_reader()
    reader.read_int32()                     # HIDL status
    ok, ril = reader.read_nullable_object()
    if not ok or ril is None:
        raise RuntimeError("no IAGnssRil")
    return gbinder.Client(ril, IAGNSSRIL)


def push(reason, force=False):
    global last
    connected, ntype, desc = network_state()
    state = (connected, ntype)
    if state == last and not force:
        return
    try:
        ril = agnss_ril()
        req = ril.new_request()
        req.append_bool(connected)
        req.append_int32(ntype)             # uint8 enum, padded to 4 bytes
        req.append_bool(False)              # roaming
        reply, status = ril.transact_sync_reply(TX_UPDATE_NETWORK_STATE, req)
        r = reply.init_reader()
        r.read_int32()
        ok, ret = r.read_bool()
        req = ril.new_request()
        req.append_bool(connected)
        req.append_hidl_string("")
        ril.transact_sync_reply(TX_UPDATE_NETWORK_AVAILABILITY, req)
    except Exception as e:                  # HAL not up yet or restarting
        log("%s: updateNetworkState failed: %s" % (reason, e))
        last = None
        return
    last = state
    log("%s: %s -> updateNetworkState(connected=%s, type=%s) = %s" % (
        reason, desc, connected, "WIFI" if ntype == TYPE_WIFI else "MOBILE", ret))


def on_nm_changed(*args, **kwargs):
    GLib.timeout_add(500, lambda: push("network change") or False)


def on_gnss_registered(*args):
    # Called for every registration of the name, and once at once if it is
    # already registered. The argument list is not documented.
    log("%s registered" % GNSS_FQNAME)
    ensure_xtra_daemon_enabled()
    GLib.timeout_add_seconds(2, lambda: push("GNSS HAL registered", force=True) or False)


def periodic():
    push("periodic", force=True)
    return True


def main():
    global bus
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    ensure_xtra_daemon_enabled()
    bus.add_signal_receiver(on_nm_changed, signal_name="StateChanged",
                            dbus_interface=NM, path=NM_PATH)
    bus.add_signal_receiver(on_nm_changed, signal_name="PropertiesChanged",
                            dbus_interface="org.freedesktop.DBus.Properties",
                            path=NM_PATH)
    push("start", force=True)
    sm.add_registration_handler(GNSS_FQNAME, on_gnss_registered)
    GLib.timeout_add_seconds(REFRESH_S, periodic)
    GLib.MainLoop().run()


if __name__ == "__main__":
    if sys.argv[1:] == ["--once"]:
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SystemBus()
        ensure_xtra_daemon_enabled()
        push("once", force=True)
    else:
        main()
