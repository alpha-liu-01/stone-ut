#!/bin/sh
# Live install of the NFC presence check without a flash (needs root). The
# boot image installs the same file from boot/ut-init/rootfs-overlay.
#
#   sudo sh /home/phablet/stone-nfc-install.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
install -d -m 755 /etc/systemd/system/nfcd.service.d
install -m 644 /home/phablet/zz-stone-nfc-hw.conf /etc/systemd/system/nfcd.service.d/zz-stone-nfc-hw.conf
systemctl daemon-reload
# Re-evaluate the condition: stop it, then start it as boot would.
systemctl stop nfcd.service
systemctl start nfcd.service || true
systemctl --no-pager status nfcd.service | head -5
ls -l /dev/st21nfc /dev/nq-nci /dev/nfc-nci 2>&1 | sed 's/^/  /'
