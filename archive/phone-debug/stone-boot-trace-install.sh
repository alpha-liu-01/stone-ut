#!/bin/sh
# Test only: trace the next boots (normal and charger mode) into
# /var/log/stone-boot-trace/, with usb-moded's debug log. Undo: --remove.
# Names differ from the earlier USB trace, whose files the init now deletes.
#
#   sudo sh /home/phablet/stone-boot-trace-install.sh [--remove]
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
U=/etc/systemd/system/stone-boot-trace.service
DI=/etc/systemd/system/usb-moded.service.d/zz-stone-debug.conf
# The image's overlay puts its own /usr/lib/stone/usb-mtp-reconnect.py back at
# every boot, so the updated watcher is tested from another path.
W=/usr/local/lib/stone-test/usb-mtp-reconnect.py
WD=/etc/systemd/user/stone-usb-mtp-reconnect.service.d/zz-stone-test.conf
if [ "${1:-}" = --remove ]; then
    systemctl disable stone-boot-trace.service 2>/dev/null || true
    rm -f $U $DI /usr/local/sbin/stone-boot-trace.sh /run/usb-moded/zz-stone-debug.conf $W $WD
    systemctl daemon-reload
    echo removed; exit 0
fi
install -m 755 /home/phablet/stone-boot-trace.sh /usr/local/sbin/stone-boot-trace.sh
cat > $U <<'EOT'
[Unit]
Description=stone test: trace USB and charging during boot
DefaultDependencies=no
After=systemd-journald.service local-fs.target
Before=usb-moded.service

[Service]
Type=simple
# Done before usb-moded may start (ExecStartPre completes before the unit is up).
ExecStartPre=/bin/sh -c 'mkdir -p /run/usb-moded; echo USB_MODED_ARGS=-D > /run/usb-moded/zz-stone-debug.conf'
ExecStart=/bin/sh /usr/local/sbin/stone-boot-trace.sh

[Install]
WantedBy=basic.target charger.target
EOT
# usb-moded -D now comes from /run/usb-moded (written by the trace at boot).
rm -f $DI
# Keep the earlier traces: they hold the previous charger test.
# The fix under test: adbd's start job waits for the FunctionFS descriptors
# (same file and path as in the next image).
install -d -m 755 /etc/systemd/system/adbd.service.d
install -m 644 /home/phablet/zz-stone-ffs-ready.conf /etc/systemd/system/adbd.service.d/zz-stone-ffs-ready.conf
install -d -m 755 /usr/local/lib/stone-test "$(dirname $WD)"
install -m 755 /home/phablet/usb-mtp-reconnect.py $W
printf '[Service]\n# Test only (stone-boot-trace-install.sh).\nExecStart=\nExecStart=/usr/bin/python3 -I %s\n' $W > $WD
systemctl daemon-reload
systemctl enable stone-boot-trace.service
systemctl is-enabled stone-boot-trace.service
systemctl show adbd.service -p ExecStartPost | cut -c1-120
