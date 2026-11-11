#!/bin/sh
# Live install of the SIM 2 call audio fix without a flash (needs root). The
# boot image installs the same files from boot/ut-init/rootfs-overlay.
# Not during a call: it restarts PulseAudio (to reload the UCM profile) and
# the call audio router.
#
#   sudo sh /home/phablet/stone-sim2-voice-install.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
S=/home/phablet/stone-sim2
install -m 644 $S/HiFi.conf /usr/share/stone/ucm2/stone/HiFi.conf
install -m 755 $S/call-audio.sh /usr/lib/stone/call-audio.sh
install -m 755 $S/call-audio-router.py /usr/lib/stone/call-audio-router.py
install -m 644 $S/call_volume.py /usr/lib/stone/call_volume.py
U="runuser -u phablet -- env XDG_RUNTIME_DIR=/run/user/32011 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/32011/bus"
$U systemctl --user restart pulseaudio.service
sleep 3
$U systemctl --user restart stone-call-audio.service
sleep 2
$U pactl list short sinks | grep -E "sink.primary" || echo "WARNING: no sink.primary"
$U systemctl --user --no-pager status stone-call-audio.service | head -3
