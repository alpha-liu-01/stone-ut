#!/bin/sh
# Test install of the Bluetooth auto-connect service (needs root). The image's
# overlay puts /usr/lib/stone/bt-autoconnect.py back at every boot, so this
# runs it from /usr/local/lib/stone-test through a drop-in (the next image's
# init deletes both). Then restarts bluebinder, which re-creates hci0 like a
# HAL death does, to see the service reconnect.
#   sudo sh /home/phablet/stone-bt-autoconnect-test.sh [--no-restart]
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
W=/usr/local/lib/stone-test/bt-autoconnect.py
D=/etc/systemd/system/stone-bt-autoconnect.service.d
install -d -m 755 /usr/local/lib/stone-test $D
install -m 755 /home/phablet/bt-autoconnect.py $W
printf '[Service]\n# Test only (stone-bt-autoconnect-test.sh).\nExecStart=\nExecStart=/usr/bin/python3 -I %s\n' $W > $D/zz-stone-test.conf
systemctl daemon-reload
systemctl restart stone-bt-autoconnect.service
sleep 2
if [ "${1:-}" != --no-restart ]; then
    echo "restarting bluebinder (Bluetooth drops for some seconds)"
    systemctl restart bluebinder.service
    sleep 25
fi
journalctl -u stone-bt-autoconnect --since "-40s" --no-pager -q -o cat
