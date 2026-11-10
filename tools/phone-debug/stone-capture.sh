#!/bin/sh
# Collect logs only root can read. Run on the phone as:
#   sudo sh /home/phablet/stone-capture.sh
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
D=/home/phablet/stone-capture
rm -rf "$D"; mkdir -p "$D"

# Kernel log of the previous (crashed) boot.
cp -a /sys/fs/pstore/. "$D/pstore/" 2>/dev/null || mkdir -p "$D/pstore"
ls -la /sys/fs/pstore > "$D/pstore.ls" 2>&1

# qcril has persist.vendor.radio.adb_log_on=1 since the last run, so the
# radio buffer has verbose data-call handling for this whole boot.
/android/system/bin/logcat -b radio -d -v threadtime > "$D/radio.txt" 2>&1
/android/system/bin/logcat -b main -b system -b crash -d -v threadtime > "$D/main.txt" 2>&1
dmesg > "$D/dmesg.txt" 2>&1

chown -R phablet:phablet "$D"
echo "saved to $D:"; ls -la "$D" "$D/pstore"
