#!/bin/sh
# Capture qcril's detailed log for the failing data call and voice call.
# Run on the phone as:  sudo sh /home/phablet/stone-radio-debug.sh
set -u
SP=/android/system/bin/setprop
GP=/android/system/bin/getprop
LC=/android/system/bin/logcat
OUT=/home/phablet/radio-debug.txt

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

# "off": switch qcril's verbose logging back off. persist.* survives
# reboots; qcril reads it when it starts, so this takes effect next boot.
if [ "${1:-}" = off ]; then
    $SP persist.vendor.radio.adb_log_on 0
    echo "persist.vendor.radio.adb_log_on=$($GP persist.vendor.radio.adb_log_on) (effective after reboot)"
    exit 0
fi

echo "turning on qcril logging and restarting qcril (ofono reconnects by itself)"
$SP persist.vendor.radio.adb_log_on 1
$LC -b all -c
$SP ctl.restart vendor.qcrild
$SP ctl.restart vendor.qcrild2
sleep 5
echo "adb_log_on=$($GP persist.vendor.radio.adb_log_on) qcrild=$($GP init.svc.vendor.qcrild)"

echo
echo ">>> Now place a call from the Phone app and let it try for ~20 seconds, then hang up."
echo ">>> Mobile data retries on its own; nothing to do for that."
i=90
while [ $i -gt 0 ]; do printf "\rcapturing... %2ds " $i; sleep 1; i=$((i - 1)); done
echo

$LC -b radio -b main -b system -b crash -d -v threadtime > "$OUT"
chown phablet:phablet "$OUT"
echo "saved $(wc -l < "$OUT") lines to $OUT"
