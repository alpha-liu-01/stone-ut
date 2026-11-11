#!/bin/sh
# Samples CPU use (ms per second) of the video playback processes:
# media-hub-server, the vendor Codec2 service (media.hwcodec), the media
# player app, and all CPUs together. Runs as phablet, writes
# /home/phablet/media-debug/cpu.log until killed or for $1 seconds (300).
#   setsid sh /home/phablet/media-cpu-sample.sh 300 >/dev/null 2>&1 &
OUT=/home/phablet/media-debug
mkdir -p "$OUT"
END=$(( $(date +%s) + ${1:-300} ))
ticks() { [ -n "$1" ] && awk '{print $14+$15}' /proc/$1/stat 2>/dev/null || echo 0; }
total() { awk '/^cpu /{print $2+$3+$4+$7+$8}' /proc/stat; }
echo "time mediahub_ms c2_ms player_ms allcpu_ms" > "$OUT/cpu.log"
while [ "$(date +%s)" -lt "$END" ]; do
    MH=$(pgrep -f /usr/lib/stone/media-hub-server | head -1)
    C2=$(pgrep -f vendor.qti.media.c2 | head -1)
    PL=$(pgrep -f lomiri-mediaplayer-app | head -1)
    a=$(ticks "$MH"); b=$(ticks "$C2"); c=$(ticks "$PL"); t=$(total)
    sleep 1
    a2=$(ticks "$MH"); b2=$(ticks "$C2"); c2=$(ticks "$PL"); t2=$(total)
    echo "$(date +%T) $(( (a2-a)*10 )) $(( (b2-b)*10 )) $(( (c2-c)*10 )) $(( (t2-t)*10 ))" >> "$OUT/cpu.log"
done
