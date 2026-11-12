#!/bin/sh
# Live install of the sensors fixes without a flash (needs root). The boot
# image installs the same files from boot/ut-init/rootfs-overlay.
#
#   sudo sh /home/phablet/stone-sensors-install.sh
#     - /usr/share/stone/gbinder-api34.conf and the sensorfwd drop-in
#       (sensorfwd talks to the AIDL sensors HAL)
#     - the repowerd drop-in (start after sensorfwd) and
#       /usr/share/repowerd/device-configs/config-stone.xml (automatic
#       brightness curve from the vendor overlay)
#     Restarts sensorfwd, then repowerd (the screen may blink once).
set -eu
SRC=/home/phablet
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
install -D -m 644 $SRC/gbinder-api34.conf /usr/share/stone/gbinder-api34.conf
install -D -m 644 $SRC/zz-stone-gbinder.conf /etc/systemd/system/sensorfwd.service.d/zz-stone-gbinder.conf
install -D -m 644 $SRC/zz-stone-sensorfw.conf /etc/systemd/system/repowerd.service.d/zz-stone-sensorfw.conf
install -D -m 644 $SRC/config-stone.xml /usr/share/repowerd/device-configs/config-stone.xml
systemctl daemon-reload
systemctl restart sensorfwd.service
echo "sensorfwd: $(systemctl is-active sensorfwd.service)"
systemctl restart repowerd.service
echo "repowerd: $(systemctl is-active repowerd.service)"
journalctl -u repowerd.service -b --no-pager | tail -8
