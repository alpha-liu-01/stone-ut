#!/usr/bin/python3 -I
"""Tell PulseAudio whether a USB audio device can take the call route.

Calls reach a USB headset the way Android does it: the DSP plays the voice
downlink (and the card's media) on its USB_AUDIO_RX back end, and the
kernel's USB audio offload service (CONFIG_SND_USB_AUDIO_QMI) hands it the
device's endpoint. That route is the UCM device "USB" of the built-in card,
port "[Out] USB" of sink.primary, which lomiri-telephony-service offers in
the dialer while PulseAudio marks it available.

A USB headset's microphone works the same way in the other direction
(USB_AUDIO_TX, UCM device "USBMic", port "[In] USB").

Run by udev (72-stone-usb-audio.rules) when the controls of the built-in
card, of StoneJack or of a USB card appear, and when a sound card goes; the
last of those runs finds everything in place. It:
- creates the "USB Jack" and "USB Mic Jack" controls on the StoneJack card
  if needed (user-space controls: the kernel creates only the 3.5 mm ones
  there), the UCM JackControls of the USB devices;
- picks the first USB sound card that has a playback stream, and writes
  USB_AUDIO_RX dev_token (card << 16 | device << 8 | direction) and the
  format, rate and channels the DSP should use with it. The token is
  written raw: the control's range reads as 0..-1, and amixer/UCM clamp
  any value to 0xffffffff (the offload service then sees card 255);
- does the same for USB_AUDIO_TX with that card's capture stream (direction
  1), if it has one (many USB-C DAC dongles have none);
- sets each jack on if its stream exists, off otherwise.

usage: usb-audio-jack.py [--removed cardN]
"""
import ctypes
import glob
import os
import re
import subprocess
import sys

JACK_CARD = b"hw:StoneJack"
JACK_NAME = b"USB Jack"
MIC_JACK_NAME = b"USB Mic Jack"
MAIN_CARD = b"hw:holiqrdsku1sndc"  # the built-in card, by id
IFACE_CARD, IFACE_MIXER = 0, 2
# DSP back-end choices, best first.
FORMATS = ["S16_LE", "S24_LE", "S24_3LE", "S32_LE"]
RATES = [48000, 44100, 96000, 32000, 16000, 8000, 88200, 192000]
RATE_ITEMS = {8000: "KHZ_8", 11025: "KHZ_11P025", 16000: "KHZ_16",
              22050: "KHZ_22P05", 32000: "KHZ_32", 44100: "KHZ_44P1",
              48000: "KHZ_48", 88200: "KHZ_88P2", 96000: "KHZ_96",
              176400: "KHZ_176P4", 192000: "KHZ_192", 352800: "KHZ_352P8",
              384000: "KHZ_384"}
CHANNEL_ITEMS = ["One", "Two", "Three", "Four", "Five", "Six", "Seven",
                 "Eight"]

asound = ctypes.CDLL("libasound.so.2")
asound.snd_strerror.restype = ctypes.c_char_p


def log(msg):
    # udev's RUN output goes to the journal (systemd-udevd).
    print("usb-audio-jack: " + msg, file=sys.stderr, flush=True)


def ctl_open(name):
    ctl = ctypes.c_void_p()
    if asound.snd_ctl_open(ctypes.byref(ctl), name, 0) < 0:
        return None
    return ctl


def elem_id(iface, name):
    idp = ctypes.c_void_p()
    asound.snd_ctl_elem_id_malloc(ctypes.byref(idp))
    asound.snd_ctl_elem_id_set_interface(idp, iface)
    asound.snd_ctl_elem_id_set_name(idp, name)
    return idp


def write_int(ctl, iface, name, value):
    val = ctypes.c_void_p()
    asound.snd_ctl_elem_value_malloc(ctypes.byref(val))
    asound.snd_ctl_elem_value_set_id(val, elem_id(iface, name))
    asound.snd_ctl_elem_value_set_integer(val, 0, ctypes.c_long(value))
    ret = asound.snd_ctl_elem_write(ctl, val)
    asound.snd_ctl_elem_value_free(val)
    return ret


