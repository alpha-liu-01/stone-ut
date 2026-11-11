#!/bin/sh
# Where does media-hub's CPU go during video playback? Runs as phablet (no
# perf/gdb on the phone; strace can attach to phablet's own processes).
#
#   setsid sh /home/phablet/media-hub-profile.sh >/dev/null 2>&1 < /dev/null &
#
# Waits (up to 30 min) until the vendor Codec2 service (media.hwcodec) starts
# working, i.e. a video is being decoded, lets playback settle 8 s, then:
#   1. per-thread CPU (ms/s) of media-hub, the media player app and
#      media.hwcodec over 20 s, with thread names (GStreamer names its
#      streaming threads after the element pad, e.g. "multiqueue0:src");
#   2. strace -c -f of media-hub for 10 s (syscall counts and time);
#   3. strace -tt of media-hub's busiest thread for 2 s.
# Output: /home/phablet/media-debug/profile.txt
OUT=/home/phablet/media-debug
mkdir -p "$OUT"
R="$OUT/profile.txt"
: > "$R"
ticks() { awk '{print $14+$15}' "$1" 2>/dev/null || echo 0; }
pid_of() { pgrep -f "$1" | head -1; }

C2=$(pid_of '[v]endor.qti.media.c2')
END=$(( $(date +%s) + 1800 ))
echo "$(date +%T) waiting for decoding (media.hwcodec pid $C2)" >> "$R"
while :; do
    a=$(ticks /proc/$C2/stat); sleep 1; b=$(ticks /proc/$C2/stat)
    [ $((b - a)) -ge 3 ] && break
    [ "$(date +%s)" -ge "$END" ] && { echo "timed out" >> "$R"; exit 1; }
done
echo "$(date +%T) decoding started; settling 8 s" >> "$R"
sleep 8

MH=$(pid_of '[/]usr/lib/stone/media-hub-server')
PL=$(pid_of '[l]omiri-mediaplayer-app')
snap() {
    for p in "$MH" "$PL" "$C2"; do
        [ -n "$p" ] || continue
        for t in /proc/$p/task/*; do
            echo "$p $(basename "$t") $(ticks "$t/stat") $(tr ' ' '_' < "$t/comm")"
        done
    done
}
snap | sort -k2,2 > "$OUT/t0"
TOT0=$(awk '/^cpu /{print $2+$3+$4+$7+$8}' /proc/stat)
sleep 20
snap | sort -k2,2 > "$OUT/t1"
TOT1=$(awk '/^cpu /{print $2+$3+$4+$7+$8}' /proc/stat)
{
    echo "== $(date +%T) per-thread CPU over 20 s, ms per s (media-hub $MH, player $PL, media.hwcodec $C2)"
    echo "all CPUs: $(( (TOT1 - TOT0) * 10 / 20 )) ms/s"
    join -1 2 -2 2 "$OUT/t0" "$OUT/t1" | awk '{d=($6-$3)*10/20; if (d>0) printf "%6.0f  pid %s tid %s %s\n", d, $2, $1, $4}' | sort -rn
    echo "== per process, ms per s"
    join -1 2 -2 2 "$OUT/t0" "$OUT/t1" | awk '{s[$2]+=($6-$3)*10/20} END {for (p in s) printf "%6.0f  pid %s\n", s[p], p}' | sort -rn
} >> "$R"
TOP=$(join -1 2 -2 2 "$OUT/t0" "$OUT/t1" | awk -v mh="$MH" '$2==mh {print ($6-$3), $1, $4}' | sort -rn | head -1)
rm -f "$OUT/t0" "$OUT/t1"

echo "== $(date +%T) strace -c -f media-hub, 10 s" >> "$R"
timeout -s INT 10 strace -c -f -p "$MH" >> "$R" 2>&1

set -- $TOP
echo "== $(date +%T) strace -tt busiest media-hub thread: tid $2 ($3), 2 s" >> "$R"
timeout -s INT 2 strace -tt -T -p "$2" -o "$OUT/top-thread.strace" 2>/dev/null
wc -l < "$OUT/top-thread.strace" | sed 's/^/syscalls in 2 s: /' >> "$R"
awk '{print $2}' "$OUT/top-thread.strace" | sed 's/(.*//' | sort | uniq -c | sort -rn | head -15 >> "$R"
head -40 "$OUT/top-thread.strace" >> "$R"
echo "$(date +%T) done" >> "$R"
