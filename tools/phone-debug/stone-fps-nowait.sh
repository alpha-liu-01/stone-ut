#!/bin/sh
# Experiment: lomiri-system-compositor without the "wait for the previous
# present fence" after each HWC present (mir-android2-platform
# real_hwc2_wrapper.cpp, RealHwc2Wrapper::set(): sync_wait(last_present_fence, -1),
# marked "FIXME: is needed at all?"). The patched library has that timeout set
# to 0 (one instruction at 0x3c834: mov w1,#-1 -> mov w1,#0).
#
#   sudo sh /home/phablet/stone-fps-nowait.sh on    bind-mount the patched copy, restart the display
#   sudo sh /home/phablet/stone-fps-nowait.sh off   unmount it, restart the display
#
# Restarting lightdm restarts lomiri-system-compositor and Lomiri: open apps
# close, unlock again afterwards. The bind mount is runtime only (gone after a
# reboot).
set -eu
LIB=/usr/lib/aarch64-linux-gnu/mir1/server-platform/graphics-android2.so.16
PATCHED=/home/phablet/graphics-android2.so.16.nowait
STOCK_SHA=146cf674cde6fe8590f8150b0f7120a17083e7ef32724be38f7752b30dbdb18b
PATCHED_SHA=bc58bdfd7c258787d2291f489d08dfa7fa973356283147cdabcbf6c70e07347d
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

case "${1:-}" in
on)
    mountpoint -q "$LIB" && umount "$LIB"
    [ "$(sha256sum < "$LIB" | cut -d' ' -f1)" = "$STOCK_SHA" ] || { echo "installed $LIB is not the version this was made from"; exit 1; }
    [ "$(sha256sum < "$PATCHED" | cut -d' ' -f1)" = "$PATCHED_SHA" ] || { echo "$PATCHED checksum mismatch"; exit 1; }
    mkdir -p /run/stone-fps
    cp "$PATCHED" /run/stone-fps/graphics-android2.so.16
    mount --bind /run/stone-fps/graphics-android2.so.16 "$LIB"
    ;;
off)
    mountpoint -q "$LIB" && umount "$LIB"
    rm -rf /run/stone-fps
    ;;
*)
    echo "usage: sudo sh $0 on|off"; exit 1 ;;
esac
echo "library now: $(sha256sum < "$LIB" | cut -d' ' -f1)"
echo "restarting the display (lightdm); unlock the phone when it is back"
systemctl restart lightdm
