#!/bin/sh
# The built-in qcacld driver only calls hdd_driver_load() after userspace
# writes ON to /dev/wlan. The vendor wifi HAL exits before doing that.
i=0
while [ ! -e /dev/wlan ] && [ "$i" -lt 40 ]; do
    sleep 1
    i=$((i + 1))
done
[ -e /dev/wlan ] || exit 1
i=0
while [ ! -e /sys/class/net/wlan0 ] && [ "$i" -lt 8 ]; do
    echo ON > /dev/wlan || true
    sleep 3
    i=$((i + 1))
done
[ -e /sys/class/net/wlan0 ]
