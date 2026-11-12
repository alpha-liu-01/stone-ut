#!/bin/sh
# Live install of the logcat wrapper and the logd watchdog without a flash
# (needs root). The boot image installs the same files from the overlay.
#   sudo sh /home/phablet/stone-logd-fix-install.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
install -m 755 /home/phablet/logcat /usr/bin/logcat
install -m 755 /home/phablet/logd-watchdog.py /usr/lib/stone/logd-watchdog.py
install -m 644 /home/phablet/stone-logd-watchdog.service /etc/systemd/system/stone-logd-watchdog.service
systemctl daemon-reload
systemctl enable stone-logd-watchdog.service
systemctl restart stone-logd-watchdog.service
systemctl is-active stone-logd-watchdog.service
