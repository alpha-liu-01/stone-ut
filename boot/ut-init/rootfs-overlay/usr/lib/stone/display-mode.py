#!/usr/bin/env python3
"""Read or switch the panel's display mode (refresh rate) on stone.

Mir's Android platform (hwc2 compat layer) only ever reads the composer's
active config; it has no call to list or set configs, so the panel stays in
whatever mode the composer started with. Qualcomm's composer also serves
vendor.display.config@2.0::IDisplayConfig on hwbinder, which Android's
display tools use to switch the active config from outside the composer
client. Its 2.0 interface is generic:

  registerClient(string name, IDisplayConfigCallback cb)
      generates (int32 error, uint64 handle)                    # code 1
  perform(uint64 handle, uint32 op, vec<uint8> in, vec<handle> h)
      generates (int32 error, vec<uint8> out, vec<handle> h)    # code 2

with the ops and packed structs of display-commonsys
services/config/src/opcode_types.h and config_defs.h.

  display-mode.py list            configs: index, refresh rate, resolution
  display-mode.py get             active config index and refresh rate
  display-mode.py set HZ|#INDEX   switch (e.g. "set 60", "set 120", "set #1")
"""
import struct
import sys

import gbinder

IFACE = "vendor.display.config@2.0::IDisplayConfig"
CB_IFACE = "vendor.display.config@2.0::IDisplayConfigCallback"
FQNAME = IFACE + "/default"
TX_REGISTER_CLIENT, TX_PERFORM = 1, 2
OP_GET_CONFIG_COUNT, OP_GET_ACTIVE_CONFIG, OP_SET_ACTIVE_CONFIG = 3, 4, 5
OP_GET_DISPLAY_ATTRIBUTES = 6
OP_REFRESH_SCREEN = 10
DPY_PRIMARY = 1                       # DisplayType::kPrimary


def val(result):
    # python-gbinder readers return (ok, value)
    ok, v = result
    if not ok:
        raise RuntimeError("short binder reply")
    return v


class DisplayConfig:
    def __init__(self, name="stone-display-mode"):
        self.sm = gbinder.ServiceManager("/dev/hwbinder")
        remote, status = self.sm.get_service_sync(FQNAME)
        if remote is None:
            raise RuntimeError("%s not registered (status %s)" % (FQNAME, status))
        self.client = gbinder.Client(remote, IFACE)
        # The composer links to the callback's death to drop this client when
        # the process exits; it also calls unlinkToDeath() on it unchecked if
        # registration fails, so never pass a null callback.
        self.cb = self.sm.new_local_object(CB_IFACE, lambda req, code, flags: (None, 0))
        req = self.client.new_request()
        req.append_hidl_string(name)
        req.append_local_object(self.cb)
        reply, status = self.client.transact_sync_reply(TX_REGISTER_CLIENT, req)
        if reply is None:
            raise RuntimeError("registerClient failed: %s" % status)
        r = reply.init_reader()
        r.read_int32()                                  # HIDL status
        err = val(r.read_int32())
        self.handle = val(r.read_uint64())
        if err:
            raise RuntimeError("registerClient error %d" % err)

    def perform(self, op, data=b""):
        req = self.client.new_request()
        w = req.init_writer()
        w.append_int64(self.handle)
        w.append_int32(op)
        w.append_hidl_vec(data, len(data), 1)
        w.append_hidl_vec(None)
        reply, status = self.client.transact_sync_reply(TX_PERFORM, req)
        if reply is None:
            raise RuntimeError("perform(%d) failed: %s" % (op, status))
        r = reply.init_reader()
        r.read_int32()                                  # HIDL status
        err = val(r.read_int32())
        try:
            out = r.read_hidl_vec()
        except ValueError:                  # empty vec (set calls): no shape
            out = None
        return err, (bytes(out) if out is not None else b"")

    def count(self):
        err, out = self.perform(OP_GET_CONFIG_COUNT, struct.pack("<i", DPY_PRIMARY))
        if err:
            raise RuntimeError("GetConfigCount error %d" % err)
        return struct.unpack_from("<I", out)[0]

    def active(self):
        err, out = self.perform(OP_GET_ACTIVE_CONFIG, struct.pack("<i", DPY_PRIMARY))
        if err:
            raise RuntimeError("GetActiveConfig error %d" % err)
        return struct.unpack_from("<I", out)[0]

    def attributes(self, index):
        # AttributesParams {uint32 config_index; DisplayType dpy}
        err, out = self.perform(OP_GET_DISPLAY_ATTRIBUTES, struct.pack("<Ii", index, DPY_PRIMARY))
        if err:
            raise RuntimeError("GetDisplayAttributes(%d) error %d" % (index, err))
        # Attributes {uint32 vsync_period(ns); uint32 x_res, y_res;
        #             float x_dpi, y_dpi; DisplayPortType panel_type; bool is_yuv}
        vsync, xres, yres, xdpi, ydpi = struct.unpack_from("<IIIff", out)
        return {"index": index, "hz": round(1e9 / vsync, 2) if vsync else 0,
                "vsync_ns": vsync, "size": "%dx%d" % (xres, yres)}

    def configs(self):
        return [self.attributes(i) for i in range(self.count())]

    def set_active(self, index):
        # ConfigParams {DisplayType dpy; uint32 config}
        err, _ = self.perform(OP_SET_ACTIVE_CONFIG, struct.pack("<iI", DPY_PRIMARY, index))
        if err:
            raise RuntimeError("SetActiveConfig(%d) error %d" % (index, err))
        # The composer applies the new config at its next commit; ask its
        # client (Mir) for a frame so that happens now, not at the next
        # screen update.
        self.perform(OP_REFRESH_SCREEN)


def pick(configs, arg):
    if arg.startswith("#"):
        return int(arg[1:])
    hz = float(arg)
    best = min(configs, key=lambda c: abs(c["hz"] - hz))
    if abs(best["hz"] - hz) > 2:
        raise SystemExit("no %s Hz config; have %s" % (arg, sorted({c["hz"] for c in configs})))
    return best["index"]


def main():
    args = sys.argv[1:] or ["get"]
    dc = DisplayConfig()
    if args[0] == "list":
        act = dc.active()
        for c in dc.configs():
            print("%s#%d  %6.2f Hz  %s  vsync %d ns" % (
                "*" if c["index"] == act else " ", c["index"], c["hz"], c["size"], c["vsync_ns"]))
    elif args[0] == "get":
        act = dc.active()
        print("#%d %.2f Hz" % (act, dc.attributes(act)["hz"]))
    elif args[0] == "set" and len(args) == 2:
        index = pick(dc.configs(), args[1])
        dc.set_active(index)
        act = dc.active()
        print("#%d %.2f Hz" % (act, dc.attributes(act)["hz"]))
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
