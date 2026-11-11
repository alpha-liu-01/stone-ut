#!/bin/sh
# Raise Android's log level for Halium's media compat layer to INFO.
#
# libmedia_compat_layer (tags MediaCodecLayer, MediaFormatLayer) logs every
# MediaCodec call at DEBUG/VERBOSE, about 23 lines per decoded video frame.
# media-hub (GStreamer amcviddec-*) goes through it, so 720p30 playback wrote
# ~1000 lines/s, each twice (logd socket and pmsg) plus getuid/gettid/getpid.
# Measured: ~85 ms of CPU per second of playback (decoder process kernel
# time and logd). liblog drops lines below log.tag.<TAG>; nothing set it.
#
# Waits for Android's property service (the container starts after us).
TAGS="MediaCodecLayer MediaFormatLayer"
LEVEL=I
i=0
while [ $i -lt 120 ]; do
    ok=1
    for t in $TAGS; do
        [ "$(getprop log.tag.$t)" = "$LEVEL" ] && continue
        setprop "log.tag.$t" "$LEVEL" 2>/dev/null
        [ "$(getprop log.tag.$t)" = "$LEVEL" ] || ok=0
    done
    [ $ok = 1 ] && { echo "log.tag.{$(echo $TAGS | tr ' ' ',')}=$LEVEL"; exit 0; }
    i=$((i + 1))
    sleep 1
done
echo "Android property service not reachable; log levels not set" >&2
exit 1
