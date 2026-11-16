#!/bin/sh
# Collect the logs of a Bluetooth call (docs/roadmap-hardware-2.md, item 9
# wideband calls). Read-only. Run with sudo, giving the start time:
#   sudo sh stone-bt-call-logs.sh 17:25 > /home/phablet/bt-call-logs.txt 2>&1
# Bluetooth addresses are masked to their first and last byte, phone numbers
# entirely; ofono's binder hex dumps are left out.
SINCE=${1:-"-30min"}
m() {
    sed -E 's/\b([0-9A-Fa-f]{2})([:_][0-9A-Fa-f]{2}){4}[:_]([0-9A-Fa-f]{2})\b/\1:..:..:..:..:\3/g;
            s/\+?[0-9]{7,15}/<number>/g'
}
nodump() { grep -a -v -E '^\[ *[0-9.]+\] [^ ]+ [^:]+: +[0-9A-F]{4}: |imsradio|radio[0-9]*[<>]|binder|\?\?\?'; }

echo "== ofono: Bluetooth hands-free (AG), SCO, codec (since $SINCE)"
journalctl -b --since "$SINCE" --no-pager -o short-monotonic -u ofono | nodump \
    | grep -a -i -E "hfp|sco|bcs|codec|emulator|handsfree|card|audio|\+ciev|\+bcs|AT\+|brsf|bac|connect" | m | tail -80
echo "== bluetoothd (since $SINCE)"
journalctl -b --since "$SINCE" --no-pager -o short-monotonic -u bluetooth \
    | grep -a -v "profiles/input" | m | tail -40
echo "== kernel: SCO, mSBC (since $SINCE)"
journalctl -b -k --since "$SINCE" --no-pager -o short-monotonic | grep -a -i -E "msbc|sco|esco|sync" | m | tail -30
echo "== links now"
hcitool con 2>&1 | m
echo "sco_offload_msbc=$(cat /sys/module/bluetooth/parameters/sco_offload_msbc) active=$(cat /sys/module/bluetooth/parameters/sco_offload_msbc_active)"
echo "== PulseAudio bluez5 / ofono backend (user journal)"
setpriv --reuid=32011 --regid=32011 --init-groups -- env XDG_RUNTIME_DIR=/run/user/32011 \
    journalctl --user -b --since "$SINCE" --no-pager -o short-monotonic -u pulseaudio \
    | grep -a -i -E "bluez|ofono|sco|hfp|hsp|transport|acquire|codec|msbc" | m | tail -40
