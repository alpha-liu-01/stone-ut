#!/bin/sh
# lxc-start -d drops the error that explains ABORTING. Run in the foreground
# with stderr saved, and return once the container is RUNNING or has died.
LOG=/var/log/lxc-foreground.log
: > "$LOG"
setsid /usr/bin/lxc-start -F -n android >"$LOG" 2>&1 </dev/null &
echo $! > /run/stone-lxc.pid
i=0
while [ "$i" -lt 40 ]; do
    if lxc-info -n android -s 2>/dev/null | grep -q RUNNING; then
        echo "stone-lxc-start: running" >> "$LOG"
        exit 0
    fi
    if ! kill -0 "$(cat /run/stone-lxc.pid)" 2>/dev/null; then
        break
    fi
    sleep 0.2
    i=$((i + 1))
done
echo "stone-lxc-start: not running" >> "$LOG"
lxc-info -n android -s >> "$LOG" 2>&1 || true
exit 1
