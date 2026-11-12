#!/usr/bin/python3
# Reconnect Bluetooth audio devices when Bluetooth is turned on (and at boot),
# as Android does (docs/roadmap-release.md, Bluetooth).
#
# BlueZ only reconnects after a link loss; after the adapter is powered on, it
# waits for the remote device to connect. Earbuds taken out of the case while
# Bluetooth was off page the phone, get no answer and back off, so they only
# come back 20-30 s after Bluetooth is turned on, or not at all.
#
# On power on, connect the devices that were connected when Bluetooth was
# turned off, or else the last one used. Only paired, trusted ("Connect
# automatically when detected" in System Settings), unblocked devices with an
# audio profile. A device that is not around (earbuds in the case) just fails
# to connect; two retries, 10 s apart, then it is left to connect by itself.
# A device the user disconnected (Device1.Disconnect, and still disconnected
# 5 s later with Bluetooth on) is not reconnected until it connects again.
import json
import os
import time

from gi.repository import Gio, GLib

# STONE_BT_AUTOCONNECT_STATE: for a test run as a user.
STATE = os.environ.get("STONE_BT_AUTOCONNECT_STATE", "/var/lib/stone/bt-autoconnect.json")
AUDIO_UUIDS = {
    "0000110b-0000-1000-8000-00805f9b34fb",  # Audio Sink (A2DP)
    "0000111e-0000-1000-8000-00805f9b34fb",  # Handsfree (HFP HF)
    "00001108-0000-1000-8000-00805f9b34fb",  # Headset (HSP)
}
# A device that disconnected this shortly before the power off was connected
# at the time: the kernel disconnects links before it closes the adapter.
RECENT = 5.0
# After an abrupt loss (bluebinder restarted, the HAL died) the remote still
# thinks it is connected and does not answer pages until its link supervision
# timeout (often 20 s): keep trying past that.
RETRY_DELAY = 10
ATTEMPTS = 3


def log(msg):
    print(f"stone-bt-autoconnect: {msg}", flush=True)


bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
manager = Gio.DBusProxy.new_sync(bus, Gio.DBusProxyFlags.NONE, None, "org.bluez", "/",
                                 "org.freedesktop.DBus.ObjectManager", None)

devices = {}        # path -> properties (dict of python values)
disconnected_at = {}  # path -> monotonic time of the last disconnection
adapter = {"path": None, "powered": False, "off_at": -1e9, "added_at": -1e9}
pending = {"targets": []}


def load_last():
    try:
        with open(STATE) as f:
            return json.load(f).get("last", [])
    except (OSError, ValueError):
        return []


def save_last(addresses):
    try:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        with open(STATE + ".new", "w") as f:
            json.dump({"last": addresses}, f)
        os.replace(STATE + ".new", STATE)
    except OSError as e:
        log(f"cannot save {STATE}: {e}")


def eligible(path):
    p = devices.get(path, {})
    return (p.get("Paired") and p.get("Trusted") and not p.get("Blocked")
            and AUDIO_UUIDS & {u.lower() for u in p.get("UUIDs", [])})


def remember_connected(path):
    addr = devices[path].get("Address")
    if not addr or not eligible(path):
        return
    last = [a for a in load_last() if a != addr]
    save_last([addr] + last[:4])


def forget(path):
    addr = devices.get(path, {}).get("Address")
    if addr in load_last():
        save_last([a for a in load_last() if a != addr])
        log(f"{devices[path].get('Alias', addr)} was disconnected by the user; not reconnecting it")


def user_disconnect(path):
    """Device1.Disconnect or DisconnectProfile was called for path."""
    if path not in devices:
        return False
    at = time.monotonic()

    def check():
        # Still disconnected, with Bluetooth on: the user meant it. (A power
        # off in between makes it Bluetooth being turned off instead.)
        if adapter["off_at"] > at - 1:
            return False
        if adapter["powered"] and not devices.get(path, {}).get("Connected"):
            forget(path)
        return False
    GLib.timeout_add_seconds(int(RECENT), check)
    return False


def watch_disconnect_calls():
    """See who asks BlueZ to disconnect a device (System Settings,
    bluetoothctl, ...). The Disconnected signal's reason cannot tell: BlueZ
    closes the profiles first and these earbuds then drop the link
    themselves, so a user's Disconnect arrives as org.bluez.Reason.Remote.
    Needs root (D-Bus BecomeMonitor)."""
    rules = [f"type='method_call',interface='org.bluez.Device1',member='{m}'"
             for m in ("Disconnect", "DisconnectProfile")]

    def on_message(connection, message, incoming):
        if (incoming and message.get_message_type() == Gio.DBusMessageType.METHOD_CALL
                and message.get_interface() == "org.bluez.Device1"):
            GLib.idle_add(user_disconnect, message.get_path())
            return None
        return message

    try:
        addr = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SYSTEM, None)
        mon = Gio.DBusConnection.new_for_address_sync(
            addr, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        mon.add_filter(on_message)
        mon.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                      "org.freedesktop.DBus.Monitoring", "BecomeMonitor",
                      GLib.Variant("(asu)", (rules, 0)), None,
                      Gio.DBusCallFlags.NONE, 5000, None)
        return mon
    except GLib.Error as e:
        log(f"cannot watch Disconnect calls ({e.message}); user disconnects are not told apart")
        return None


def by_address(addr):
    for path, p in devices.items():
        if p.get("Address") == addr:
            return path
    return None


