#!/bin/sh
# Root side of the refresh rate setting in System Settings
# (/usr/share/stone/settings/refresh_rate.py). Started by
# stone-refresh-rate.path when /run/stone-refresh-rate/request is written.
# The request is "<60|120> <save|restart>"; anything else is ignored.
REQ=/run/stone-refresh-rate/request
[ -f "$REQ" ] || exit 0
read -r rate action < "$REQ"
rm -f "$REQ"
case "$rate" in 60|120) ;; *) echo "ignored request: $rate $action"; exit 0 ;; esac
case "$action" in
restart)
    echo "refresh rate $rate Hz, restarting the display"
    exec /usr/bin/stone-refresh-rate "$rate" --restart-display ;;
save)
    mkdir -p /etc/stone
    echo "$rate" > /etc/stone/refresh-rate
    echo "refresh rate $rate Hz saved for the next display start" ;;
*)
    echo "ignored request: $rate $action" ;;
esac
