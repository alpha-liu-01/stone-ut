#!/bin/sh
# Live install of the microSD mount-option fix without a flash (needs root).
# The boot image installs the same file from boot/ut-init/rootfs-overlay.
#
#   sudo sh /home/phablet/stone-sdcard-install.sh
#     Installs /etc/udisks2/mount_options.conf (vfat without "flush").
#     udisks reads it at the next mount: reboot, or take the card out and
#     put it back in.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
install -D -m 644 /home/phablet/mount_options.conf /etc/udisks2/mount_options.conf
echo "installed /etc/udisks2/mount_options.conf:"
grep -v '^#' /etc/udisks2/mount_options.conf | grep .
echo "current card mount (old options until it is mounted again):"
grep mmcblk /proc/mounts || echo "(card not mounted)"
