#!/bin/sh
# Live install of the USB-at-boot fixes without a flash (needs root), and
# cleanup of the earlier tests (docs/roadmap-release.md item 2):
# - no usb-moded rescue mode (as a drop-in: the image's copy of
#   stone-sunstone.conf is put back at every boot, so the live test cannot
#   change that file);
# - the user-session MTP/adb reconnect watcher;
# - removes the boot trace, the system reconnect service and the Type-C test.
# The next image carries the same fixes and its init deletes the test files.
#
#   sudo sh /home/phablet/stone-usb-install.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
for u in stone-usb-boot-trace.service stone-usb-mtp-reconnect.service stone-usb-typec-kick.service; do
    systemctl disable "$u" 2>/dev/null || true
done
rm -f /etc/systemd/system/stone-usb-boot-trace.service /usr/local/sbin/stone-usb-boot-trace.sh \
    /etc/systemd/system/stone-usb-mtp-reconnect.service /usr/lib/stone/usb-mtp-reconnect.sh \
    /etc/systemd/system/stone-usb-typec-kick.service /usr/lib/stone/usb-typec-kick.sh
rm -rf /var/log/stone-usb-boot-trace
D=/etc/systemd/system/usb-moded.service.d
install -d -m 755 $D
printf '[Service]\n# Test only (tools/phone-debug/stone-usb-install.sh).\nEnvironment=USB_MODED_ARGS=\n' > $D/zz-stone-test-no-rescue.conf
install -d -m 755 /usr/lib/stone /etc/systemd/user/ubuntu-touch-session.target.wants
install -m 755 /home/phablet/usb-mtp-reconnect.py /usr/lib/stone/usb-mtp-reconnect.py
install -m 644 /home/phablet/stone-usb-mtp-reconnect.service /etc/systemd/user/stone-usb-mtp-reconnect.service
ln -sf ../stone-usb-mtp-reconnect.service /etc/systemd/user/ubuntu-touch-session.target.wants/stone-usb-mtp-reconnect.service
systemctl daemon-reload
systemctl show usb-moded -p Environment
ls -l /etc/systemd/user/ubuntu-touch-session.target.wants/ | grep -E "stone|mtp"
