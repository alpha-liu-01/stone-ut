#!/bin/sh
# Live tests of the camera fixes, without a flash (needs root). Everything is
# done inside the Android container and is gone after a reboot, except the
# persist property.
#
#   sudo sh /home/phablet/stone-camera-test.sh [apply]
#     - persist.vendor.camera.mapid=0: Xiaomi's CHI (chxcameraidxiaomi.cpp,
#       ExtensionModule::GetNumCameras / BuildCameraRoleIds) stops remapping
#       camera IDs to its "role IDs"; with it, camera 0 is the logical
#       wide+depth bokeh camera whose Xiaomi AlgoControl node aborts.
#     - libaudioclient with releaseAudioSessionId() returning at once
#       (tools/patch-libaudioclient.py), so releasing a video recorder no
#       longer waits forever for an AudioFlinger.
#     - /vendor/etc/camera/camxoverridesettings.txt with
#       MultiCameraEnable=FALSE, so CamX builds no logical multi-sensor
#       cameras: the rear camera is the wide sensor alone (with multi-camera
#       on, it streamed wide + the monochrome depth sensor and the preview
#       showed the depth sensor's grey frames).
#     Then restarts the camera provider, minimedia and camera_service.
#   sudo sh /home/phablet/stone-camera-test.sh dump
#     Full debuggerd dump of the running camera provider (includes its
#     recent log lines; logcat itself returns nothing here) into
#     /home/phablet/camera-debug/provider-dump.txt.
set -eu
IN="lxc-attach -n android --"
LIB=/home/phablet/libaudioclient-patched.so
TMP=/android/data/local/tmp
OUT=/home/phablet/camera-debug
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

overlaid() {
    $IN /system/bin/sh -c "grep -q ' $1 ' /proc/self/mountinfo"
}

case "${1:-apply}" in
apply)
    $IN /system/bin/setprop persist.vendor.camera.mapid 0
    echo "persist.vendor.camera.mapid=$($IN /system/bin/getprop persist.vendor.camera.mapid)"

    if [ -f "$LIB" ] && ! overlaid /system/lib64/libaudioclient.so; then
        cp "$LIB" $TMP/libaudioclient.so
        chmod 644 $TMP/libaudioclient.so
        $IN /system/bin/mount --bind /data/local/tmp/libaudioclient.so /system/lib64/libaudioclient.so
    fi
    overlaid /system/lib64/libaudioclient.so && echo "libaudioclient: patched copy"

    sed 's/^MultiCameraEnable=TRUE/MultiCameraEnable=FALSE/' \
        /vendor/etc/camera/camxoverridesettings.txt > $TMP/camxoverridesettings.txt
    chmod 644 $TMP/camxoverridesettings.txt
    if ! overlaid /vendor/etc/camera/camxoverridesettings.txt; then
        $IN /system/bin/mount --bind /data/local/tmp/camxoverridesettings.txt \
            /vendor/etc/camera/camxoverridesettings.txt
    fi
    echo "camx: $($IN /system/bin/grep MultiCameraEnable /vendor/etc/camera/camxoverridesettings.txt)"

    for s in vendor.camera-provider-2-4 minimedia camera_service; do
        $IN /system/bin/setprop ctl.restart $s
    done
    sleep 3
    for s in vendor.camera-provider-2-4 minimedia camera_service; do
        echo "$s: $($IN /system/bin/getprop init.svc.$s)"
    done
    ;;
dump)
    mkdir -p "$OUT"
    P=$($IN /system/bin/getprop init.svc_debug_pid.vendor.camera-provider-2-4)
    $IN /system/bin/debuggerd "$P" > "$OUT/provider-dump.txt" 2>&1
    chown -R phablet:phablet "$OUT"
    echo "provider $P: $(wc -l < "$OUT/provider-dump.txt") lines in $OUT/provider-dump.txt"
    ;;
*)
    echo "usage: sudo sh $0 [apply|dump]"; exit 1 ;;
esac
