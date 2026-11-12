#!/bin/sh
# Live test of item 7 step 1 (docs/roadmap-release.md): update-fixups.py, the
# display-setup.sh unmount/mounts modes and the apt hook. Run with sudo:
#   sudo sh /home/phablet/stone-update-fixups-test.sh > /home/phablet/update-fixups-test.txt 2>&1
# Installs the new files from /home/phablet/fixups-test to their final paths
# (display-setup.sh goes back to the image's version at the next boot), then:
#  1. update-fixups.py check, then apply: the regenerated APN database must
#     equal the one the image ships;
#  2. display-setup.sh unmount / mounts;
#  3. apt update, then reinstall the installed mir1-platform-graphics-android2-16
#     through apt: without the hook dpkg cannot replace the bind-mounted library.
set -u
# The test restarts nothing, but if the session restarts anyway, the USB
# reconnect at session start drops adb; do not let the hang-up stop apt.
trap '' HUP
T=/home/phablet/fixups-test
L=/usr/lib/stone
LIBSO=/usr/lib/aarch64-linux-gnu/mir1/server-platform/graphics-android2.so.16
mounts() { findmnt -rn -o TARGET,SOURCE | grep -E "graphics-android2|PageComponent" || echo "(no bind mounts)"; }

echo "== install"
install -m 644 $T/update-fixups.py $L/update-fixups.py
install -m 644 $T/patch-telephony-ports.py $L/patch-telephony-ports.py
install -m 644 $T/apndb-prefer-mvno.py $L/apndb-prefer-mvno.py
install -m 644 $T/display-setup.sh $L/display-setup.sh
install -m 644 $T/tested-versions.txt /usr/share/stone/tested-versions.txt
install -m 644 $T/apndb-mvno.conf /usr/share/stone/apndb-mvno.conf
install -m 644 $T/99stone-update-fixups /etc/apt/apt.conf.d/99stone-update-fixups
before=$(sha256sum < /usr/share/stone/apns-conf.xml | cut -d' ' -f1)
echo "apns-conf.xml before: $before"

echo "== 1. check"
python3 -I $L/update-fixups.py check
echo "== 1. apply"
python3 -I $L/update-fixups.py apply
after=$(sha256sum < /usr/share/stone/apns-conf.xml | cut -d' ' -f1)
echo "apns-conf.xml after: $after"
[ "$before" = "$after" ] && echo "APNDB SAME AS IMAGE" || echo "APNDB DIFFERS"
sha256sum /usr/bin/lomiri-telephony-service-handler-stone
echo "== 1. apply again (expect up to date)"
python3 -I $L/update-fixups.py apply

echo "== 2. unmount / mounts (the compositor must keep running: same pid)"
pid() { pgrep -x lomiri-system-c || pgrep -f lomiri-system-compositor | head -n 1; }
p1=$(pid); echo "compositor pid $p1"
mounts
sh $L/display-setup.sh unmount
mounts
sh $L/display-setup.sh mounts
mounts
sleep 3
p2=$(pid); echo "compositor pid $p2"
[ "$p1" = "$p2" ] && echo "COMPOSITOR KEPT RUNNING" || { echo "COMPOSITOR RESTARTED; stopping the test"; exit 1; }

echo "== 3. apt reinstall of the bind-mounted Mir library"
apt-get update -qq 2>&1 | tail -3
v=$(dpkg-query -W -f='${Version}' mir1-platform-graphics-android2-16)
apt-get install -y --reinstall "mir1-platform-graphics-android2-16=$v" 2>&1 | tail -25
echo "dpkg status: $(dpkg-query -W -f='${db:Status-Abbrev} ${Version}' mir1-platform-graphics-android2-16)"
mounts
sha256sum "$LIBSO"
p3=$(pid); echo "compositor pid $p3"
[ "$p1" = "$p3" ] && echo "COMPOSITOR KEPT RUNNING" || echo "COMPOSITOR RESTARTED"
echo "== done"
echo "stone-update-fixups-test: done; Ctrl+C is safe now" > /dev/tty 2>/dev/null || true