def set_jack(name, present):
    ctl = ctl_open(JACK_CARD)
    if ctl is None:
        log("no StoneJack card; USB call route stays unavailable")
        return
    idp = elem_id(IFACE_CARD, name)
    info = ctypes.c_void_p()
    asound.snd_ctl_elem_info_malloc(ctypes.byref(info))
    asound.snd_ctl_elem_info_set_id(info, idp)
    if asound.snd_ctl_elem_info(ctl, info) < 0:
        ret = asound.snd_ctl_elem_add_boolean(ctl, idp, 1)
        if ret < 0:
            log("cannot add %s: %s" % (name.decode(),
                                       asound.snd_strerror(ret).decode()))
    asound.snd_ctl_elem_info_free(info)
    write_int(ctl, IFACE_CARD, name, 1 if present else 0)
    asound.snd_ctl_close(ctl)


def stream_formats(stream_file, direction):
    """[(format, channels, [rates])] of the altsets of one direction
    ("Playback" or "Capture")."""
    text = open(stream_file).read()
    play = text.split(direction + ":", 1)
    if len(play) < 2:
        return []
    other = "Capture:" if direction == "Playback" else "Playback:"
    play = play[1].split(other, 1)[0]
    alts = []
    for block in play.split("Altset")[1:]:
        fmt = re.search(r"Format: (\S+)", block)
        ch = re.search(r"Channels: (\d+)", block)
        rates = re.search(r"Rates: ([^\n]+)", block)
        if not (fmt and ch and rates):
            continue
        rs = []
        if "-" in rates.group(1):  # continuous range "8000 - 96000"
            lo, hi = (int(x) for x in re.findall(r"\d+", rates.group(1))[:2])
            rs = [r for r in RATE_ITEMS if lo <= r <= hi]
        else:
            rs = [int(x) for x in re.findall(r"\d+", rates.group(1))]
        alts.append((fmt.group(1), int(ch.group(1)), rs))
    return alts


def pick(alts):
    for fmt in FORMATS:
        for rate in RATES:
            for a_fmt, ch, rates in alts:
                if a_fmt == fmt and rate in rates and 1 <= ch <= 8:
                    return fmt, rate, ch
    return None


def find_usb(removed, direction, only_card=None):
    for card_dir in sorted(glob.glob("/proc/asound/card[0-9]*")):
        card = os.path.basename(card_dir)
        if card == removed or not os.path.exists(card_dir + "/usbid"):
            continue
        num = int(card[4:])
        if only_card is not None and num != only_card:
            continue
        for stream in sorted(glob.glob(card_dir + "/stream[0-9]*")):
            choice = pick(stream_formats(stream, direction))
            if choice:
                dev = int(os.path.basename(stream)[6:])
                return num, dev, choice
    return None


def configure(port, usb, direction_bit):
    """Write the DSP back end settings for one USB stream."""
    num, dev, (fmt, rate, ch) = usb
    ctl = ctl_open(MAIN_CARD)
    token = num << 16 | dev << 8 | direction_bit
    ok = ctl is not None and \
        write_int(ctl, IFACE_MIXER, ("%s dev_token" % port).encode(),
                  token) >= 0
    if ctl is not None:
        asound.snd_ctl_close(ctl)
    for name, item in (("Format", fmt), ("SampleRate", RATE_ITEMS[rate]),
                       ("Channels", CHANNEL_ITEMS[ch - 1])):
        r = subprocess.run(["amixer", "-q", "-c", "holiqrdsku1sndc", "cset",
                            "name=%s %s" % (port, name), item])
        ok = ok and r.returncode == 0
    if ok:
        log("card %d device %d: %s %s %d Hz %d ch, token 0x%x"
            % (num, dev, port, fmt, rate, ch, token))
    else:
        log("card %d: could not configure %s" % (num, port))
    return ok


def main():
    removed = None
    if sys.argv[1:2] == ["--removed"] and len(sys.argv) > 2:
        removed = sys.argv[2]
    out = find_usb(removed, "Playback")
    # The mic only counts on the card that also plays (a headset).
    mic = find_usb(removed, "Capture", out[0]) if out else None
    out_ok = bool(out) and configure("USB_AUDIO_RX", out, 0)
    mic_ok = bool(mic) and configure("USB_AUDIO_TX", mic, 1)
    if not out:
        log("no USB playback device")
    elif not mic:
        log("card %d has no capture stream (no USB mic)" % out[0])
    set_jack(JACK_NAME, out_ok)
    set_jack(MIC_JACK_NAME, out_ok and mic_ok)


if __name__ == "__main__":
    main()
