#!/bin/sh
# Live install of the fingerprint fix without a flash (needs root). The boot
# image installs the same files from boot/ut-init/rootfs-overlay.
#
#   sudo sh /home/phablet/stone-fingerprint-install.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
S=/home/phablet/stone-fp
install -d -m 755 /usr/lib/stone/biometryd /etc/systemd/system/biometryd.service.d
install -m 755 $S/biometryd /usr/lib/stone/biometryd/biometryd
install -m 644 $S/libbiometry.so.2 /usr/lib/stone/biometryd/libbiometry.so.2
install -m 644 $S/zz-stone-biometryd.conf /etc/systemd/system/biometryd.service.d/zz-stone-biometryd.conf
systemctl daemon-reload
systemctl restart biometryd
sleep 3
systemctl --no-pager status biometryd | head -5
journalctl -u biometryd -n 15 --no-pager -o cat
echo "== query through D-Bus as phablet (what System Settings does):"
runuser -u phablet -- env XDG_RUNTIME_DIR=/run/user/32011 QT_QPA_PLATFORM=minimal QT_SELECT=qt5 \
    timeout 20 qmlscene /home/phablet/fp-probe.qml 2>&1 | grep -E "qml:|terminate|what"
