#!/usr/bin/python3 -I
"""Write an integer ALSA control without reading it first.

The Qualcomm voice controls ("Voice Tx Mute", "Voice Rx Gain", ...) are
write-only multi-value controls: {value, vsid, ramp_ms}. amixer cset reads
the element before writing and gives up ("Cannot read the given element").

usage: ctl-write.py [-c CARD] NAME V1 [V2 ...]   (values may be negative or
       0x-prefixed; 0xFFFFFFFF = ALL_SESSION_VSID)
"""
import ctypes
import sys

args = sys.argv[1:]
card = "hw:holiqrdsku1sndc"  # the built-in card, by id
if args[:1] == ["-c"]:
    card = "hw:" + args[1]
    args = args[2:]
if len(args) < 2:
    sys.exit(__doc__)
name, values = args[0], [int(v, 0) for v in args[1:]]

asound = ctypes.CDLL("libasound.so.2")
asound.snd_strerror.restype = ctypes.c_char_p
SND_CTL_ELEM_IFACE_MIXER = 2


def check(ret, what):
    if ret < 0:
        sys.exit("%s: %s: %s" % (name, what, asound.snd_strerror(ret).decode()))


ctl = ctypes.c_void_p()
check(asound.snd_ctl_open(ctypes.byref(ctl), card.encode(), 0), "open")
val = ctypes.c_void_p()
check(asound.snd_ctl_elem_value_malloc(ctypes.byref(val)), "malloc")
asound.snd_ctl_elem_value_set_interface(val, SND_CTL_ELEM_IFACE_MIXER)
asound.snd_ctl_elem_value_set_name(val, name.encode())
for i, v in enumerate(values):
    # long on arm64; 0xFFFFFFFF stays 4294967295, which the driver reads as u32.
    asound.snd_ctl_elem_value_set_integer(val, ctypes.c_uint(i), ctypes.c_long(v))
check(asound.snd_ctl_elem_write(ctl, val), "write")
asound.snd_ctl_elem_value_free(val)
asound.snd_ctl_close(ctl)
