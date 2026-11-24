#!/bin/sh
# Test of stone-vendor-fixups.py choosing the vendor partition by slot
# (docs/roadmap-release.md item 18). Run with sudo, after pushing the new
# script next to this one:
#   sudo sh stone-vendor-fixups-slot-test.sh > /home/phablet/vendor-fixups-slot-test.txt 2>&1
# Writes only to a temporary directory: the overlay the phone uses is not
# touched (its vndservicemanager is running and must not be rewritten).
set -u
trap '' HUP
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d /tmp/vft.XXXXXX)
LIVE=/usr/share/halium-overlay/android/vendor
sed "s|^OVERLAY = .*|OVERLAY = \"$T/overlay\"|" "$HERE/stone-vendor-fixups.py" > "$T/vendor-fixups.py"
grep -n '^OVERLAY' "$T/vendor-fixups.py"

echo "== slot suffix on the kernel command line"
tr ' ' '\n' < /proc/cmdline | grep slot_suffix
echo "== mapped vendor devices"
ls /dev/mapper/ | grep -E '^vendor' || echo "(none)"

echo "== 1. no argument (suffix from the command line)"
python3 -I "$T/vendor-fixups.py"; echo "exit $?"
echo "-- compare with the overlay in use"
for f in $(cd "$T/overlay" && find . -type f | sort); do
    if cmp -s "$T/overlay/$f" "$LIVE/$f"; then echo "same: $f"; else echo "DIFFERENT: $f"; fi
done

echo "== 2. forced _a"
python3 -I "$T/vendor-fixups.py" _a; echo "exit $?"
echo "== 3. no usable suffix"
python3 -I "$T/vendor-fixups.py" _x; echo "exit $?"

rm -rf "$T"
echo "stone-vendor-fixups-slot-test: done; Ctrl+C is safe now" > /dev/tty 2>/dev/null || true
