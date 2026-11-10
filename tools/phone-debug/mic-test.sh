#!/bin/sh
# Record 2 s from the built-in mics through MultiMedia1 and print levels.
# usage: mic-test.sh amic1|amic3|handset-mic
set -u
c() { amixer -q -c0 cset name="$1" "$2" >/dev/null 2>&1 || echo "ctl failed: $1=$2"; }
reset() {
  for d in 0 1 2; do c "TX_AIF1_CAP Mixer DEC$d" 0; done
  c "ADC1_MIXER Switch" 0; c "ADC2_MIXER Switch" 0
  c "MultiMedia1 Mixer TX_CDC_DMA_TX_3" 0
}
reset
case "$1" in
  amic1) c "TX DEC0 MUX" SWR_MIC; c "ADC1 ChMap" SWRM_TX1_CH1; c "TX SMIC MUX0" SWR_MIC0
         c "TX_CDC_DMA_TX_3 Channels" One; c "TX_AIF1_CAP Mixer DEC0" 1; c "ADC1_MIXER Switch" 1; CH=1 ;;
  amic3) c "TX DEC0 MUX" SWR_MIC; c "ADC2 ChMap" SWRM_TX2_CH1; c "TX SMIC MUX0" SWR_MIC4
         c "TX_CDC_DMA_TX_3 Channels" One; c "TX_AIF1_CAP Mixer DEC0" 1; c "ADC2_MIXER Switch" 1; c "ADC2 MUX" INP3; CH=1 ;;
  handset-mic)
         c "TX_CDC_DMA_TX_3 Channels" Two; c "TX DEC1 MUX" SWR_MIC; c "TX SMIC MUX1" SWR_MIC0; c "ADC1 ChMap" SWRM_TX1_CH1
         c "TX_AIF1_CAP Mixer DEC1" 1; c "ADC1_MIXER Switch" 1; c "TX DEC2 MUX" SWR_MIC; c "TX SMIC MUX2" SWR_MIC4
         c "ADC2 ChMap" SWRM_TX2_CH1; c "TX_AIF1_CAP Mixer DEC2" 1; c "ADC2_MIXER Switch" 1; c "ADC2 MUX" INP3; CH=2 ;;
esac
c "MultiMedia1 Mixer TX_CDC_DMA_TX_3" 1
OUT=${XDG_RUNTIME_DIR:-/tmp}/mic-$1.raw
arecord -q -D hw:0,0 -t raw -f S16_LE -r 48000 -c $CH -d 2 "$OUT" 2>&1 | head -3
reset
python3 -I - "$OUT" $CH <<'PY'
import sys, array, math
d = array.array("h", open(sys.argv[1], "rb").read()); ch = int(sys.argv[2])
for i in range(ch):
    s = d[i::ch][4800:]  # skip first 0.1 s
    if not s: print("ch%d: no samples" % i); continue
    rms = math.sqrt(sum(x*x for x in s) / len(s)); peak = max(abs(x) for x in s)
    print("ch%d: %d samples rms=%.1f peak=%d (%s)" % (i, len(s), rms, peak, "SILENT" if peak == 0 else "signal"))
PY
