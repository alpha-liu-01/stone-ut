"""In-call (downlink) volume for stone, used by call-audio-router.py.

Lomiri's volume keys (ayatana-indicator-sound) control the volume of the
"phone" media role while a stream with media.role=phone exists, corked or
not; on Halium devices pulseaudio-modules-droid provides one for the voice
call and hands its volume to the audio HAL. Here calls bypass the HAL, and
the DSP's own volume (the "Voice Rx Gain" control, VSS_IVOLUME_CMD_SET_STEP)
needs ACDB volume calibration that is not loaded: the DSP answers
ADSP_EFAILED ("voice volume failed" in the kernel log on every call). So:

- while a call is on, a corked (silent, never started) playback stream with
  media.role=phone is kept open; module-stream-restore gives it the saved
  phone role volume, and the indicator's volume keys change that;
- its volume is mapped to the codec's digital gain on the interpolator that
  carries the call to the active output (1 dB per step, 84 = 0 dB).

libpulse is used through ctypes on the router's GLib main loop
(libpulse-mainloop-glib), so changes arrive as events.
"""
import ctypes
import ctypes.util
import math
import os
import subprocess

# sink.primary port -> codec digital volume controls carrying the call.
# USB and Bluetooth calls leave the DSP for the device without passing the
# codec: their volume is the device's own.
ROUTE_CONTROLS = {
    "[Out] Earpiece": ["RX_RX0 Digital Volume"],
    "[Out] Speaker": ["RX_RX2 Digital Volume"],
    "[Out] Headphones": ["RX_RX0 Digital Volume", "RX_RX1 Digital Volume"],
}
UNITY = 84                    # 0 dB
MIN_DB = -40                  # lowest audible setting
MAX_DB_FILE = os.path.expanduser("~/.config/stone/call-volume-max-db")
MAX_DB_DEFAULT = 6
# The stream-restore default for the phone role (touch-stream-restore.table)
# is -15 dB; keep that at today's fixed level (0 dB codec gain).
DEFAULT_ROLE_DB = -15.0
MAIN_CARD = "hw:holiqrdsku1sndc"
# The phone role volume saved before this existed is arbitrary (it was 23 %,
# -38 dB, on the test phone, which would make calls far quieter than the
# fixed level they had). The first time the stream appears, the role is set
# to the default once; after that the user's choice is kept.
INIT_MARKER = os.path.expanduser("~/.config/stone/call-volume-initialized")

PA_VOLUME_NORM = 0x10000
PA_CONTEXT_READY = 4
PA_CONTEXT_FAILED = 5
PA_CONTEXT_TERMINATED = 6
PA_STREAM_READY = 2
PA_STREAM_START_CORKED = 0x0001
PA_SAMPLE_S16LE = 3
PA_SUBSCRIPTION_MASK_SINK_INPUT = 0x0004
PA_SUBSCRIPTION_EVENT_FACILITY_MASK = 0x000F
PA_SUBSCRIPTION_EVENT_TYPE_MASK = 0x0030
PA_SUBSCRIPTION_EVENT_SINK_INPUT = 0x0002
PA_SUBSCRIPTION_EVENT_REMOVE = 0x0020
PA_CHANNELS_MAX = 32


class SampleSpec(ctypes.Structure):
    _fields_ = [("format", ctypes.c_int), ("rate", ctypes.c_uint32),
                ("channels", ctypes.c_uint8)]


class ChannelMap(ctypes.Structure):
    _fields_ = [("channels", ctypes.c_uint8), ("map", ctypes.c_int * PA_CHANNELS_MAX)]


class CVolume(ctypes.Structure):
    _fields_ = [("channels", ctypes.c_uint8), ("values", ctypes.c_uint32 * PA_CHANNELS_MAX)]


