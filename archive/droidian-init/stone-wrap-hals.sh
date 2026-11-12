#!/bin/sh
# Run after vendor is mounted. Copy the real HAL binaries aside and bind a
# logger over the container paths so their stderr reaches the kernel log.
ROOT=/var/lib/lxc/android/rootfs
LOG=/var/log/stone-wrap.txt
mkdir -p /usr/local/lib/stone "$ROOT/vendor_real"
echo "wrap start" > "$LOG"

install_wrap() {
    src=$1
    destrel=$2
    if [ ! -f "$src" ]; then
        echo "missing $src" >> "$LOG"
        return
    fi
    mkdir -p "$ROOT/vendor_real/$(dirname "$destrel")"
    if ! cp -a "$src" "$ROOT/vendor_real/$destrel"; then
        echo "copy failed $src" >> "$LOG"
        return
    fi
    name=$(basename "$destrel")
    wrap=/usr/local/lib/stone/wrap-$name
    cat > "$wrap" << EOF
#!/system/bin/sh
echo stone-hal $name > /dev/kmsg 2>/dev/null || true
echo stone-hal $name >> /vendor_real/hal.log
exec /vendor_real/$destrel "\$@" >> /vendor_real/hal.log 2>&1
EOF
    chmod 755 "$wrap"
    if mount --bind "$wrap" "$ROOT/vendor/$destrel"; then
        echo "wrapped $destrel" >> "$LOG"
    else
        echo "bind failed $destrel" >> "$LOG"
    fi
}

mkdir -p "$ROOT/vendor_real/lib64"
SYMBOL='_ZTVNSt3__118basic_stringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEEE'
if grep -a -q "$SYMBOL" /vendor/lib64/libc++.so 2>/dev/null; then
    cp -a /vendor/lib64/libc++.so "$ROOT/vendor_real/lib64/libc++.so"
    echo "libc++ from vendor, has stringstream" >> "$LOG"
elif [ -f /usr/local/lib/stone/libc++.so ]; then
    cp -a /usr/local/lib/stone/libc++.so "$ROOT/vendor_real/lib64/libc++.so"
    echo "libc++ from fallback, vendor lacks stringstream" >> "$LOG"
else
    echo "libc++ unavailable" >> "$LOG"
fi
if [ -f /usr/local/lib/stone/libapexsupport.so ]; then
    cp -a /usr/local/lib/stone/libapexsupport.so "$ROOT/vendor_real/lib64/libapexsupport.so"
    echo "installed libapexsupport" >> "$LOG"
else
    echo "libapexsupport missing" >> "$LOG"
fi

install_wrap /vendor/bin/vndservicemanager bin/vndservicemanager

for rc in /vendor/etc/init/*composer*.rc; do
    [ -f "$rc" ] || continue
    echo "rc $rc" >> "$LOG"
    sed -n '1,40p' "$rc" >> "$LOG"
    grep -o '/vendor/[^ ]*' "$rc" | while read -r path; do
        case "$path" in
            *.rc|*.xml|*.policy) continue ;;
        esac
        if [ -f "$path" ]; then
            install_wrap "$path" "${path#/vendor/}"
        fi
    done
done
