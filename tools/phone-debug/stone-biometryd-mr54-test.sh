#!/bin/sh
# Test biometryd MR !54 (the libgbinder fingerprint backend backported to
# ubports/24.04-2.x, still on GetConnectionAppArmorSecurityContext) with the
# AppArmor-mediating kernel (docs/roadmap-release.md items 5 and 12).
#
#   sudo sh stone-biometryd-mr54-test.sh on     run the MR's daemon
#   sudo sh stone-biometryd-mr54-test.sh off    back to the image's daemon
#   sudo sh stone-biometryd-mr54-test.sh log    its journal since "on"
#
# The MR's biometryd and libbiometry.so.2 (from repo.ubports.com
# 24.04-2.x_-_PR_biometryd_54, unpacked on the PC) are in
# /home/phablet/biometryd-mr54/. The drop-in is in /run: gone after a reboot.
set -eu
DIR=/home/phablet/biometryd-mr54
DROP=/run/systemd/system/biometryd.service.d
CONF=$DROP/zz-zz-stone-mr54-test.conf

case "${1:-}" in
on)
    [ -x "$DIR/biometryd" ] && [ -f "$DIR/libbiometry.so.2" ] || { echo "files missing in $DIR" >&2; exit 1; }
    mkdir -p "$DROP"
    printf '%s\n' '[Service]' "Environment=LD_LIBRARY_PATH=$DIR" 'ExecStart=' "ExecStart=$DIR/biometryd run" > "$CONF"
    systemctl daemon-reload
    systemctl restart biometryd
    date +%s > /run/stone-mr54-test.start
    sleep 3
    systemctl show biometryd -p ExecStart -p ActiveState -p NRestarts | cut -c1-160
    ;;
off)
    rm -f "$CONF"
    systemctl daemon-reload
    systemctl restart biometryd
    sleep 2
    systemctl show biometryd -p ExecStart -p ActiveState | cut -c1-160
    ;;
log)
    since=$(cat /run/stone-mr54-test.start 2>/dev/null || echo 0)
    journalctl -u biometryd --since "@$since" --no-pager | tail -n 80
    ;;
*) echo "usage: $0 on|off|log" >&2; exit 1 ;;
esac
echo "stone-biometryd-mr54-test: done; Ctrl+C is safe now" > /dev/tty 2>/dev/null || true