class SinkInputInfo(ctypes.Structure):
    # The leading fields of pa_sink_input_info (pulse/introspect.h), up to
    # the ones read here; the struct is only ever accessed by pointer.
    _fields_ = [("index", ctypes.c_uint32), ("name", ctypes.c_char_p),
                ("owner_module", ctypes.c_uint32), ("client", ctypes.c_uint32),
                ("sink", ctypes.c_uint32), ("sample_spec", SampleSpec),
                ("channel_map", ChannelMap), ("volume", CVolume),
                ("buffer_usec", ctypes.c_uint64), ("sink_usec", ctypes.c_uint64),
                ("resample_method", ctypes.c_char_p), ("driver", ctypes.c_char_p),
                ("mute", ctypes.c_int)]


STATE_CB = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p)
SUBSCRIBE_CB = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_int, ctypes.c_uint32, ctypes.c_void_p)
SINK_INPUT_INFO_CB = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.POINTER(SinkInputInfo),
                                      ctypes.c_int, ctypes.c_void_p)
SUCCESS_CB = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p)


def _lib(name):
    return ctypes.CDLL(ctypes.util.find_library(name) or "lib%s.so.0" % name)


pa = _lib("pulse")
pa_glib = _lib("pulse-mainloop-glib")
pa_glib.pa_glib_mainloop_new.restype = ctypes.c_void_p
pa_glib.pa_glib_mainloop_new.argtypes = [ctypes.c_void_p]
pa_glib.pa_glib_mainloop_get_api.restype = ctypes.c_void_p
pa_glib.pa_glib_mainloop_get_api.argtypes = [ctypes.c_void_p]
for fn, res, args in (
        ("pa_context_new", ctypes.c_void_p, [ctypes.c_void_p, ctypes.c_char_p]),
        ("pa_context_connect", ctypes.c_int, [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_void_p]),
        ("pa_context_disconnect", None, [ctypes.c_void_p]),
        ("pa_context_unref", None, [ctypes.c_void_p]),
        ("pa_context_get_state", ctypes.c_int, [ctypes.c_void_p]),
        ("pa_context_set_state_callback", None, [ctypes.c_void_p, STATE_CB, ctypes.c_void_p]),
        ("pa_context_set_subscribe_callback", None, [ctypes.c_void_p, SUBSCRIBE_CB, ctypes.c_void_p]),
        ("pa_context_subscribe", ctypes.c_void_p, [ctypes.c_void_p, ctypes.c_int, SUCCESS_CB, ctypes.c_void_p]),
        ("pa_context_get_sink_input_info", ctypes.c_void_p,
         [ctypes.c_void_p, ctypes.c_uint32, SINK_INPUT_INFO_CB, ctypes.c_void_p]),
        ("pa_operation_unref", None, [ctypes.c_void_p]),
        ("pa_proplist_new", ctypes.c_void_p, []),
        ("pa_proplist_sets", ctypes.c_int, [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]),
        ("pa_proplist_free", None, [ctypes.c_void_p]),
        ("pa_stream_new_with_proplist", ctypes.c_void_p,
         [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(SampleSpec), ctypes.c_void_p, ctypes.c_void_p]),
        ("pa_stream_connect_playback", ctypes.c_int,
         [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p]),
        ("pa_stream_set_state_callback", None, [ctypes.c_void_p, STATE_CB, ctypes.c_void_p]),
        ("pa_stream_get_state", ctypes.c_int, [ctypes.c_void_p]),
        ("pa_stream_get_index", ctypes.c_uint32, [ctypes.c_void_p]),
        ("pa_stream_disconnect", ctypes.c_int, [ctypes.c_void_p]),
        ("pa_stream_unref", None, [ctypes.c_void_p]),
        ("pa_cvolume_avg", ctypes.c_uint32, [ctypes.POINTER(CVolume)])):
    f = getattr(pa, fn)
    f.restype, f.argtypes = res, args


def max_db():
    try:
        return max(0.0, min(20.0, float(open(MAX_DB_FILE).read().strip())))
    except (OSError, ValueError):
        return float(MAX_DB_DEFAULT)


