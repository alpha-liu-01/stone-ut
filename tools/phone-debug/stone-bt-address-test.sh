#!/bin/sh
# Live test of the fixed Bluetooth address (docs/roadmap-hardware-2.md,
# Bluetooth pairings). Run with sudo:
#   sudo sh stone-bt-address-test.sh > /home/phablet/bt-address-test.txt 2>&1
# Writes the canonical address (the current persist.vendor.service.bdroid.bdaddr)
# to /data/vendor/bluetooth/bdaddr, sets ro.vendor.bt.bdaddr_path to it (it is
# unset; a ro property can be set once), restarts bluebinder so the HAL
# programs the controller again, and reports the adapter address and the
# paired devices. Until the next reboot only. Addresses are masked to their
# first and last byte.
set -u
trap '' HUP
m() { sed -E 's/\b([0-9A-Fa-f]{2})(:[0-9A-Fa-f]{2}){4}:([0-9A-Fa-f]{2})\b/\1:..:..:..:..:\3/g'; }
DATA=/var/lib/android-data/vendor/bluetooth
addr=$(getprop persist.vendor.service.bdroid.bdaddr | tr 'A-F' 'a-f')
echo "$addr" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || { echo "no valid persist address: '$addr'" | m; exit 1; }

echo "== before"
bluetoothctl list | m
echo "canonical (property): $addr" | m

printf '%s\n' "$addr" > $DATA/bdaddr
chown 1002:1002 $DATA/bdaddr
chmod 0644 $DATA/bdaddr
lxc-attach -n android -- /system/bin/setprop ro.vendor.bt.bdaddr_path /data/vendor/bluetooth/bdaddr
echo "ro.vendor.bt.bdaddr_path=$(getprop ro.vendor.bt.bdaddr_path)"
lxc-attach -n android -- /system/bin/sh -c 'ls -l /data/vendor/bluetooth/bdaddr'

echo "== restarting bluebinder"
systemctl restart bluebinder.service
i=0
while ! bluetoothctl list | grep -q Controller && [ $i -lt 30 ]; do sleep 1; i=$((i + 1)); done
sleep 3
echo "== after ($i s)"
bluetoothctl list | m
bluetoothctl show | grep -E 'Powered'
echo "-- paired devices now:"
bluetoothctl devices Paired | m
echo "-- HAL log about the address:"
lxc-attach -n android -- /system/bin/logcat -d -b all 2>/dev/null | grep -i -E "bdaddr|bd address|BD Address|MODEM_NV|random BDA|HCI_WRITE_BD" | tail -12 | m
echo "stone-bt-address-test: done; Ctrl+C is safe now" > /dev/tty 2>/dev/null || true
