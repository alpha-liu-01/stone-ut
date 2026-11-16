#!/bin/sh
# Live install of the Bluetooth call volume (docs/roadmap-hardware-2.md,
# item 9, Bluetooth call volume). Run with sudo, not during a call:
#   sudo sh /home/phablet/stone-bt-call-volume-install.sh
# Installs call_volume.py and call-audio-router.py from
# /home/phablet/bt-volume-test (the image restores its own copies at the next
# boot) and restarts the call-audio router.
set -eu
T=/home/phablet/bt-volume-test
install -m 644 $T/call_volume.py /usr/lib/stone/call_volume.py
install -m 755 $T/call-audio-router.py /usr/lib/stone/call-audio-router.py
setpriv --reuid=32011 --regid=32011 --init-groups -- env XDG_RUNTIME_DIR=/run/user/32011 \
    systemctl --user restart stone-call-audio.service
sleep 2
setpriv --reuid=32011 --regid=32011 --init-groups -- env XDG_RUNTIME_DIR=/run/user/32011 \
    systemctl --user --no-pager status stone-call-audio.service | head -4
echo "stone-bt-call-volume-install: done; Ctrl+C is safe now" > /dev/tty 2>/dev/null || true
