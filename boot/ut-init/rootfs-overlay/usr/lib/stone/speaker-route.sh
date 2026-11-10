#!/bin/sh
# MultiMedia5 (pcm device 9) to the speaker, from mixer_paths_qrdsku1.xml
# paths "speaker" and "low-latency-playback". The 64-bit legacy HAL is the
# AOSP stub and never programs these controls.
CARD=holiqrdsku1sndc
amixer -c "$CARD" cset name='RX_MACRO RX2 MUX' AIF2_PB >/dev/null
amixer -c "$CARD" cset name='RX_CDC_DMA_RX_1 Channels' One >/dev/null
amixer -c "$CARD" cset name='RX INT2_1 MIX1 INP0' RX2 >/dev/null
amixer -c "$CARD" cset name='RX INT2_1 INTERP' 'RX INT2_1 MIX1' >/dev/null
amixer -c "$CARD" cset name='AUX_RDAC Switch' 1 >/dev/null
amixer -c "$CARD" cset name='SpkrLeft Sipa Audio Scene' Playback >/dev/null
amixer -c "$CARD" cset name='SpkrLeft Sipa Power' On >/dev/null
amixer -c "$CARD" cset name='RX_CDC_DMA_RX_1 Audio Mixer MultiMedia5' 1 >/dev/null
exit 0
