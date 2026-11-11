#!/usr/bin/env python3
"""Run a GStreamer pipeline on the phone without gst-launch-1.0.

The rootfs has neither gstreamer1.0-tools nor the Gst GObject-introspection
data, so this drives libgstreamer-1.0 through ctypes.

  python3 gst-decode-test.py 'PIPELINE' [seconds]
    Runs until EOS, error or the time limit, then prints the state reached,
    the wall time and the frames that reached an element named "sink"
    (a fakesink with signal-handoffs is not needed: it counts buffers
    through a pad probe on sink's sink pad).

  python3 gst-decode-test.py --playbin FILE [seconds]
    playbin with fakesink as video and audio sink (sync=true, so it plays
    in real time); GST_DEBUG=decodebin*:4 or similar shows what it picks.

Set GST_DEBUG yourself for details, e.g. GST_DEBUG=amc*:6,hybris*:6.
"""
import ctypes
import ctypes.util
import os
import sys
import time

gst = ctypes.CDLL("libgstreamer-1.0.so.0")
gobject = ctypes.CDLL("libgobject-2.0.so.0")

gst.gst_init.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
gst.gst_parse_launch.restype = ctypes.c_void_p
gst.gst_parse_launch.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
gst.gst_element_set_state.argtypes = [ctypes.c_void_p, ctypes.c_int]
gst.gst_element_get_state.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int),
                                      ctypes.POINTER(ctypes.c_int), ctypes.c_uint64]
gst.gst_element_get_bus.restype = ctypes.c_void_p
gst.gst_element_get_bus.argtypes = [ctypes.c_void_p]
gst.gst_bus_timed_pop_filtered.restype = ctypes.c_void_p
gst.gst_bus_timed_pop_filtered.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int]
gst.gst_bin_get_by_name.restype = ctypes.c_void_p
gst.gst_bin_get_by_name.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
gst.gst_element_get_static_pad.restype = ctypes.c_void_p
gst.gst_element_get_static_pad.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
PROBE = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
gst.gst_pad_add_probe.argtypes = [ctypes.c_void_p, ctypes.c_int, PROBE, ctypes.c_void_p, ctypes.c_void_p]
gst.gst_message_parse_error.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p),
                                        ctypes.POINTER(ctypes.c_char_p)]
gst.gst_object_unref.argtypes = [ctypes.c_void_p]
gst.gst_message_unref = getattr(gst, "gst_mini_object_unref")
gst.gst_message_unref.argtypes = [ctypes.c_void_p]
gst.gst_element_query_position.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_int64)]


class GError(ctypes.Structure):
    _fields_ = [("domain", ctypes.c_uint32), ("code", ctypes.c_int), ("message", ctypes.c_char_p)]


MSG_EOS, MSG_ERROR = 1 << 0, 1 << 1
STATE_NULL, STATE_PLAYING = 1, 4
PROBE_TYPE_BUFFER = 1 << 4
FORMAT_TIME = 3


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    if args[0] == "--playbin":
        uri = "file://" + os.path.abspath(args[1])
        desc = ("playbin name=pb uri=\"%s\" video-sink=\"fakesink name=sink sync=true\" "
                "audio-sink=\"fakesink sync=true\"" % uri.replace('"', '\\"'))
        limit = float(args[2]) if len(args) > 2 else 20
    else:
        desc = args[0]
        limit = float(args[1]) if len(args) > 1 else 60
    gst.gst_init(None, None)
    err = ctypes.c_void_p()
    pipe = gst.gst_parse_launch(desc.encode(), ctypes.byref(err))
    if err.value:
        print("parse error:", ctypes.cast(err, ctypes.POINTER(GError)).contents.message.decode())
        if not pipe:
            sys.exit(1)
    frames = [0, None, None]

    @PROBE
    def on_buffer(pad, info, user):
        now = time.monotonic()
        if frames[1] is None:
            frames[1] = now
        frames[2] = now
        frames[0] += 1
        return 1  # GST_PAD_PROBE_OK

    sink = gst.gst_bin_get_by_name(pipe, b"sink")
    if sink:
        pad = gst.gst_element_get_static_pad(sink, b"sink")
        gst.gst_pad_add_probe(pad, PROBE_TYPE_BUFFER, on_buffer, None, None)
    t0 = time.monotonic()
    gst.gst_element_set_state(pipe, STATE_PLAYING)
    bus = gst.gst_element_get_bus(pipe)
    result = "time limit"
    while time.monotonic() - t0 < limit:
        msg = gst.gst_bus_timed_pop_filtered(bus, 200 * 1000 * 1000, MSG_EOS | MSG_ERROR)
        if not msg:
            continue
        e = ctypes.c_void_p()
        dbg = ctypes.c_char_p()
        # GstMessage.type follows the 64-byte GstMiniObject on 64-bit.
        msg_type = ctypes.c_uint32.from_address(msg + 0x40).value
        if msg_type & MSG_ERROR:
            gst.gst_message_parse_error(msg, ctypes.byref(e), ctypes.byref(dbg))
            ge = ctypes.cast(e, ctypes.POINTER(GError)).contents
            result = "ERROR: %s (%s)" % (ge.message.decode(), (dbg.value or b"").decode()[:300])
        else:
            result = "EOS"
        gst.gst_message_unref(msg)
        break
    wall = time.monotonic() - t0
    pos = ctypes.c_int64(-1)
    gst.gst_element_query_position(pipe, FORMAT_TIME, ctypes.byref(pos))
    gst.gst_element_set_state(pipe, STATE_NULL)
    span = (frames[2] - frames[1]) if frames[1] and frames[2] else 0
    print("result: %s; wall %.1f s; position %.1f s; frames at sink %d%s" % (
        result, wall, pos.value / 1e9 if pos.value >= 0 else -1, frames[0],
        "; %.1f fps" % (frames[0] / span) if span > 0 else ""))


if __name__ == "__main__":
    main()
