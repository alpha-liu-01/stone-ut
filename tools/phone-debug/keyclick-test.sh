#!/bin/sh
# Listening test for uneven keyboard clicks on the speaker.
#   sh /home/phablet/keyclick-test.sh A|B|C|D   (keyclick.qml next to it)
# (Use the full path with adb: a ~ is expanded by the PC's shell.)
# A: 12 keyboard clicks (QtMultimedia SoundEffect, like the keyboard) after
#    the speaker has been idle for 7 s
# B: the same, but the speaker path is kept running by a silent stream
# C: the same 12 clicks mixed into one continuous stream (one paplay)
# D: like A, plus a 10 ms vibration pulse with every click (like typing)
export XDG_RUNTIME_DIR=/run/user/32011 QT_QPA_PLATFORM=offscreen
W=/usr/share/maliit/plugins/lomiri-keyboard/styles/lomiri/sounds/key_tick2_quiet.wav
echo "waiting 7 s for the speaker to go idle..."; sleep 7
case "$1" in
A) qmlscene "$(dirname "$0")/keyclick.qml" >/dev/null 2>&1 ;;
B) head -c 1536000 /dev/zero | pacat --raw --rate=48000 --channels=2 --format=s16le -d sink.primary &
   sleep 2; qmlscene "$(dirname "$0")/keyclick.qml" >/dev/null 2>&1; wait ;;
C) python3 -I - "$W" <<'PY'
import sys, wave
w = wave.open(sys.argv[1]); p = w.getparams(); d = w.readframes(p.nframes)
gap = int(0.12 * p.framerate) * p.nchannels * p.sampwidth
one = d + b"\0" * (gap - len(d))
o = wave.open("/tmp/keyclick-train.wav", "wb"); o.setparams(p); o.writeframes(one * 12); o.close()
PY
   paplay -d sink.primary /tmp/keyclick-train.wav ;;
D) qmlscene "$(dirname "$0")/keyclick.qml" >/dev/null 2>&1 &
   for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
       busctl --system call com.lomiri.hfd /com/lomiri/hfd com.lomiri.hfd.Vibrator vibrate i 10 >/dev/null 2>&1
       sleep 0.12
   done; wait ;;
*) echo "usage: sh $0 A|B|C|D"; exit 1 ;;
esac
echo "done ($1)"
