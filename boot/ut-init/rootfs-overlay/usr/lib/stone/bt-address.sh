#!/bin/sh
# Give the Bluetooth controller the same address on every boot
# (docs/roadmap-hardware-2.md, Bluetooth pairings and LE keyboards).
#
# The vendor HAL (android.hardware.bluetooth@1.0-impl-qti) takes the address
# from one of several places: the file named by ro.vendor.bt.bdaddr_path,
# persist.vendor.service.bdroid.bdaddr, or the modem's NV storage, and it
# writes what it used back into the property. The property and the modem copy
# hold the same bytes in opposite order, so the address came out byte-reversed
# on some boots. BlueZ keeps pairings per adapter address, and remote devices
# only accept the address they paired with: paired keyboards and controllers
# seemed forgotten.
#
# The HAL reads ro.vendor.bt.bdaddr_path first (as AOSP's bluetooth_address
# does). It is unset in this vendor, so set it to a file with the one canonical
# address before bluebinder starts the HAL. The canonical address is stored in
# /var/lib/stone/bt-bdaddr: taken once from an existing bdaddr file, else from
# the property, and kept from then on.
STATE=/var/lib/stone/bt-bdaddr
DATA=/var/lib/android-data/vendor/bluetooth
FILE=$DATA/bdaddr
PROP_PATH=/data/vendor/bluetooth/bdaddr
valid() { echo "$1" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; }
log() { echo "stone-bt-address: $*"; }

addr=$(cat "$STATE" 2>/dev/null | tr 'A-F' 'a-f')
if ! valid "$addr"; then
    addr=$(head -c 17 "$FILE" 2>/dev/null | tr 'A-F' 'a-f')
    valid "$addr" || addr=$(/usr/bin/getprop persist.vendor.service.bdroid.bdaddr | tr 'A-F' 'a-f')
    if ! valid "$addr"; then
        log "no address to keep; leaving the HAL's own choice"
        exit 0
    fi
    mkdir -p "$(dirname "$STATE")"
    printf '%s\n' "$addr" > "$STATE"
    log "canonical address stored (from the first boot with this service)"
fi

mkdir -p "$DATA"
printf '%s\n' "$addr" > "$FILE.new" && mv "$FILE.new" "$FILE"
chown 1002:1002 "$FILE"
chmod 0644 "$FILE"
# Right after the container starts its property service may not answer yet.
i=0
while [ -z "$(/usr/bin/getprop ro.vendor.bt.bdaddr_path)" ] && [ $i -lt 30 ]; do
    lxc-attach -n android -- /system/bin/setprop ro.vendor.bt.bdaddr_path "$PROP_PATH" 2>/dev/null
    [ -n "$(/usr/bin/getprop ro.vendor.bt.bdaddr_path)" ] && break
    sleep 1
    i=$((i + 1))
done
[ "$(/usr/bin/getprop ro.vendor.bt.bdaddr_path)" = "$PROP_PATH" ] \
    && log "HAL address file set" \
    || log "ro.vendor.bt.bdaddr_path is '$(/usr/bin/getprop ro.vendor.bt.bdaddr_path)', not ours"
