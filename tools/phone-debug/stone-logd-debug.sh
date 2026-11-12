#!/bin/sh
# Why logd stops servicing its sockets (needs root):
#   sudo sh /home/phablet/stone-logd-debug.sh
# 1. kernel-side state and a symbolized backtrace of every logd thread (debuggerd)
# 2. restart logd, then check that reading and writing work again
# Everything goes to /home/phablet/logd-debug.txt.
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
IN="lxc-attach -n android --"
OUT=/home/phablet/logd-debug.txt
P=$(pgrep -x logd)
{
echo "== logd pid $P (container pid $(grep NSpid /proc/$P/status | awk '{print $3}')), clock $(date)"
for t in /proc/$P/task/*; do
    echo "-- task $(basename $t) $(cat $t/comm) state $(cut -d' ' -f3 $t/stat) wchan $(cat $t/wchan)"
    echo "   syscall: $(cat $t/syscall 2>&1)"
    sed 's/^/   /' $t/stack 2>&1 | head -12
done
echo "== socket queues (logd's listening sockets)"
ss -xlp 2>/dev/null | grep -E "logd|Recv-Q" | head
ss -xap 2>/dev/null | grep -E "/dev/socket/logd" | head
echo "== debuggerd -b"
$IN /system/bin/debuggerd -b $(grep NSpid /proc/$P/status | awk '{print $3}') 2>&1 | head -400
echo "== restart logd"
$IN /system/bin/setprop ctl.restart logd
sleep 3
echo "logd now pid $(pgrep -x logd), init.svc.logd=$($IN /system/bin/getprop init.svc.logd)"
$IN /system/bin/log -t stonetest "after restart $(date +%s)"
echo "-- logcat -d -t 5:"; $IN /system/bin/logcat -d -t 5 2>&1
echo "-- read back:"; $IN /system/bin/logcat -d -s stonetest 2>&1
echo "-- logcat -g:"; $IN /system/bin/logcat -g 2>&1
} > $OUT 2>&1
chown phablet:phablet $OUT
grep -E "^== |^logd now|^-- (logcat|read)" -A2 $OUT | head -30
