#!/bin/sh
# Test the upstream mir-android2-platform fix built from source
# (tools/upstream/build-mir-android2-platform.sh) in place of the runtime
# binary patch of stone-display-setup (docs/roadmap-release.md item 5).
#
#   sudo sh stone-mir-source-test.sh source   use the source build
#   sudo sh stone-mir-source-test.sh stock    use the archive's unpatched module
#                                             (control: 60 Hz expected)
#   sudo sh stone-mir-source-test.sh status
#
# The module to test is /home/phablet/mir-test/graphics-android2.so.16. It is
# copied to /run (root-owned) and bind-mounted over the system's copy; then
# lightdm restarts, which restarts lomiri-system-compositor and Lomiri (open
# apps close; unlock again). Runtime only: a reboot brings back the image's
# runtime patch.
set -eu
LIB=/usr/lib/aarch64-linux-gnu/mir1/server-platform/graphics-android2.so.16
SRC=/home/phablet/mir-test/graphics-android2.so.16
RUN=/run/stone-mir-test

status() {
    if mountpoint -q "$LIB"; then
        echo "bind-mounted: $(findmnt -no SOURCE "$LIB")"
    else
        echo "not bind-mounted (the archive's module)"
    fi
    echo "in use: $(sha256sum < "$LIB" | cut -d' ' -f1)"
    pid=$(pgrep -f lomiri-system-compositor | head -n 1)
    [ -n "$pid" ] && grep -m1 graphics-android2 "/proc/$pid/maps" | awk '{print "compositor maps:", $6}'
}

# The running compositor keeps the bind mount busy: stop lightdm (and with
# it lomiri-system-compositor) before unmounting.
stop_display() {
    systemctl stop lightdm
    i=0
    while pgrep -f lomiri-system-compositor >/dev/null && [ $i -lt 50 ]; do
        sleep 0.2; i=$((i + 1))
    done
    # Something still holds the file even then (a root process); detach the
    # bind mount lazily, so the next mount takes its place for new mappings.
    while mountpoint -q "$LIB"; do umount -l "$LIB"; done
}

start_display() {
    systemctl start lightdm
    sleep 8
    status
}

# Never leave the phone without a display, even if a step fails.
trap 'systemctl is-active -q lightdm || systemctl start lightdm' EXIT

case "${1:-status}" in
source)
    [ -f "$SRC" ] || { echo "$SRC missing" >&2; exit 1; }
    mkdir -p "$RUN"
    install -m 644 "$SRC" "$RUN/graphics-android2.so.16"
    stop_display
    mount --bind "$RUN/graphics-android2.so.16" "$LIB"
    start_display
    ;;
stock)
    stop_display
    start_display
    ;;
status) status ;;
*) echo "usage: $0 source|stock|status" >&2; exit 1 ;;
esac
echo "stone-mir-source-test: done; Ctrl+C is safe now" > /dev/tty 2>/dev/null || true
