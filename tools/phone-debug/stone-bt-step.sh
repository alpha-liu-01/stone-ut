#!/bin/sh
# Test helper (needs root): stream the Android log (logd is only reachable
# inside the container) and the Bluetooth trace for a few minutes, to catch the
# Bluetooth HAL dying while Bluetooth is off.
#   sudo sh /home/phablet/stone-bt-step.sh [seconds]
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
SECS=${1:-300}
O=/home/phablet/bt-hal-log; rm -rf $O; mkdir -p $O
# Check first that logcat answers inside the container.
lxc-attach -n android -- /system/bin/logcat -d -t 3 > $O/logcat-check.txt 2>&1
echo "logcat check: rc=$? $(wc -l < $O/logcat-check.txt) lines"
head -3 $O/logcat-check.txt
systemd-run --unit=stone-bt-logcat --collect -p RuntimeMaxSec=$SECS \
    /bin/sh -c "lxc-attach -n android -- /system/bin/logcat -b all -v monotonic > $O/logcat.txt 2>&1" >/dev/null
ps -eo pid,lstart,args | grep -E "android.hardware.bluetooth@" | grep -v grep > $O/hal-before.txt
sh /home/phablet/stone-bt-trace.sh "$SECS"
echo "Android log and HAL pid going to $O for $SECS s"
cat $O/hal-before.txt
