#!/bin/sh
# Live install of the MMS-over-Wi-Fi fix without a flash (needs root). The
# boot image installs the same files from boot/ut-init/rootfs-overlay.
#
#   sudo sh /home/phablet/stone-mms-route-install.sh
#     Installs mms-route.py, its unit, the dnsmasq hostsdir drop-in and the
#     tmpfiles entry, restarts NetworkManager's dnsmasq (NM starts it again)
#     and the service, then shows the routes, the hosts file and a lookup.
set -eu
SRC=/home/phablet
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
install -m 755 $SRC/mms-route.py /usr/lib/stone/mms-route.py
install -m 644 $SRC/stone-mms-route.service /etc/systemd/system/stone-mms-route.service
install -m 644 $SRC/20-stone-mms.conf /etc/NetworkManager/dnsmasq.d/20-stone-mms.conf
install -m 644 $SRC/stone-mms.conf /usr/lib/tmpfiles.d/stone-mms.conf
systemd-tmpfiles --create /usr/lib/tmpfiles.d/stone-mms.conf
systemctl daemon-reload
systemctl enable stone-mms-route.service
pkill -f 'dnsmasq.*NetworkManager' || true
systemctl restart stone-mms-route.service
sleep 6
echo "== dnsmasq"; journalctl -b --no-pager -t dnsmasq | tail -4
echo "== service"; journalctl -u stone-mms-route -b --no-pager | tail -12
echo "== routes"; ip -4 route
echo "== hosts"; cat /run/stone-mms/mms-hosts
echo "== lookup"; getent hosts mmsproxy.mobile.bm mms.mobile.bm || echo "lookup failed"
