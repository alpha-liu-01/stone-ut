#!/bin/sh
# Live install of the clock guard without a flash (needs root). The boot
# image installs the same files from boot/ut-init/rootfs-overlay (and its init
# also sets the clock before systemd starts, which a live install cannot do).
#   sudo sh /home/phablet/stone-clock-guard-install.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
install -m 755 /home/phablet/clock-guard.py /usr/lib/stone/clock-guard.py
install -m 644 /home/phablet/stone-clock-guard.service /etc/systemd/system/stone-clock-guard.service
systemctl daemon-reload
systemctl enable stone-clock-guard.service
systemctl start stone-clock-guard.service
systemctl is-active stone-clock-guard.service
