#!/bin/sh
# Does a backward clock jump wedge logd? (needs root)
#   sudo sh /home/phablet/stone-logd-clock-test.sh
# Sets the clock back to the raw RTC time (January 1970), as time_daemon does;
# stone-clock-guard puts it right again at once. Probes logd before and after,
# and restarts logd if it is wedged.
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
probe() {
    timeout 5 python3 -I -c '
import socket
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(2)
try:
    s.connect("/dev/socket/logd"); s.send(b"getLogSize 0\0"); print("logd answers:", s.recv(64).rstrip(b"\0").decode())
except Exception as e:
    print("logd WEDGED:", type(e).__name__, e)'
}
echo "before: $(probe)"
RTC=$(cat /sys/class/rtc/rtc0/since_epoch)
date -s "@$RTC" >/dev/null && echo "clock set back to $(date -d @$RTC)"
sleep 3
echo "clock now: $(date)"
journalctl -u stone-clock-guard --since "-10s" --no-pager -q -o cat | tail -2
echo "after: $(probe)"
sleep 10
r=$(probe); echo "after 13 s: $r"
case "$r" in *WEDGED*)
    lxc-attach -n android -- /system/bin/setprop ctl.restart logd; sleep 3
    echo "logd restarted: $(probe)" ;;
esac
