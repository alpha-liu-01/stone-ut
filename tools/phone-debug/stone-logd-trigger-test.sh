#!/bin/sh
# Which host-side client wedges logd? (needs root)
#   sudo sh /home/phablet/stone-logd-trigger-test.sh
# logd lives in the Android container's PID namespace; a host process shows up
# there as pid 0. Each step starts from a freshly restarted logd, does one kind
# of host access, and checks logd from inside the container (pids map there).
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
IN="lxc-attach -n android --"
probe() { timeout 5 $IN /system/bin/logcat -g >/dev/null 2>&1 && echo ok || echo WEDGED; }
fresh() { $IN /system/bin/setprop ctl.restart logd; sleep 3; }
step() {
    name=$1; shift
    fresh
    b=$(probe)
    "$@" >/dev/null 2>&1
    sleep 2
    echo "$name: before $b, after $(probe)"
}
asphablet() { runuser -u phablet -- "$@"; }
CTL=/tmp/stone-logd-ctl.py
cat > $CTL <<'EOT'
import socket
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(3)
s.connect("/dev/socket/logd"); s.send(b"getLogSize 0\0"); s.recv(64)
EOT
chmod 644 $CTL
step "nothing (idle 2 s)" true
step "host write, root" /system/bin/log -t stonetest host-root
step "host write, phablet" asphablet /system/bin/log -t stonetest host-phablet
step "host command (getLogSize), root" timeout 5 python3 -I $CTL
step "host command (getLogSize), phablet" asphablet timeout 5 python3 -I $CTL
step "host logcat -d, phablet" asphablet timeout 5 /system/bin/logcat -d -t 1
step "host logcat -d, root" timeout 5 /system/bin/logcat -d -t 1
step "container logcat -d, root" timeout 5 $IN /system/bin/logcat -d -t 1
fresh
echo "end: logd $(probe)"
rm -f $CTL