def gain_for(volume, muted):
    """Codec control value for a phone-role volume (pa_volume_t)."""
    if muted or volume == 0:
        return 0                                   # -84 dB: silent
    f = volume / PA_VOLUME_NORM                    # the indicator's slider
    f0 = 10 ** (DEFAULT_ROLE_DB / 60.0)            # PulseAudio volumes are cubic
    if f <= f0:
        db = max(MIN_DB, 60.0 * math.log10(f / f0))
    else:
        db = min(1.0, (f - f0) / (1.0 - f0)) * max_db()
    return int(round(UNITY + db))


def set_controls(controls, value, log):
    for name in controls:
        r = subprocess.run(["amixer", "-q", "-D", MAIN_CARD, "cset", "name=%s" % name, str(value)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            log("call volume: %s: %s" % (name, r.stderr.strip()))


class CallVolume:
    """Keeps the phone-role stream while enabled and applies its volume."""

    def __init__(self, log):
        self.log = log
        self.ml = pa_glib.pa_glib_mainloop_new(None)   # default GMainContext
        self.api = pa_glib.pa_glib_mainloop_get_api(self.ml)
        self.ctx = None
        self.stream = None
        self.stream_index = None
        self.want = False
        self.port = None
        self.applied = {}          # control -> value we set
        self.volume = None         # (pa_volume_t, muted)
        # ctypes callbacks must stay referenced while PulseAudio may call them.
        self._ctx_state_cb = STATE_CB(self._on_ctx_state)
        self._stream_state_cb = STATE_CB(self._on_stream_state)
        self._subscribe_cb = SUBSCRIBE_CB(self._on_subscribe)
        self._info_cb = SINK_INPUT_INFO_CB(self._on_info)
        self._success_cb = SUCCESS_CB(lambda c, ok, u: None)

    # --- public -------------------------------------------------------------
    def set(self, want, port):
        """want: a call is up; port: sink.primary's active port."""
        if port != self.port:
            self.port = port
            self._apply()
        if want == self.want:
            return
        self.want = want
        if want:
            self._connect()
        else:
            self._close()

    def shutdown(self):
        self.want = False
        self._close()

    # --- PulseAudio ---------------------------------------------------------
    def _connect(self):
        if self.ctx is not None:
            if self.stream is None and pa.pa_context_get_state(self.ctx) == PA_CONTEXT_READY:
                self._open_stream()
            return
        self.ctx = pa.pa_context_new(self.api, b"stone call volume")
        pa.pa_context_set_state_callback(self.ctx, self._ctx_state_cb, None)
        if pa.pa_context_connect(self.ctx, None, 0, None) < 0:
            self.log("call volume: cannot connect to PulseAudio")
            self._drop_context()

    def _on_ctx_state(self, ctx, userdata):
        state = pa.pa_context_get_state(ctx)
        if state == PA_CONTEXT_READY:
            pa.pa_context_set_subscribe_callback(ctx, self._subscribe_cb, None)
            op = pa.pa_context_subscribe(ctx, PA_SUBSCRIPTION_MASK_SINK_INPUT, self._success_cb, None)
            if op:
                pa.pa_operation_unref(op)
            if self.want:
                self._open_stream()
        elif state in (PA_CONTEXT_FAILED, PA_CONTEXT_TERMINATED):
            if self.want:              # not our own close at the end of a call
                self.log("call volume: PulseAudio connection closed")
            self.stream, self.stream_index = None, None
            self._drop_context(disconnect=False)

    def _drop_context(self, disconnect=True):
        ctx, self.ctx = self.ctx, None
        if ctx:
            if disconnect:
                pa.pa_context_disconnect(ctx)
            pa.pa_context_unref(ctx)

    def _open_stream(self):
        props = pa.pa_proplist_new()
        for k, v in ((b"media.role", b"phone"), (b"media.name", b"Call volume"),
                     (b"application.name", b"stone call audio"),
                     (b"application.icon_name", b"phone")):
            pa.pa_proplist_sets(props, k, v)
        ss = SampleSpec(PA_SAMPLE_S16LE, 8000, 1)
        self.stream = pa.pa_stream_new_with_proplist(self.ctx, b"Call volume", ctypes.byref(ss), None, props)
        pa.pa_proplist_free(props)
        pa.pa_stream_set_state_callback(self.stream, self._stream_state_cb, None)
        # Corked from the start: it never plays, so it neither wakes the
        # speaker nor triggers module-role-cork.
        pa.pa_stream_connect_playback(self.stream, None, None, PA_STREAM_START_CORKED, None, None)

    def _on_stream_state(self, stream, userdata):
        if stream != self.stream:
            return
        if pa.pa_stream_get_state(stream) == PA_STREAM_READY:
            self.stream_index = pa.pa_stream_get_index(stream)
            self.log("call volume: phone role stream #%d" % self.stream_index)
            if not os.path.exists(INIT_MARKER):
                default = int(round(PA_VOLUME_NORM * 10 ** (DEFAULT_ROLE_DB / 60.0)))
                subprocess.run(["pactl", "set-sink-input-volume", str(self.stream_index), str(default)])
                subprocess.run(["pactl", "set-sink-input-mute", str(self.stream_index), "0"])
                try:
                    os.makedirs(os.path.dirname(INIT_MARKER), exist_ok=True)
                    open(INIT_MARKER, "w").write("phone role volume set to %d (%.0f dB)\n" % (default, DEFAULT_ROLE_DB))
                except OSError:
                    pass
                self.log("call volume: phone role volume initialized to %.0f dB" % DEFAULT_ROLE_DB)
            self._query()

    def _close(self):
        if self.stream is not None:
            pa.pa_stream_disconnect(self.stream)
            pa.pa_stream_unref(self.stream)
            self.stream, self.stream_index = None, None
        self._drop_context()
        self.volume = None
        self._apply()

    def _on_subscribe(self, ctx, event, index, userdata):
        facility = event & PA_SUBSCRIPTION_EVENT_FACILITY_MASK
        kind = event & PA_SUBSCRIPTION_EVENT_TYPE_MASK
        if facility == PA_SUBSCRIPTION_EVENT_SINK_INPUT and index == self.stream_index \
                and kind != PA_SUBSCRIPTION_EVENT_REMOVE:
            self._query()

    def _query(self):
        if self.ctx is None or self.stream_index is None:
            return
        op = pa.pa_context_get_sink_input_info(self.ctx, self.stream_index, self._info_cb, None)
        if op:
            pa.pa_operation_unref(op)

    def _on_info(self, ctx, info, eol, userdata):
        if eol or not info:
            return
        vol = pa.pa_cvolume_avg(ctypes.byref(info.contents.volume))
        muted = bool(info.contents.mute)
        if (vol, muted) != self.volume:
            self.volume = (vol, muted)
            self._apply()

    # --- codec --------------------------------------------------------------
    def _apply(self):
        """Set the active route's controls, and 0 dB everywhere else."""
        target = {}
        if self.want and self.volume is not None:
            vol, muted = self.volume
            value = gain_for(vol, muted)
            for name in ROUTE_CONTROLS.get(self.port, []):
                target[name] = value
        for name in list(self.applied):
            if name not in target:
                set_controls([name], UNITY, self.log)
                del self.applied[name]
        changed = {n: v for n, v in target.items() if self.applied.get(n) != v}
        if changed:
            for n, v in changed.items():
                set_controls([n], v, self.log)
            self.applied.update(changed)
            vol, muted = self.volume
            self.log("call volume: %d%%%s on %s -> %s" % (
                round(100 * vol / PA_VOLUME_NORM), " muted" if muted else "", self.port,
                ", ".join("%s=%d (%+d dB)" % (n, v, v - UNITY) for n, v in sorted(changed.items()))))
        elif self.want and self.volume is not None and self.port not in ROUTE_CONTROLS:
            pass   # USB/Bluetooth: the device's own volume
