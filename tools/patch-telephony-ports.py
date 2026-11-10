#!/usr/bin/env python3
"""Teach lomiri-telephony-service-handler the UCM port names.

telephony-service chooses the call audio output (earpiece, speaker,
Bluetooth) by switching PulseAudio sink/source ports, and it only knows the
port names of the droid card ("output-earpiece", ...). The droid card cannot
work on this device (32-bit vendor audio HAL, see roadmap-hardware.md items 3
and 5), so the ports come from the UCM profile in
/usr/share/stone/ucm2/stone/HiFi.conf, and PulseAudio names UCM ports
"[Out] <device>" / "[In] <device>".

This replaces nine port-name string constants in .rodata in place. Every
new name is shorter than the old one and is padded with NULs. The code only
references the start of each string (checked with llvm-objdump: no adrp/add
pair points inside them) and the short words the handler also uses
("earpiece", "speaker", "bluetooth") are separate copies, so nothing else
changes. Of the wired names, "output-wired_headphone" (any 3.5 mm plug) and
"input-wired_headset" (its mic) are mapped; "output-wired_headset" stays
unmatched, so the handler always uses the headphone port as the wired
output. "output-usb_device" is mapped to the UCM USB device (the DSP's
USB offload route; the handler treats it like wired headphones) and
"input-usb_headset" to the USBMic device, which the handler takes as the
wired mic whenever it is available ("output-usb_headset" stays unmatched).

The output must be installed in /usr/bin (as
lomiri-telephony-service-handler-stone): the handler only considers itself
installed, and finds its protocol files, when it runs from there. A copy in
another directory waits twice 25 s for its own D-Bus name and then never
handles a call (seen on the phone: no outgoing calls, incoming calls stuck at
0:00 and impossible to hang up).

Applies only to the exact lomiri-telephony-service 0.6.2+0~20260728091107.2
binary (input and output SHA256 are checked).

usage: patch-telephony-ports.py IN OUT
"""
import hashlib
import sys

IN_SHA256 = "f369e392762191d0469e2ecc512a2c03d016e2bca7374cb18ca03295c072d639"
OUT_SHA256 = "bdecab3799fb2856e36a8953e598290860ef5837430554a4829a79dd85dae298"

# offset in the file (== vaddr, .rodata is mapped 1:1), old, new
PATCHES = [
    (0x847b8, b"output-earpiece", b"[Out] Earpiece"),
    (0x847e8, b"output-speaker", b"[Out] Speaker"),
    (0x84800, b"output-bluetooth_sco", b"[Out] Bluetooth"),
    (0x84288, b"input-builtin_mic", b"[In] Mic"),
    (0x842d8, b"input-bluetooth_sco_headset", b"[In] BluetoothMic"),
    # 3.5 mm jack. Counted as present unless PulseAudio says the port is
    # unavailable, so the UCM devices need working jack detection.
    (0x84108, b"output-wired_headphone", b"[Out] Headphones"),
    (0x842b0, b"input-wired_headset", b"[In] Headset"),
    # USB headphones through the DSP (USB audio offload). Used only while
    # PulseAudio marks the port available ("USB Jack", usb-audio-jack.py).
    (0x84138, b"output-usb_device", b"[Out] USB"),
    # Its mic (USB_AUDIO_TX), when the USB card has one ("USB Mic Jack").
    (0x842f8, b"input-usb_headset", b"[In] USBMic"),
]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    data = bytearray(open(sys.argv[1], "rb").read())
    if hashlib.sha256(data).hexdigest() != IN_SHA256:
        sys.exit("%s: unexpected telephony-service-handler build, not patching"
                 % sys.argv[1])
    for off, old, new in PATCHES:
        assert len(new) <= len(old)
        assert data[off:off + len(old) + 1] == old + b"\0", hex(off)
        data[off:off + len(old)] = new.ljust(len(old), b"\0")
    digest = hashlib.sha256(data).hexdigest()
    if digest != OUT_SHA256:
        sys.exit("patched result does not match the tested binary")
    with open(sys.argv[2], "wb") as f:
        f.write(data)


if __name__ == "__main__":
    main()
