#!/bin/sh
# Boot-time trace (test only; installed by stone-boot-trace-install.sh).
# Runs in normal boots and in charger mode (charger.target). For the first
# 120 s it records the journal live (the system journal loses the early boot),
# and whenever it changes: the USB gadget, usb-moded's mode, what the charger
# driver reports to usb-moded (online, type) and the battery. One directory per
# boot: /var/log/stone-boot-trace/<n>-<mode>/.
#
# In charger mode UT's lxc-android-ready remounts every block-device
# filesystem read-only (sysrq u) against power cuts. tmpfs stays writable, so
# there the trace goes to /run, and at the end (after 120 s) it is copied to
# /var/log/stone-boot-trace with / remounted read-write for about a second.
# (pstore does not help: charger to normal is a cold boot.)
B=/var/log/stone-boot-trace
# usb-moded's debug log. An EnvironmentFile wins over Environment=, and the
# image's stone-sunstone.conf sets USB_MODED_ARGS=, so a drop-in cannot do
# this; /run/usb-moded/*.conf is read last. This unit runs before usb-moded.
mkdir -p /run/usb-moded
echo USB_MODED_ARGS=-D > /run/usb-moded/zz-stone-debug.conf
mode=normal; grep -q 'androidboot.mode=charger' /proc/cmdline && mode=charger
if [ $mode = charger ]; then
    OUT=/run/stone-boot-trace; mkdir -p $OUT
    STATE=$OUT/state.txt
    cat /proc/cmdline > $OUT/cmdline.txt
    journalctl -f -o short-monotonic --no-pager -q > $OUT/journal.txt 2>&1 &
else
    mkdir -p $B
    n=$(ls $B | wc -l)
    OUT=$B/$n-$mode; mkdir -p $OUT
    STATE=$OUT/state.txt
    cat /proc/cmdline > $OUT/cmdline.txt
    [ -n "$(ls /sys/fs/pstore 2>/dev/null)" ] && cp -r /sys/fs/pstore $OUT/pstore
    journalctl -f -o short-monotonic --no-pager -q > $OUT/journal.txt 2>&1 &
fi
JPID=$!
G=/sys/kernel/config/usb_gadget/g1
U=/sys/class/power_supply/usb
BAT=/sys/class/power_supply/battery
last=
# Charger mode: 60 s, so the copy at the end happens before a long press ends it.
secs=120; [ $mode = charger ] && secs=60
end=$(( $(cut -d. -f1 /proc/uptime) + secs ))
while [ "$(cut -d. -f1 /proc/uptime)" -lt "$end" ]; do
    s="udc=$(cat $G/UDC 2>/dev/null) pid=$(cat $G/idVendor 2>/dev/null):$(cat $G/idProduct 2>/dev/null)"
    s="$s funcs=$(ls $G/configs/c.1 2>/dev/null | grep -v -e strings -e MaxPower -e bmAttributes | tr '\n' ',')"
    s="$s udcstate=$(cat /sys/class/udc/4e00000.dwc3/state 2>/dev/null)"
    s="$s mode=$(usb_moded_util -q 2>/dev/null | sed 's/^mode = //')"
    s="$s usb_online=$(cat $U/online 2>/dev/null) usb_type=$(cat $U/type 2>/dev/null)/$(cat $U/usb_type 2>/dev/null | sed 's/.*\[\(.*\)\].*/\1/')"
    s="$s adbd=$(systemctl is-active adbd.service 2>/dev/null)"
    s="$s target=$(systemctl get-default 2>/dev/null)"
    s="$s bat=$(cat $BAT/status 2>/dev/null)/$(cat $BAT/capacity 2>/dev/null)%"
    if [ "$s" != "$last" ]; then echo "[$(cut -d' ' -f1 /proc/uptime)] $s" >> $STATE; last=$s; fi
    sleep 0.2
done
# Charging current, a few samples (negative = into the battery on this gauge).
for i in 1 2 3; do echo "[$(cut -d' ' -f1 /proc/uptime)] current_now=$(cat $BAT/current_now 2>/dev/null) voltage_now=$(cat $BAT/voltage_now 2>/dev/null)" >> $STATE; sleep 2; done
kill $JPID
dmesg > $OUT/dmesg.txt
if [ $mode = charger ]; then
    ro=; grep -q ' / [^ ]* ro[, ]' /proc/mounts && ro=y
    [ -n "$ro" ] && mount -o remount,rw /
    mkdir -p $B
    n=$(ls $B | wc -l)
    cp -r $OUT $B/$n-charger
    sync
    [ -n "$ro" ] && mount -o remount,ro /
fi
chmod -R a+r $B 2>/dev/null
