#!/usr/bin/python3 -I
"""Open the VoiceMMode1 front end (hw:holiqrdsku1sndc,2) in both directions, start it,
and hold it until SIGTERM. Never read or write samples.

msm-pcm-voice-v2 is hostless: it has no .copy or .pointer op and no DMA
buffer, so the ADSP moves the audio and the host only opens, configures and
starts the PCM (the Android HAL does exactly that with tinyalsa). Writing to
it, as aplay does, makes ALSA copy into a NULL dma_area -> kernel oops ->
panic_on_oops -> the phone resets.

Once both directions are prepared, msm_pcm_prepare() calls
voc_start_voice_call() for the VoiceMMode1 session.

usage: voice-pcm-hold.py [DEVICE]   (default hw:holiqrdsku1sndc,2)
"""
import ctypes
import signal
import sys

DEVICE = (sys.argv[1] if len(sys.argv) > 1 else "hw:holiqrdsku1sndc,2").encode()
SND_PCM_STREAM_PLAYBACK, SND_PCM_STREAM_CAPTURE = 0, 1
SND_PCM_FORMAT_S16_LE = 2
SND_PCM_ACCESS_RW_INTERLEAVED = 3
RATE, CHANNELS, LATENCY_US = 8000, 1, 40000   # HAL: 8 kHz mono, 2 x 160 frames

asound = ctypes.CDLL("libasound.so.2")
asound.snd_strerror.restype = ctypes.c_char_p
pcm_t = ctypes.c_void_p


def check(ret, what):
    if ret < 0:
        raise RuntimeError("%s: %s" % (what, asound.snd_strerror(ret).decode()))
    return ret


def open_started(stream):
    pcm = pcm_t()
    check(asound.snd_pcm_open(ctypes.byref(pcm), DEVICE, stream, 0), "open")
    check(asound.snd_pcm_set_params(pcm, SND_PCM_FORMAT_S16_LE,
                                    SND_PCM_ACCESS_RW_INTERLEAVED, CHANNELS,
                                    RATE, 0, LATENCY_US), "set_params")
    # No data will ever be queued: never stop on "underrun"/"overrun", and
    # do not wait for data before starting.
    sw = ctypes.c_void_p()
    check(asound.snd_pcm_sw_params_malloc(ctypes.byref(sw)), "sw malloc")
    check(asound.snd_pcm_sw_params_current(pcm, sw), "sw current")
    boundary = ctypes.c_ulong()
    check(asound.snd_pcm_sw_params_get_boundary(sw, ctypes.byref(boundary)), "boundary")
    check(asound.snd_pcm_sw_params_set_stop_threshold(pcm, sw, boundary), "stop threshold")
    check(asound.snd_pcm_sw_params_set_start_threshold(pcm, sw, ctypes.c_ulong(1)), "start threshold")
    check(asound.snd_pcm_sw_params(pcm, sw), "sw params")
    asound.snd_pcm_sw_params_free(sw)
    check(asound.snd_pcm_prepare(pcm), "prepare")
    return pcm


signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
pcms = []
try:
    which = sys.argv[2] if len(sys.argv) > 2 else "both"   # debugging: rx|tx|both
    if which in ("rx", "both"):
        pcms.append(("rx", open_started(SND_PCM_STREAM_PLAYBACK)))
    if which in ("tx", "both"):
        pcms.append(("tx", open_started(SND_PCM_STREAM_CAPTURE)))
    for name, pcm in pcms:
        check(asound.snd_pcm_start(pcm), "start " + name)
    print("voice pcm %s started (%s)" % (DEVICE.decode(), which), flush=True)
    signal.sigwait({signal.SIGTERM, signal.SIGINT})
except RuntimeError as e:
    print("voice pcm: %s" % e, file=sys.stderr, flush=True)
    sys.exit(1)
finally:
    for name, pcm in pcms:
        asound.snd_pcm_drop(pcm)
        asound.snd_pcm_close(pcm)
