#!/bin/sh
# Item 7 step 2 (docs/roadmap-release.md): one apt full-upgrade on the phone,
# with everything recorded. Run with sudo, phone on Wi-Fi or mobile data:
#   sudo sh /home/phablet/stone-apt-upgrade.sh
# Output: /home/phablet/apt-upgrade/ (versions before/after, apt's output, the
# stone hook's report). Keeps existing config files (--force-confold) and does
# not stop if adb drops (SIGHUP ignored). Reboot afterwards (glibc).
#
# Roll back the UBports packages if needed (old versions stay in the repo):
#   sudo apt install bluebinder=<old> ofono-binder-plugin=<old> libofonobinderpluginext=<old>
# with <old> from /home/phablet/apt-upgrade/before.txt.
set -u
trap '' HUP
OUT=/home/phablet/apt-upgrade
mkdir -p "$OUT"
export DEBIAN_FRONTEND=noninteractive

dpkg-query -W -f='${Package} ${Version}\n' | sort > "$OUT/before.txt"
apt-get update > "$OUT/update.txt" 2>&1
apt list --upgradable 2>/dev/null | grep -v '^Listing' > "$OUT/upgradable.txt"
echo "upgradable: $(wc -l < "$OUT/upgradable.txt") packages" | tee "$OUT/summary.txt"

apt-get -y -o Dpkg::Options::=--force-confold full-upgrade > "$OUT/full-upgrade.txt" 2>&1
echo "apt-get full-upgrade exit code: $?" | tee -a "$OUT/summary.txt"

dpkg-query -W -f='${Package} ${Version}\n' | sort > "$OUT/after.txt"
diff "$OUT/before.txt" "$OUT/after.txt" | grep '^[<>]' > "$OUT/changed.txt"
echo "changed: $(grep -c '^>' "$OUT/changed.txt") installed/upgraded, $(grep -c '^<' "$OUT/changed.txt") old versions" | tee -a "$OUT/summary.txt"
dpkg --audit > "$OUT/dpkg-audit.txt" 2>&1
echo "dpkg --audit: $(wc -l < "$OUT/dpkg-audit.txt") lines (0 = clean)" | tee -a "$OUT/summary.txt"
grep '^stone' "$OUT/full-upgrade.txt" | tee -a "$OUT/summary.txt"
python3 -I /usr/lib/stone/update-fixups.py check | tee "$OUT/fixups-check.txt"
chown -R 32011:32011 "$OUT"
echo "stone-apt-upgrade: done; reboot the phone now" > /dev/tty 2>/dev/null || true
