#!/bin/sh
# Voice call audio without the Android audio HAL.
#
# The vendor HAL (32-bit audio.primary.holi.so) is not reachable from
# PulseAudio here, so nothing starts the ADSP voice session when the modem
# has a call up. This does what the HAL would do for VoiceMMode1, following
# /vendor/etc/mixer_paths_qrdsku1.xml:
#   voicemmode1-call[ handset] + handset/speaker + handset-mic/speaker-mic
# and then holds the VoiceMMode1 PCM (hw:0,2) open in both directions;
# msm-pcm-voice starts the voice session once RX and TX are both prepared.
#
# usage: call-audio.sh on [earpiece|speaker] | off
CARD=0
PIDS=${XDG_RUNTIME_DIR:-/tmp}/stone-call-audio.pids

set_ctl() { amixer -q -c "$CARD" cset name="$1" "$2" >/dev/null 2>&1 || echo "ctl failed: $1=$2" >&2; }

earpiece_on() {
    set_ctl 'RX_MACRO RX0 MUX' AIF1_PB
    set_ctl 'RX_CDC_DMA_RX_0 Channels' One
    set_ctl 'RX INT0_1 MIX1 INP0' RX0
    set_ctl 'RX INT0 DEM MUX' CLSH_DSM_OUT
    set_ctl 'EAR_RDAC Switch' 1
    set_ctl 'RDAC3_MUX' RX1
    set_ctl 'RX_EAR Mode' ON
    set_ctl 'RX_CDC_DMA_RX_0_Voice Mixer VoiceMMode1' 1
}

earpiece_off() {
    set_ctl 'RX_CDC_DMA_RX_0_Voice Mixer VoiceMMode1' 0
    set_ctl 'RX_EAR Mode' OFF
    set_ctl 'EAR_RDAC Switch' 0
}

# The speaker chain itself (RX2/AUX/Sipa on RX_CDC_DMA_RX_1) is already set
# up by speaker-route.sh for PulseAudio; only the voice mixer is added.
speaker_on() {
    /usr/lib/stone/speaker-route.sh >/dev/null 2>&1 || true
    set_ctl 'RX_CDC_DMA_RX_1_Voice Mixer VoiceMMode1' 1
}

speaker_off() {
    set_ctl 'RX_CDC_DMA_RX_1_Voice Mixer VoiceMMode1' 0
}

# Microphones. Both built-in mics are SoundWire ADCs on the codec:
#   SWR_MIC0 -> ADC1 (main/bottom mic), SWR_MIC4 -> ADC2/INP3 (second mic).
# Without ACDB calibration the voice uplink runs VSS_IVOCPROC_TOPOLOGY_ID_NONE
# (no fluence/ECNS), so the default is one mic, mono, like the vendor's
# amic1/amic3 paths. "dual" is the vendor handset-mic/speaker-mic routing
# (two channels into TX_CDC_DMA_TX_3), which needs the dual-mic calibration
# Android loads. Choose with ~/.config/stone/call-mic (mono|dual).
MIC_MODE=$(cat "${HOME}/.config/stone/call-mic" 2>/dev/null)
[ "$MIC_MODE" = dual ] || MIC_MODE=mono

mic_mono() {
    set_ctl 'TX_CDC_DMA_TX_3 Channels' One
    set_ctl 'TX DEC0 MUX' SWR_MIC
    set_ctl 'TX SMIC MUX0' "$1"
    if [ "$1" = SWR_MIC0 ]; then
        set_ctl 'ADC1 ChMap' SWRM_TX1_CH1
        set_ctl 'ADC1_MIXER Switch' 1
    else
        set_ctl 'ADC2 ChMap' SWRM_TX2_CH1
        set_ctl 'ADC2 MUX' INP3
        set_ctl 'ADC2_MIXER Switch' 1
    fi
    set_ctl 'TX_AIF1_CAP Mixer DEC0' 1
}

mic_dual() {
    set_ctl 'TX_CDC_DMA_TX_3 Channels' Two
    set_ctl 'TX DEC1 MUX' SWR_MIC
    set_ctl 'TX SMIC MUX1' "$1"
    set_ctl 'ADC1 ChMap' SWRM_TX1_CH1
    set_ctl 'TX_AIF1_CAP Mixer DEC1' 1
    set_ctl 'ADC1_MIXER Switch' 1
    set_ctl 'TX DEC2 MUX' SWR_MIC
    set_ctl 'TX SMIC MUX2' "$2"
    set_ctl 'ADC2 ChMap' SWRM_TX2_CH1
    set_ctl 'TX_AIF1_CAP Mixer DEC2' 1
    set_ctl 'ADC2_MIXER Switch' 1
    set_ctl 'ADC2 MUX' INP3
}

