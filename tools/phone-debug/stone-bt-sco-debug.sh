#!/bin/sh
# Why the Bluetooth chip never appears on SLIMbus (no BT call audio).
#
# SCO audio goes DSP <-> SLIMBUS_7 <-> BT chip. Opening SLIMBUS_7 fails with
# "btfm_slim_hw_init: failed to get slimbus btfmslim_slave logical address:
# -6": the ADSP (bus master) has never seen the chip report present.
# This tests enumeration directly (btpower's BT_CMD_SLIM_TEST ioctl runs
# the same btfm_slim_hw_init), then re-powers the chip by restarting
# bluebinder (the vendor HAL powers it off/on and reloads its firmware while
# the ADSP and SLIMbus are certainly up) and tests again.
#
# Run on the phone as:  sudo sh /home/phablet/stone-bt-sco-debug.sh
# Bluetooth drops for a few seconds; the earbuds reconnect afterwards.
set -u
LC=/android/system/bin/logcat
GP=/android/system/bin/getprop
OUT=/home/phablet/bt-sco-debug.txt
DBG=/sys/kernel/debug

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
mountpoint -q $DBG || mount -t debugfs none $DBG 2>/dev/null

slim_test() {
    python3 -I -c '
import fcntl, os
fd = os.open("/dev/btpower", os.O_RDWR)
try:
    r = fcntl.ioctl(fd, 0xbfac, 0)
    print("BT_CMD_SLIM_TEST: ok (%d)" % r)
except OSError as e:
    print("BT_CMD_SLIM_TEST: failed: %s" % e)
os.close(fd)'
}

klog_mark() { echo "stone-bt-sco-debug: $*" > /dev/kmsg; }

{
echo "== $(date) up $(cut -d' ' -f1 /proc/uptime)s"
echo "soc: $($GP vendor.qcom.bluetooth.soc) hal: $($GP init.svc.vendor.bluetooth-1-0-qti)"
ls -la /vendor/firmware /vendor/bt_firmware 2>/dev/null | grep -i -E "apbt|apnv|crbt|crnv|\.tlv|nv.*\.bin" | head -20
for f in /sys/bus/slimbus/devices/*; do echo "$f driver=$(basename "$(readlink "$f/driver" 2>/dev/null)")"; done

# Verbose SLIMbus controller + btfm logging into dmesg
echo 'file slim-msm-ngd.c +p' > $DBG/dynamic_debug/control 2>/dev/null
echo 'file slim-msm.c +p' > $DBG/dynamic_debug/control 2>/dev/null
echo 'file btfm_slim.c +p' > $DBG/dynamic_debug/control 2>/dev/null
echo 'file btfm_slim_slave.c +p' > $DBG/dynamic_debug/control 2>/dev/null
echo 3 > /sys/devices/platform/soc/a5c0000.slim/debug_mask 2>/dev/null

$LC -b all -c
klog_mark "test 1: chip as booted"
echo "== test 1: enumeration with the chip as booted"
slim_test

klog_mark "restarting bluebinder"
echo "== restarting bluebinder (re-powers the chip, reloads its firmware)"
systemctl restart bluebinder
i=0
while [ $i -lt 30 ]; do
    systemctl -q is-active bluebinder && break
    sleep 1; i=$((i + 1))
done
sleep 3
echo "bluebinder: $(systemctl is-active bluebinder) after ${i}s"

klog_mark "test 2: after re-power"
echo "== test 2: enumeration after re-powering the chip"
slim_test

echo "== dmesg (SLIMbus, btfm, btpower)"
dmesg | grep -a -i -E "stone-bt-sco-debug|slim|ngd|btfm|bt_power|btpower|bluetooth|wcn|SLIMBUS" | tail -300
echo "== slimbus ipc log"
for d in $DBG/ipc_logging/*slim*; do
    [ -e "$d" ] || continue
    echo "-- $d"
    cat "$d/log_cont" 2>/dev/null | tail -200 || cat "$d/log" 2>/dev/null | tail -200
done
echo "== logcat (BT HAL)"
$LC -b all -d -v threadtime | grep -i -E "bluetooth|bt_|hci|slim|soc|nvm|tlv|patch|rampatch|btpower|wcnss" | tail -500
} > "$OUT" 2>&1

chown phablet:phablet "$OUT"
grep -E "^== test|BT_CMD_SLIM_TEST|^bluebinder" "$OUT"
echo "saved $(wc -l < "$OUT") lines to $OUT"
