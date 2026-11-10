#!/bin/sh
# Camera debugging that needs root. Android tools only work inside the
# container (lxc-attach): logcat run from the Ubuntu side gets nothing from
# logd, and debuggerd has to see the container's processes. Binder state is
# world-readable in /dev/binderfs/binder_logs (this kernel has no debugfs).
#
#   sudo sh /home/phablet/stone-camera-debug.sh now
#       Snapshot of a stuck camera app: binder transactions (who waits on
#       whom), kernel stacks of the camera app, camera_service, minimedia and
#       the camera provider, native backtraces (debuggerd -b) of the Android
#       ones, the current logcat. Then starts a continuous logcat capture
#       (CamX logs a lot; the ring buffer alone loses minutes).
#   sudo sh /home/phablet/stone-camera-debug.sh stop
#       Ends the capture and gives the files to phablet.
#
# Output in /home/phablet/camera-debug/.
set -u
IN="lxc-attach -n android --"
GP=/android/system/bin/getprop
OUT=/home/phablet/camera-debug
BL=/dev/binderfs/binder_logs

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
mkdir -p "$OUT"

# The container has its own PID namespace: debuggerd wants its numbers.
nspid() { awk '/^NSpid:/{print $NF}' /proc/$1/status 2>/dev/null; }

threads() {
    for p in "$@"; do
        [ -d /proc/$p ] || continue
        echo "== $p $(cat /proc/$p/cmdline | tr '\0' ' ')"
        for t in /proc/$p/task/*; do
            echo "$(basename $t) $(cat $t/comm) $(awk '{print $3}' $t/stat) $(cat $t/wchan)"
            cat $t/stack 2>/dev/null | head -8 | sed 's/^/      /'
        done
    done
}

case "${1:-}" in
now)
    # An earlier version ran logcat on the Ubuntu side, which captures nothing.
    pkill -f "/android/system/bin/logcat -b all -v threadtime -f $OUT" 2>/dev/null
    {
        echo "== $(date) up $(cut -d' ' -f1 /proc/uptime)s"
        APP=$(pgrep -f lomiri-camera-app | tr '\n' ' ')
        MM=$(pgrep -f /system/bin/minimedia | tr '\n' ' ')
        CS=$(pgrep -f /system/bin/camera_service | tr '\n' ' ')
        PROV=$($GP init.svc_debug_pid.vendor.camera-provider-2-4)
        echo "app=$APP minimedia=$MM camera_service=$CS provider=$PROV"
        echo "== binder transactions"
        cat $BL/transactions
        echo "== threads (kernel stacks)"
        threads $APP $CS $MM $PROV
        for p in $CS $MM; do
            echo "== debuggerd -b $p (container pid $(nspid $p))"
            $IN /system/bin/debuggerd -b "$(nspid $p)" 2>&1
        done
        echo "== debuggerd -b provider $PROV (container pid)"
        $IN /system/bin/debuggerd -b "$PROV" 2>&1
        echo "== camera properties (vendor build.prop)"
        grep -i -E "camera|camx" /vendor/build.prop /odm/etc/build.prop 2>/dev/null
    } > "$OUT/snapshot.txt" 2>&1
    $IN /system/bin/logcat -d -b all -v threadtime > "$OUT/logcat-before.txt" 2> "$OUT/logcat-before.err"
    echo "logcat rc=$? stdout=$(wc -c < "$OUT/logcat-before.txt") stderr=$(wc -c < "$OUT/logcat-before.err")" >> "$OUT/logcat-before.err"
    $IN /system/bin/logcat -d -t 20 >> "$OUT/logcat-before.err" 2>&1
    # Bigger ring buffers and a continuous capture for the next attempt
    # (written inside the container, copied out on stop).
    $IN /system/bin/logcat -G 16M 2>/dev/null
    $IN /system/bin/pkill -f "logcat -b all -v threadtime -f /data/local/tmp/camera-logcat.txt" 2>/dev/null
    $IN /system/bin/sh -c "rm -f /data/local/tmp/camera-logcat.txt*; logcat -b all -v threadtime -r 65536 -n 4 -f /data/local/tmp/camera-logcat.txt >/dev/null 2>&1 &" 
    chown -R phablet:phablet "$OUT"
    echo "snapshot: $(wc -l < "$OUT/snapshot.txt") lines; logcat capture running"
    ;;
stop)
    $IN /system/bin/pkill -f "logcat -b all -v threadtime -f /data/local/tmp/camera-logcat.txt" 2>/dev/null
    sleep 1
    cat $(ls -r /android/data/local/tmp/camera-logcat.txt.* 2>/dev/null) /android/data/local/tmp/camera-logcat.txt > "$OUT/logcat.txt" 2>/dev/null
    chown -R phablet:phablet "$OUT"
    ls -l "$OUT"
    ;;
*)
    echo "usage: sudo sh $0 now|stop"; exit 1 ;;
esac
