#!/bin/sh
# Why Android's log reads back empty (needs root):
#   sudo sh /home/phablet/stone-logcat-check.sh
# Output also saved to /home/phablet/logcat-check.txt.
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
IN="lxc-attach -n android --"
try() {
    out=$("$@" 2>&1); rc=$?
    echo "rc=$rc lines=$(printf '%s\n' "$out" | grep -c .): $*"
    printf '%s\n' "$out" | head -${N:-3} | cut -c1-160 | sed 's/^/    /'
}
{
echo "== reading"
try /system/bin/logcat -d -t 3
try $IN /system/bin/logcat -d -t 3
try $IN /system/bin/logcat -d -b all -t 3
N=25 try $IN /system/bin/logcat -S
try $IN /system/bin/logcat -g
echo "== a line written inside the container, read back"
$IN /system/bin/log -t stonetest "inside $(date +%s)"
try $IN /system/bin/logcat -d -s stonetest
echo "== a line written from the host as root, read back"
/system/bin/log -t stonetest "host $(date +%s)"
try $IN /system/bin/logcat -d -s stonetest
echo "== logd"
try $IN /system/bin/getprop init.svc.logd
try $IN /system/bin/ps -A -o PID,USER,NAME,ARGS
N=20 try ls -la /proc/$(pgrep -x logd)/fd
try $IN /system/bin/ls -la /dev/socket/
echo "== logpersist files (logd.logpersistd.enable)"
try ls -la /android/data/misc/logd/
echo "== properties"
N=40 try sh -c "$IN /system/bin/getprop | grep -iE 'log'"
} 2>&1 | tee /home/phablet/logcat-check.txt | grep -E "^(==|rc=)"
chown phablet:phablet /home/phablet/logcat-check.txt
