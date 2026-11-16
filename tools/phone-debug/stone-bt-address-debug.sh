#!/bin/sh
# Where the Bluetooth address comes from (docs/roadmap-hardware-2.md,
# Bluetooth pairings). Read-only. Run with sudo:
#   sudo sh stone-bt-address-debug.sh > /home/phablet/bt-address.txt 2>&1
# Addresses are masked to their first and last byte (enough to tell the two
# byte orders apart).
m() { sed -E 's/\b([0-9A-Fa-f]{2})(:[0-9A-Fa-f]{2}){4}:([0-9A-Fa-f]{2})\b/\1:..:..:..:..:\3/g; s/\b([0-9A-Fa-f]{2})([0-9A-Fa-f]{8})([0-9A-Fa-f]{2})\b/\1........\3/g'; }
echo "== uptime: $(uptime -p)"
echo "== adapter now"; bluetoothctl list | m
echo "== board-address"; cat /var/lib/bluetooth/board-address | m
echo "== properties"
for p in persist.vendor.service.bdroid.bdaddr persist.service.bdroid.bdaddr ro.boot.btmacaddr ro.vendor.bt.bdaddr_path ro.bt.bdaddr_path vendor.bluetooth.soc ro.vendor.bluetooth.soc persist.vendor.qcom.bluetooth.soc; do
    echo "$p=$(getprop $p)"
done | m
echo "== persistent property store (Android /data)"
for f in /var/lib/android-data/property/persistent_properties /var/lib/android-data/property/persist.vendor.service.bdroid.bdaddr; do
    [ -e "$f" ] && { echo "$f: $(stat -c '%y' "$f" | cut -c1-19)"; strings "$f" | grep -i -A1 bdaddr | m; }
done
echo "== Xiaomi/Qualcomm address files"
for d in /mnt/vendor/persist/bluetooth /vendor/persist/bluetooth /persist/bluetooth /mnt/vendor/persist /var/lib/android-data/vendor/bluetooth /var/lib/android-data/misc/bluedroid /var/lib/android-data/vendor/bluedroid; do
    [ -d "$d" ] && { echo "-- $d"; ls -la "$d" 2>&1 | head -12; }
done
lxc-attach -n android -- /system/bin/sh -c 'ls -la /mnt/vendor/persist/bluetooth /mnt/vendor/persist/bluetooth/* 2>&1 | head -12; for f in /mnt/vendor/persist/bluetooth/*; do echo "$f: $(wc -c < "$f" 2>/dev/null) bytes"; done' 2>&1 | m
echo "== HAL log lines about the address (this boot)"
lxc-attach -n android -- /system/bin/logcat -d -b all 2>/dev/null | grep -i -E "bdaddr|bd_addr|bd addr|bd address|local addr|NVM|set_bdaddr|readBdAddr|bt_mac|btmac" | head -40 | m
echo "== bluebinder this boot"
journalctl -b -u bluebinder --no-pager | tail -15 | m
echo "== boots kept in the journal"
journalctl --list-boots --no-pager | tail -12