def connect(path, attempt=1):
    p = devices.get(path)
    if not p or p.get("Connected") or not adapter["powered"] or not eligible(path):
        return False
    name = p.get("Alias") or p.get("Address")
    log(f"connecting {name} (attempt {attempt})")

    def done(proxy, res):
        try:
            proxy.call_finish(res)
            log(f"connected {name}")
        except GLib.Error as e:
            log(f"{name}: {e.message}")
            if attempt < ATTEMPTS:
                GLib.timeout_add_seconds(RETRY_DELAY, lambda: connect(path, attempt + 1) and False)

    dev = Gio.DBusProxy.new_sync(bus, Gio.DBusProxyFlags.DO_NOT_LOAD_PROPERTIES, None,
                                 "org.bluez", path, "org.bluez.Device1", None)
    dev.call("Connect", None, Gio.DBusCallFlags.NONE, 30000, None, done)
    return False


def connect_targets():
    targets, pending["targets"] = pending["targets"], []
    for i, path in enumerate(targets):
        # One at a time is kinder to the controller; stagger by a few seconds.
        GLib.timeout_add_seconds(1 + 3 * i, lambda path=path: connect(path))
    return False


def powered_on(why):
    snapshot = pending.get("snapshot") or []
    pending["snapshot"] = []
    targets = [p for p in snapshot if eligible(p)]
    if not targets:
        for addr in load_last()[:1]:
            path = by_address(addr)
            if path and eligible(path):
                targets.append(path)
    names = [devices[p].get("Alias") or devices[p].get("Address") for p in targets]
    log(f"{why}; reconnecting: {', '.join(names) or 'nothing'}")
    pending["targets"] = targets
    connect_targets()


def powered_off():
    now = time.monotonic()
    adapter["off_at"] = now
    snap = [p for p in devices if eligible(p) and (
        devices[p].get("Connected") or now - disconnected_at.get(p, -1e9) < RECENT)]
    pending["snapshot"] = snap
    log("powered off; were connected: " +
        (", ".join(devices[p].get("Alias", p) for p in snap) or "none"))


def on_props_changed(conn, sender, path, iface, signal, params):
    changed_iface, changed, _ = params.unpack()
    if changed_iface == "org.bluez.Device1" and path in devices:
        devices[path].update(changed)
        if "Connected" in changed:
            if changed["Connected"]:
                remember_connected(path)
            else:
                disconnected_at[path] = time.monotonic()
    elif changed_iface == "org.bluez.Adapter1" and path == adapter["path"] and "Powered" in changed:
        was, adapter["powered"] = adapter["powered"], bool(changed["Powered"])
        if adapter["powered"] and not was:
            if time.monotonic() - adapter["added_at"] < 5:
                adapter_up_later("adapter appeared, then powered on")
            else:
                powered_on("powered on")
        elif was and not adapter["powered"]:
            powered_off()


def adapter_up_later(why):
    # bluetoothd exports the paired devices after the adapter: give them a
    # moment, then act as on a power on unless something connected by itself.
    def go():
        if adapter["powered"] and not any(p.get("Connected") for p in devices.values()):
            powered_on(why)
        return False
    GLib.timeout_add_seconds(3, go)


def on_added(conn, sender, path, iface, signal, params):
    obj, ifaces = params.unpack()
    if "org.bluez.Device1" in ifaces:
        devices[obj] = dict(ifaces["org.bluez.Device1"])
    if "org.bluez.Adapter1" in ifaces and adapter["path"] is None:
        # At boot the adapter appears late (bluebinder waits for the HAL), and
        # it may appear already powered: there is no Powered change to see then.
        # Also after bluebinder re-creates hci0 (the HAL died).
        adapter["path"] = obj
        adapter["added_at"] = time.monotonic()
        adapter["powered"] = bool(ifaces["org.bluez.Adapter1"].get("Powered"))
        log(f"adapter {obj} appeared, powered={adapter['powered']}")
        if adapter["powered"]:
            adapter_up_later("adapter appeared powered")


def on_removed(conn, sender, path, iface, signal, params):
    obj, ifaces = params.unpack()
    if "org.bluez.Device1" in ifaces:
        devices.pop(obj, None)
    if "org.bluez.Adapter1" in ifaces and obj == adapter["path"]:
        log(f"adapter {obj} removed")
        if adapter["powered"]:
            powered_off()
        adapter["path"] = None
        adapter["powered"] = False


bus.signal_subscribe("org.bluez", "org.freedesktop.DBus.Properties", "PropertiesChanged",
                     None, None, Gio.DBusSignalFlags.NONE, on_props_changed)
monitor = watch_disconnect_calls()
bus.signal_subscribe("org.bluez", "org.freedesktop.DBus.ObjectManager", "InterfacesAdded",
                     "/", None, Gio.DBusSignalFlags.NONE, on_added)
bus.signal_subscribe("org.bluez", "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved",
                     "/", None, Gio.DBusSignalFlags.NONE, on_removed)

objects = manager.call_sync("GetManagedObjects", None, Gio.DBusCallFlags.NONE, 5000, None)
for path, ifaces in objects.unpack()[0].items():
    if "org.bluez.Device1" in ifaces:
        devices[path] = dict(ifaces["org.bluez.Device1"])
        if devices[path].get("Connected"):
            remember_connected(path)
    if "org.bluez.Adapter1" in ifaces and adapter["path"] is None:
        adapter["path"] = path
        adapter["powered"] = bool(ifaces["org.bluez.Adapter1"].get("Powered"))

log(f"started; adapter {adapter['path']} powered={adapter['powered']}, "
    f"last used: {', '.join(load_last()) or 'none'}")
if adapter["powered"]:
    # A restart of this service, or bluetoothd was quicker than usual.
    adapter_up_later("started with Bluetooth on")

GLib.MainLoop().run()
