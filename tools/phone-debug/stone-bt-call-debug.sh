#!/bin/sh
# Bluetooth call debugging (needs root): an HCI trace of the whole call plus
# the kernel, ofono, PulseAudio and call-audio router logs.
#
#   sudo sh /home/phablet/stone-bt-call-debug.sh start
#     (make the Bluetooth call, then)
#   sudo sh /home/phablet/stone-bt-call-debug.sh stop
#
# Output: /home/phablet/bt-call-debug/
set -u
OUT=/home/phablet/bt-call-debug
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
mkdir -p "$OUT"

case "${1:-}" in
start)
    rm -f "$OUT"/*
    date +%s > "$OUT/start-time"
    cut -d' ' -f1 /proc/uptime > "$OUT/start-uptime"
    nohup btmon -t > "$OUT/btmon.txt" 2>&1 &
    echo $! > "$OUT/btmon.pid"
    sleep 1
    chown -R phablet:phablet "$OUT"
    echo "HCI trace running; make the Bluetooth call, then: sudo sh $0 stop"
    ;;
stop)
    [ -f "$OUT/btmon.pid" ] && kill "$(cat "$OUT/btmon.pid")" 2>/dev/null
    rm -f "$OUT/btmon.pid"
    since=$(cat "$OUT/start-time" 2>/dev/null || echo 0)
    t0=$(cat "$OUT/start-uptime" 2>/dev/null || echo 0)
    dmesg | awk -v t="$t0" '{s=$0; sub(/^\[ */,"",s); split(s,a,"]"); if (a[1]+0 > t) print}' > "$OUT/dmesg.txt"
    journalctl -u ofono --since "@$since" --no-pager -o short-monotonic \
        | grep -vE "ofonod-wrapper.*  [0-9A-F]{4}: " > "$OUT/ofono.txt"
    journalctl _SYSTEMD_USER_UNIT=pulseaudio.service --since "@$since" --no-pager -o short-monotonic > "$OUT/pulseaudio.txt"
    journalctl _SYSTEMD_USER_UNIT=stone-call-audio.service --since "@$since" --no-pager -o short-monotonic > "$OUT/router.txt"
    cat /sys/module/bluetooth/parameters/sco_offload_msbc_active > "$OUT/msbc-active.txt"
    chown -R phablet:phablet "$OUT"
    ls -l "$OUT"
    ;;
*)
    echo "usage: sudo sh $0 start|stop"; exit 1 ;;
esac
