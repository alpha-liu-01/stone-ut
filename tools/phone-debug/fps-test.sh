#!/bin/sh
# Frame-rate test, with the screen on and unlocked:
#   adb shell sh /home/phablet/fps-test.sh [lomiri-report-on|lomiri-report-off]
#   sudo sh /home/phablet/fps-test.sh clocks (root: clock comparison, see below)
#
# lomiri-report-on   runtime drop-in for Lomiri with MIR_SERVER_COMPOSITOR_REPORT=log
#                    (Lomiri's own compositor logs its FPS every second) and a
#                    restart of Lomiri (open apps close; unlock again after it).
#                    The drop-in is in /run: gone after reboot.
# lomiri-report-off  removes it and restarts Lomiri.
# no argument        the test:
#   1. 5 s idle on the home screen: panel vsync + committed frames.
#   2. 12 s fps-probe.qml (a full-screen Mir client animating continuously):
#      frames the app renders (counted from Qt's render-timing log), next to
#      what Lomiri and the panel get.
#   3. 15 s scrolling Lomiri's app drawer.
#   4. 15 s scrolling the System Settings main list (an app).
# clocks (root)      app drawer scrolling, 10 s each: stock governors; GPU
#                    mod_percent=200; GPU floor 490 MHz; CPU clusters at max
#                    (stock settings restored afterwards).
#   Lomiri's render-loop timing for each phase is shown when enabled
#   (lomiri-report-on).
# Output goes to the terminal and /home/phablet/fps-test/.
OUT=/home/phablet/fps-test
UNIT=lomiri-full-greeter.service
DROPIN=/run/user/32011/systemd/user/$UNIT.d
export XDG_RUNTIME_DIR=/run/user/32011
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/32011/bus
cd /home/phablet || exit 1

case "${1:-}" in
lomiri-report-on)
    mkdir -p "$DROPIN"
    printf '[Service]\nEnvironment=MIR_SERVER_COMPOSITOR_REPORT=log QSG_INFO=1 QSG_RENDER_TIMING=1\n' > "$DROPIN/zz-fps-report.conf"
    systemctl --user daemon-reload
    systemctl --user restart $UNIT
    echo "Lomiri restarted with its compositor report; unlock the phone"
    exit 0 ;;
lomiri-report-off)
    rm -rf "$DROPIN"
    systemctl --user daemon-reload
    systemctl --user restart $UNIT
    echo "Lomiri restarted normally"
    exit 0 ;;
esac

mkdir -p "$OUT"
rm -f "$OUT"/*.txt
journal() {   # Lomiri's journal since $1, as phablet or as root
    if [ "$(id -u)" = 0 ]; then
        journalctl _SYSTEMD_USER_UNIT=$UNIT --since "@$1" --no-pager -o cat 2>/dev/null
    else
        journalctl --user -u $UNIT --since "@$1" --no-pager -o cat 2>/dev/null
    fi
}
lomiri_report() {   # $1 = since (epoch s), $2 = file
    # Lomiri's Qt Quick render loop (QSG_RENDER_TIMING=1): one line per frame,
    # "Frame rendered with 'threaded' renderloop in Nms, sync=, render=, swap=".
    # swap = time eglSwapBuffers blocked (waiting for the host compositor).
    journal "$1" | grep "Frame rendered" > "$2"
    [ -s "$2" ] || return 0
    echo "-- Lomiri render loop (frames per second | median render / swap ms):"
    python3 - "$2" <<'PY'
import re, sys, collections
per = collections.OrderedDict()
for line in open(sys.argv[1]):
    m = re.search(r":(\d\d:\d\d:\d\d)\.\d+\].*in (\d+)ms, sync=(\d+), render=(\d+), swap=(\d+)", line)
    if m:
        per.setdefault(m.group(1), []).append(tuple(int(x) for x in m.group(2, 3, 4, 5)))
med = lambda v: sorted(v)[len(v) // 2]
for sec, fr in per.items():
    print("%s  %3d fps | sync %2d  render %2d  swap %2d  (max swap %d)" % (
        sec, len(fr), med([f[1] for f in fr]), med([f[2] for f in fr]),
        med([f[3] for f in fr]), max(f[3] for f in fr)))
PY
}
phase() {   # $1 = name, $2 = seconds, $3 = instruction
    echo "== $1, $2 s: $3"
    t=$(date +%s)
    python3 fps-panel.py "$2" | tee "$OUT/$1.txt"
    lomiri_report "$t" "$OUT/$1-lomiri.txt"
}

if [ "${1:-}" = clocks ]; then
    [ "$(id -u)" = 0 ] || { echo "clocks needs sudo"; exit 1; }
    G=/sys/class/kgsl/kgsl-3d0/devfreq
    gmin=$(cat $G/min_freq); gmod=$(cat $G/mod_percent)
    stock() {
        echo "$gmin" > $G/min_freq
        echo "$gmod" > $G/mod_percent
        for p in /sys/devices/system/cpu/cpufreq/policy*; do
            cat $p/cpuinfo_min_freq > $p/scaling_min_freq
        done
    }
    trap 'stock; chown -R phablet:phablet "$OUT"' EXIT INT TERM
    echo "Keep scrolling the app drawer up and down for the whole test (about 45 s)."
    sleep 3
    phase 1-stock 10 "stock governors (scroll now)"
    echo 200 > $G/mod_percent
    phase 2-gpu-mod200 10 "GPU governor sees load x2 (mod_percent=200), CPU stock"
    stock
    echo 490000000 > $G/min_freq
    phase 3-gpu-floor490 10 "GPU floor 490 MHz, CPU stock"
    stock
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        cat $p/scaling_max_freq > $p/scaling_min_freq
    done
    phase 4-cpu-max 10 "CPU at max, GPU stock"
    echo "== done (stock clocks restored)"
    exit 0
fi

phase 1-idle 5 "leave the phone alone"

echo "== 2-probe, 12 s: watch the orange square and the blue bar"
t=$(date +%s)
python3 fps-panel.py 12 > "$OUT/2-probe-panel.txt" &
QSG_RENDER_TIMING=1 GLIBC_TUNABLES=glibc.rtld.optional_static_tls=4096 \
    QT_QPA_PLATFORM=ubuntumirclient MIR_SOCKET=/run/user/32011/mir_socket QT_SELECT=qt5 \
    timeout 13 qmlscene fps-probe.qml 2>&1 | python3 -c '
import sys, time
start, n, sec = time.monotonic(), 0, 1
for line in sys.stdin:
    if "Frame rendered" not in line:
        continue
    now = time.monotonic()
    while now - start >= sec:
        print("t=%2ds app rendered %3d frames" % (sec, n), flush=True)
        n, sec = 0, sec + 1
    n += 1
' > "$OUT/2-probe-client.txt"
wait
echo "-- probe app:"; cat "$OUT/2-probe-client.txt"
echo "-- panel:"; cat "$OUT/2-probe-panel.txt"
lomiri_report "$t" "$OUT/2-probe-lomiri.txt"

phase 3-drawer 15 "open the app drawer and scroll it up and down, starting now"
phase 4-settings 15 "open System Settings and scroll its main list, starting now"
echo "== done"
