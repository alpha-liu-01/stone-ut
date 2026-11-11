#!/bin/sh
# GNSS debugging for an outdoor test (needs root).
#
#   sudo sh /home/phablet/stone-gnss-debug.sh start
#     - runtime drop-in for lomiri-location-service with GLOG_logtostderr=1
#       (its glog output otherwise goes nowhere) and GLOG_v=200 (NMEA
#       sentences and per-report satellite counts), and a restart
#     - a 16 MB, cleared logcat ring buffer inside the Android container (the
#       Qualcomm GNSS HAL, loc_launcher, ...), dumped at stop. A background
#       "logcat -f" started through lxc-attach does not survive it returning.
#     - a snapshot of the Qualcomm location processes and properties
#     Then use a maps app (or gnss-monitor.qml) to get position updates.
#   sudo sh /home/phablet/stone-gnss-debug.sh stop
#     Stops the captures, saves everything to /home/phablet/gnss-debug/,
#     removes the drop-in (runtime only, also gone after a reboot) and
#     restarts lomiri-location-service normally.
#   sudo sh /home/phablet/stone-gnss-debug.sh run [SECONDS]
#     start, then /home/phablet/gnss-monitor.qml as phablet for SECONDS
#     (180; a QtPositioning session like a maps app, output in
#     gnss-monitor.txt), then stop.
#
# Do not use "lomiri-location-serviced-cli --test" here: its fixture runs
# "service lomiri-location-service stop" and only starts the service again
# when the test ends (after a fix, or 15 minutes per trial).
set -u
IN="lxc-attach -n android --"
OUT=/home/phablet/gnss-debug
DROPIN=/run/systemd/system/lomiri-location-service.service.d
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
mkdir -p "$OUT"

snapshot() {
    {
        echo "== $(date) uptime $(cut -d' ' -f1 /proc/uptime)"
        ps -eo pid,user,etime,args | grep -iE "gnss|loc_launcher|xtra|lowi|slim|location" | grep -v grep
        echo "== properties"
        $IN /system/bin/getprop | grep -iE "gnss|gps|location|xtra|izat|loc\."
        echo "== /data/vendor/location"
        ls -laR /android/data/vendor/location 2>&1 | head -40
        echo "== location service"
        for p in state is_online does_satellite_based_positioning visible_space_vehicles; do
            lomiri-location-serviced-cli --bus system --get --property $p 2>&1 | grep -v unregister
        done
    } >> "$OUT/snapshot.txt" 2>&1
}

case "${1:-}" in
start)
    rm -f "$OUT"/*.txt
    mkdir -p "$DROPIN"
    printf '[Service]\nEnvironment=GLOG_logtostderr=1 GLOG_v=200\n' > "$DROPIN/zz-gnss-debug.conf"
    systemctl daemon-reload
    $IN /system/bin/logcat -G 16M 2>/dev/null
    $IN /system/bin/logcat -c 2>/dev/null
    date +%s > "$OUT/start-time"
    systemctl restart lomiri-location-service
    sleep 3
    snapshot
    chown -R phablet:phablet "$OUT"
    echo "debug capture running; use a maps app, then: sudo sh $0 stop"
    ;;
stop)
    snapshot
    $IN /system/bin/logcat -d -b all -v threadtime > "$OUT/logcat.txt" 2> "$OUT/logcat.err"
    grep -iE "gnss|gps|loc|xtra|izat|ntp|supl|slim|lowi" "$OUT/logcat.txt" > "$OUT/logcat-gnss.txt"
    since=$(cat "$OUT/start-time" 2>/dev/null || echo 0)
    journalctl -u lomiri-location-service --since "@$since" --no-pager > "$OUT/location-service.txt" 2>&1
    rm -rf "$DROPIN"
    systemctl daemon-reload
    systemctl restart lomiri-location-service
    chown -R phablet:phablet "$OUT"
    ls -l "$OUT"
    ;;
run)
    sh "$0" start
    sed "s/property int limit: [0-9]*/property int limit: ${2:-180}/" \
        /home/phablet/gnss-monitor.qml > "$OUT/gnss-monitor.qml"
    chown phablet:phablet "$OUT/gnss-monitor.qml"
    runuser -u phablet -- env XDG_RUNTIME_DIR=/run/user/32011 QT_QPA_PLATFORM=minimal QT_SELECT=qt5 \
        timeout $(( ${2:-180} + 15 )) qmlscene "$OUT/gnss-monitor.qml" > "$OUT/gnss-monitor.txt" 2>&1
    sh "$0" stop
    ;;
*)
    echo "usage: sudo sh $0 start|stop|run [SECONDS]"; exit 1 ;;
esac
