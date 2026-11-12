#!/bin/sh
# AppArmor mediation check (docs/roadmap-release.md item 12). Read-only.
# Run with sudo (the system journal is not readable as phablet):
#   sudo sh stone-apparmor-check.sh > /home/phablet/apparmor-check.txt 2>&1
F=/sys/kernel/security/apparmor/features
PU=32011
# Session-bus and user-journal commands run as phablet.
U() {
    if [ "$(id -u)" = 0 ]; then
        # setpriv opens no PAM session (runuser kept the adb terminal open).
        setpriv --reuid=$PU --regid=$PU --init-groups -- env HOME=/home/phablet XDG_RUNTIME_DIR=/run/user/$PU \
            DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$PU/bus "$@"
    else
        env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$PU/bus "$@"
    fi
}

echo "== kernel"
uname -v
echo "== features"
ls "$F"
for d in dbus network network/af_unix domain/stack; do
    [ -e "$F/$d" ] && { printf '%s: ' "$d"; ls "$F/$d" | tr '\n' ' '; echo; } || echo "$d: missing"
done
[ -e "$F/dbus/mask" ] && echo "dbus/mask: $(cat "$F/dbus/mask")"
[ -e "$F/network/af_unix" ] && [ -f "$F/network/af_unix" ] && echo "network/af_unix: $(cat "$F/network/af_unix")"

echo "== SO_PEERSEC on the system and session bus sockets"
python3 -I - <<'EOF'
import os, socket
SO_PEERSEC = 31
for path in ("/run/dbus/system_bus_socket", "/run/user/32011/bus"):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(path)
        v = s.getsockopt(socket.SOL_SOCKET, SO_PEERSEC, 256)
        print(path, "->", v.rstrip(b"\0").decode(errors="replace"))
    except OSError as e:
        print(path, "->", e)
    finally:
        s.close()
EOF

echo "== D-Bus credentials (LinuxSecurityLabel) of confined services"
for comm in telepathy-ofono mission-control-5 mediascanner-service-2.0; do
    pid=$(pgrep -f "$comm" | head -n 1)
    [ -n "$pid" ] || { echo "$comm: not running"; continue; }
    echo "$comm (pid $pid): $(cat /proc/$pid/attr/current 2>/dev/null)"
done
U gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.GetConnectionCredentials org.freedesktop.Telepathy.MissionControl5 2>&1 | head -c 400
echo

echo "== confined processes"
ps -eo label=,comm= | grep -v '^unconfined' | sort | uniq -c | sort -rn

echo "== policy cache"
ls -la /var/cache/apparmor/ 2>&1 | head

# journalctl -k has no kernel entries on this phone; read the ring buffer.
echo "== AppArmor denials in the kernel log (dmesg, last 60)"
dmesg 2>/dev/null | grep -a 'apparmor="DENIED"' | tail -n 60
echo "== D-Bus denials in the journal since boot (last 60)"
journalctl -b --no-pager 2>/dev/null | grep -a 'apparmor="DENIED"' | grep -a 'dbus' | tail -n 60
U journalctl --user -b --no-pager 2>/dev/null | grep -a 'apparmor="DENIED"' | tail -n 60
echo "== counts"
printf 'kernel log lines readable: '; dmesg 2>/dev/null | wc -l
printf 'kernel denials: '; dmesg 2>/dev/null | grep -ac 'apparmor="DENIED"'
printf 'dbus denials (system journal): '; journalctl -b --no-pager 2>/dev/null | grep -a 'apparmor="DENIED"' | grep -ac 'dbus'
printf 'denials (user journal): '; U journalctl --user -b --no-pager 2>/dev/null | grep -ac 'apparmor="DENIED"'
echo "stone-apparmor-check: done, output in the file; Ctrl+C is safe now" > /dev/tty 2>/dev/null
