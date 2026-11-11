#!/bin/sh
# Voice call session primitives, used by call-audio-router.py.
#
# The routing (earpiece/speaker/headphones/Bluetooth, uplink mic, gain) is not here: it
# is the UCM profile /usr/share/stone/ucm2/stone/HiFi.conf, applied by
# PulseAudio when lomiri-telephony-service switches the sink.primary port.
# What the vendor HAL would still do on top of its mixer paths is here:
# hold the hostless voice PCM open in both directions, which makes
# msm-pcm-voice start the voice session, and send the mute controls.
# SIM 1 (subscription 1) calls use the VoiceMMode1 session (device 2, vsid
# 0x11C05000), SIM 2 calls VoiceMMode2 (device 15, vsid 0x11DC5000): "sub2".
#
# usage: call-audio.sh on [muted] [sub2] | off | mute 0|1 | gain DB
#        call-audio.sh route earpiece|speaker|bluetooth|headphones|headset|usb
#                                                          (debug)
#        call-audio.sh rec-ul [secs] [file]               (debug)
# By id, not number: a USB audio card present at boot can take any slot.
CARD=holiqrdsku1sndc
PIDS=${XDG_RUNTIME_DIR:-/tmp}/stone-call-audio.pids
DIR=$(dirname "$0")

set_ctl() { amixer -q -c "$CARD" cset name="$1" "$2" >/dev/null 2>&1 || echo "ctl failed: $1=$2" >&2; }

# What the HAL's voice_set_mic_mute() sends once the call is up:
# {value, ALL_SESSION_VSID, ramp ms}. Write-only controls, so not via amixer
# (it reads first). The device mutes are cleared once per session.
CTLW=${STONE_CTL_WRITE:-$DIR/ctl-write.py}
voice_mute() {
    python3 -I "$CTLW" 'Voice Tx Mute' "$1" 0xFFFFFFFF 20 || echo "ctl failed: Voice Tx Mute" >&2
}
device_unmute() {
    for c in 'Voice Tx Device Mute' 'Voice Rx Device Mute'; do
        python3 -I "$CTLW" "$c" 0 0xFFFFFFFF 20 || echo "ctl failed: $c" >&2
    done
}

# Optional uplink gain override in dB above 0 (the UCM profile sets +20,
# TX_DEC0 Volume 104; 1 dB/step, 84 = 0 dB).
gain() {
    case "$1" in ''|*[!0-9]*) return ;; esac
    g=$1; [ "$g" -le 40 ] || g=40
    set_ctl 'TX_DEC0 Volume' $((84 + g))
}

# The voice FE is hostless: never read or write it (aplay/arecord did, and
# the NULL dma_area copy panicked the kernel). The holder only opens,
# configures and starts both directions until "off" kills it.
HOLD=${STONE_VOICE_HOLD:-$DIR/voice-pcm-hold.py}
VOICE_PCM=2               # VoiceMMode1; 15 = VoiceMMode2
pcm_on() {
    python3 -I "$HOLD" hw:$CARD,$VOICE_PCM "${1:-both}" &
    echo $! >> "$PIDS"
}
pcm_off() {
    [ -f "$PIDS" ] && kill $(cat "$PIDS") 2>/dev/null
    rm -f "$PIDS"
}

case "$1" in
    on)
        muted=0
        for a in "$2" "$3"; do
            case "$a" in muted) muted=1 ;; sub2) VOICE_PCM=15 ;; esac
        done
        pcm_off
        pcm_on
        # The session only exists once both directions are prepared.
        sleep 0.5
        device_unmute
        voice_mute $muted
        ;;
    off) pcm_off ;;
    mute) voice_mute "${2:-1}" ;;
    gain) gain "$2" ;;
    # Debug: switch the route the way the dialer does.
    route)
        case "$2" in
            earpiece) p='[Out] Earpiece'; s='[In] Mic' ;;
            speaker) p='[Out] Speaker'; s='[In] Mic' ;;
            bluetooth) p='[Out] Bluetooth'; s='[In] BluetoothMic' ;;
            headphones) p='[Out] Headphones'; s='[In] Mic' ;;
            headset) p='[Out] Headphones'; s='[In] Headset' ;;
            usb) p='[Out] USB'; s='[In] Mic' ;;
            *) echo "usage: $0 route earpiece|speaker|bluetooth|headphones|headset|usb" >&2; exit 1 ;;
        esac
        pactl set-sink-port sink.primary "$p" && pactl set-source-port source.primary "$s"
        ;;
    # Debug: record what the DSP sends to the modem (in-call record uplink,
    # MultiMedia9 <- VOC_REC_UL; a normal capture FE, safe to read).
    rec-ul)
        secs=${2:-8}; out=${3:-${XDG_RUNTIME_DIR:-/tmp}/stone-uplink.raw}
        set_ctl 'MultiMedia9 Mixer VOC_REC_UL' 1
        arecord -q -D hw:$CARD,23 -t raw -f S16_LE -r 8000 -c 1 -d "$secs" "$out"
        set_ctl 'MultiMedia9 Mixer VOC_REC_UL' 0
        python3 -I -c '
import sys, array, math
d = array.array("h", open(sys.argv[1], "rb").read())[800:]
rms = math.sqrt(sum(x*x for x in d) / len(d)) if d else 0
print("uplink %s: %d samples rms=%.1f peak=%d" % (sys.argv[1], len(d), rms, max(map(abs, d)) if d else 0))
' "$out"
        ;;
    pcm-rx) pcm_on rx ;;
    pcm-tx) pcm_on tx ;;
    pcm-off) pcm_off ;;
    *)
        echo "usage: $0 on [muted] | off | mute 0|1 | gain DB | route DEV | rec-ul" >&2
        exit 1
        ;;
esac
