#!/bin/sh
# Live install of the in-call volume fix without a flash (needs root). The
# boot image installs the same files from boot/ut-init/rootfs-overlay.
# Do not run it during a call (it restarts the call audio router).
#
#   sudo sh /home/phablet/stone-call-volume-install.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
install -m 644 /home/phablet/stone-cv/call_volume.py /usr/lib/stone/call_volume.py
install -m 755 /home/phablet/stone-cv/call-audio-router.py /usr/lib/stone/call-audio-router.py
runuser -u phablet -- env XDG_RUNTIME_DIR=/run/user/32011 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/32011/bus \
    systemctl --user restart stone-call-audio.service
sleep 2
runuser -u phablet -- env XDG_RUNTIME_DIR=/run/user/32011 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/32011/bus \
    systemctl --user --no-pager status stone-call-audio.service | head -4
