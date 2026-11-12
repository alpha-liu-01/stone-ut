#!/bin/sh
# Bluetooth trace for a few minutes (test only, needs root):
#   sudo sh /home/phablet/stone-bt-trace.sh [seconds]
# Records HCI traffic (btmon), the journal, rfkill events and the paired
# devices' BlueZ state into /home/phablet/bt-trace-<n>/. Runs detached through
# systemd-run, so a dropped adb session does not end it.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
SECS=${1:-180}
if [ "${STONE_BT_TRACE_CHILD:-}" != 1 ]; then
    n=0; while [ -e /home/phablet/bt-trace-$n ]; do n=$((n + 1)); done
    OUT=/home/phablet/bt-trace-$n; mkdir -p $OUT
    systemd-run --unit=stone-bt-trace-$n --collect -E STONE_BT_TRACE_CHILD=1 -E OUT=$OUT \
        /bin/sh "$(readlink -f "$0")" "$SECS" >/dev/null
    echo "tracing for $SECS s into $OUT"
    exit 0
fi
cd "$OUT"
# Not under set -e from here: grep -c and friends return 1 on a zero count.
set +e
btmon -w hci.btsnoop >/dev/null 2>&1 & P1=$!
btmon -t > hci.txt 2>&1 & P2=$!
journalctl -f -o short-monotonic --no-pager -q > journal.txt 2>&1 & P3=$!
rfkill event > rfkill.txt 2>&1 & P4=$!
end=$(( $(cut -d. -f1 /proc/uptime) + SECS ))
last=
while [ "$(cut -d. -f1 /proc/uptime)" -lt "$end" ]; do
    s="rfkill=$(rfkill -n -o TYPE,SOFT list bluetooth 2>/dev/null | tr -s ' \n' ' ')"
    s="$s adapter=$(bluetoothctl show 2>/dev/null | sed -n 's/^\tPowered: //p')"
    for d in $(bluetoothctl devices Paired 2>/dev/null | cut -d' ' -f2); do
        s="$s $d=$(bluetoothctl info $d 2>/dev/null | sed -n 's/^\tConnected: //p')"
    done
    s="$s acl=$(hcitool con 2>/dev/null | grep -c ACL)"
    [ "$s" != "$last" ] && echo "[$(cut -d' ' -f1 /proc/uptime)] $s" >> state.txt
    last=$s
    sleep 1
done
kill $P1 $P2 $P3 $P4 2>/dev/null
chown -R phablet:phablet "$OUT"
