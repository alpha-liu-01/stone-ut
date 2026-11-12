#!/bin/sh
# Live install of the GNSS fix without a flash (needs root). The boot image
# installs the same files from boot/ut-init/rootfs-overlay.
#
#   sudo sh /home/phablet/stone-gnss-install.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
install -m 755 /home/phablet/gnss-netstate.py /usr/lib/stone/gnss-netstate.py
install -m 644 /home/phablet/stone-gnss-netstate.service /etc/systemd/system/stone-gnss-netstate.service
systemctl daemon-reload
systemctl enable stone-gnss-netstate.service
systemctl restart stone-gnss-netstate.service
sleep 3
systemctl --no-pager status stone-gnss-netstate.service | head -4
journalctl -u stone-gnss-netstate.service -b --no-pager | tail -4
