#!/bin/sh
# Which way of reading Android's log works (needs root):
#   sudo sh /home/phablet/stone-logcat-check.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
try() {
    out=$("$@" 2>&1); rc=$?
    echo "rc=$rc lines=$(printf '%s\n' "$out" | grep -c .): $*"
    printf '%s\n' "$out" | head -2 | cut -c1-150 | sed 's/^/    /'
}
try /android/system/bin/logcat -d -t 3
try /system/bin/logcat -d -t 3
try lxc-attach -n android -- /system/bin/logcat -d -t 3
try lxc-attach -n android -- /system/bin/logcat -d -b main -t 3
try lxc-attach -n android -- /system/bin/logcat -g
try lxc-attach -n android -- /system/bin/getprop init.svc.logd
ls -la /dev/socket/logd* /android/dev/socket/logd* 2>&1 | sed 's/^/    /'
