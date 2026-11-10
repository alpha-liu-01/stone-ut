#!/usr/bin/python3 -I
"""Minimal android.system.net.netd@1.1::INetd/default on /dev/hwbinder.

Halium runs no netd. The Qualcomm netmgrd (ro.vendor.use_data_netmgrd=true)
waits for V1_1::INetd::getService("default") before it finishes starting;
until then DSI never initialises and qcril's DataModule refuses every
setupDataCall ("[CallManager]: DSI init not yet completed", cause 4100).

Ubuntu's NetworkManager owns routing and the firewall here, so the OEM
network calls only need to succeed. Same idea as mer-hybris/dummy_netd, but
every method gets a well-formed HIDL reply (transport status, then the
return values) so netmgrd's createOemNetwork() sees StatusCode::OK.
"""
import signal
import sys

import gbinder
from gi.repository import GLib

DEVICE = "/dev/hwbinder"
NAME = "default"
IFACES = ["android.system.net.netd@1.1::INetd",
          "android.system.net.netd@1.0::INetd"]

# HIDL method codes, in declaration order across the interface chain.
CREATE_OEM_NETWORK = 1                  # () -> (u64 handle, u32 mark, status)
DESTROY_OEM_NETWORK = 2                 # (u64) -> (status)
ADD_ROUTE_TO_OEM_NETWORK = 3            # 1.1, all below -> (status)
REMOVE_ROUTE_FROM_OEM_NETWORK = 4
ADD_INTERFACE_TO_OEM_NETWORK = 5
REMOVE_INTERFACE_FROM_OEM_NETWORK = 6
SET_IP_FORWARD_ENABLE = 7
SET_FORWARDING_BETWEEN_INTERFACES = 8

NAMES = {
    CREATE_OEM_NETWORK: "createOemNetwork",
    DESTROY_OEM_NETWORK: "destroyOemNetwork",
    ADD_ROUTE_TO_OEM_NETWORK: "addRouteToOemNetwork",
    REMOVE_ROUTE_FROM_OEM_NETWORK: "removeRouteFromOemNetwork",
    ADD_INTERFACE_TO_OEM_NETWORK: "addInterfaceToOemNetwork",
    REMOVE_INTERFACE_FROM_OEM_NETWORK: "removeInterfaceFromOemNetwork",
    SET_IP_FORWARD_ENABLE: "setIpForwardEnable",
    SET_FORWARDING_BETWEEN_INTERFACES: "setForwardingBetweenInterfaces",
}

STATUS_OK = 0
next_net_id = 100


def log(msg):
    print(msg, flush=True)


def handler(req, code, flags):
    global next_net_id
    reply = obj.new_reply()
    if code not in NAMES:
        log("unknown transaction %d" % code)
        return None, -1  # UNKNOWN_TRANSACTION-ish; libgbinder replies an error
    reply.append_int32(0)  # hardware::Status::ok()
    if code == CREATE_OEM_NETWORK:
        net_id = next_net_id
        next_net_id += 1
        handle = (net_id << 32) | 0xfacade   # what Android's netd hands out
        mark = net_id | 0x30000              # explicitlySelected|protectedFromVpn
        reply.append_int64(handle)
        reply.append_int32(mark)
        log("createOemNetwork -> netId %d handle 0x%x mark 0x%x" % (net_id, handle, mark))
    else:
        log(NAMES[code])
    reply.append_int32(STATUS_OK)
    return reply, 0


sm = gbinder.ServiceManager(DEVICE)
obj = sm.new_local_object(IFACES, handler)
loop = GLib.MainLoop()


def register():
    if sm.is_present():
        st = sm.add_service_sync(NAME, obj)
        log("registered %s/%s: %s" % (IFACES[0], NAME, "ok" if st == 0 else st))


register()
sm.add_presence_handler(register)  # re-register if hwservicemanager restarts
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, loop.quit)
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, loop.quit)
loop.run()
sys.exit(0)