# Uplink gain. Android's voice ACDB calibration adds uplink gain in the DSP;
# with the passthrough topology the speech reached the modem at about
# -24 dBFS peaks, low enough for the vocoder's VAD/DTX to drop softer
# syllables (the far end heard it chopping several times a second).
# TX_DECn Volume is 1 dB/step, 84 = 0 dB (ADCn Volume is only 0.25 dB/step).
# dB above 0, from ~/.config/stone/call-mic-gain, default 14.
MIC_GAIN=$(cat "${HOME}/.config/stone/call-mic-gain" 2>/dev/null)
case "$MIC_GAIN" in ''|*[!0-9]*) MIC_GAIN=14 ;; esac
[ "$MIC_GAIN" -le 40 ] || MIC_GAIN=40

mic_gain() {
    for d in 0 1 2; do set_ctl "TX_DEC$d Volume" $((84 + $1)); done
}

# $1 = primary mic, $2 = secondary mic
mic_on() {
    if [ "$MIC_MODE" = dual ]; then mic_dual "$1" "$2"; else mic_mono "$1"; fi
    mic_gain "$MIC_GAIN"
    set_ctl 'VoiceMMode1_Tx Mixer TX_CDC_DMA_TX_3_MMode1' 1
}

mic_off() {
    mic_gain 0
    set_ctl 'VoiceMMode1_Tx Mixer TX_CDC_DMA_TX_3_MMode1' 0
    set_ctl 'TX_AIF1_CAP Mixer DEC0' 0
    set_ctl 'TX_AIF1_CAP Mixer DEC1' 0
    set_ctl 'TX_AIF1_CAP Mixer DEC2' 0
    set_ctl 'ADC1_MIXER Switch' 0
    set_ctl 'ADC2_MIXER Switch' 0
}

# What the HAL's voice_set_mic_mute()/voice_set_volume() send once the call
# is up: {value, ALL_SESSION_VSID, ramp ms}. Write-only controls, so not via
# amixer (it reads first).
CTLW=${STONE_CTL_WRITE:-$(dirname "$0")/ctl-write.py}
voice_unmute() {
    for c in 'Voice Tx Mute' 'Voice Tx Device Mute' 'Voice Rx Device Mute'; do
        python3 -I "$CTLW" "$c" 0 0xFFFFFFFF 20 || echo "ctl failed: $c" >&2
    done
}

# The voice FE is hostless: never read or write it (aplay/arecord did, and
# the NULL dma_area copy panicked the kernel). The holder only opens,
# configures and starts both directions until "off" kills it.
HOLD=${STONE_VOICE_HOLD:-$(dirname "$0")/voice-pcm-hold.py}

pcm_on() {
    python3 -I "$HOLD" hw:$CARD,2 "${1:-both}" &
    echo $! >> "$PIDS"
}

pcm_off() {
    [ -f "$PIDS" ] && kill $(cat "$PIDS") 2>/dev/null
    rm -f "$PIDS"
}

case "$1" in
    on)
        pcm_off
        case "${2:-earpiece}" in
            speaker) earpiece_off; speaker_on; mic_on SWR_MIC4 SWR_MIC0 ;;
            *)       speaker_off; earpiece_on; mic_on SWR_MIC0 SWR_MIC4 ;;
        esac
        pcm_on
        # The session only exists once both directions are prepared.
        sleep 0.5
        voice_unmute
        echo "call audio on: ${2:-earpiece}, mic $MIC_MODE +${MIC_GAIN} dB"
        ;;
    off)
        pcm_off
        earpiece_off
        speaker_off
        mic_off
        ;;
    # Single stages, for debugging.
    mixer)
        case "${2:-earpiece}" in
            speaker) speaker_on; mic_on SWR_MIC4 SWR_MIC0 ;;
            *)       earpiece_on; mic_on SWR_MIC0 SWR_MIC4 ;;
        esac
        ;;
    mixer-off) earpiece_off; speaker_off; mic_off ;;
    unmute) voice_unmute ;;
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
        echo "usage: $0 on [earpiece|speaker] | off" >&2
        exit 1
        ;;
esac
