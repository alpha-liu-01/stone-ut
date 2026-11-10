#!/usr/bin/env python3
"""Stop camera_service from hanging when a video recording is released.

Ubuntu Touch records video in the Android container's camera_service
(libmedia_compat_layer's MediaRecorderClient + StagefrightRecorder). The
microphone comes from the app through /dev/socket/micshm: the Halium build of
libaudioclient has an "AudioRecordHybris" path for that, and
AudioSystem::newAudioUniqueId() is stubbed, so recording needs no
AudioFlinger. This system has none (no audioserver, no miniafservice).

AudioSystem::releaseAudioSessionId() was left alone. AudioRecord's destructor
calls it when the recorder is released, it asks for "media.audio_flinger",
and libaudioclient waits for that service forever (1 s retry loop). The
camera app's deleteRecorder() -> android_recorder_release() never returns,
the app hangs after every recording, and the next release queues behind the
first on the same lock. Seen with debuggerd -b on camera_service:
  AudioSystem::releaseAudioSessionId <- AudioRecord::~AudioRecord <-
  AudioSource::~AudioSource <- StagefrightRecorder::~StagefrightRecorder <-
  MediaRecorderClient::release

The patch makes releaseAudioSessionId(audio_session_t, pid_t) return at
once (its first instruction becomes RET). It returns void, and without an
AudioFlinger there is nothing to release.

The output is bind-mounted over /android/system/lib64/libaudioclient.so by
lxc-android-config's mount-halium-overlay (from
/usr/share/halium-overlay/android/system/lib64/).

Applies only to the exact Halium 14 build (input and output SHA256 checked).

usage: patch-libaudioclient.py IN OUT
"""
import hashlib
import sys

IN_SHA256 = "97144b4e999b467593a60aa89d412442a9704e60e3c2bc264e40597abfc96239"
OUT_SHA256 = "5fe2f500d4c1fc03a548c470c8d23481463cb4f1deec3340e5decb521ecd2c09"

# _ZN7android11AudioSystem21releaseAudioSessionIdE15audio_session_ti
# (.text is mapped 1:1, file offset == vaddr): sub sp, sp, #0x40 -> ret
PATCHES = [(0x68878, "ff0301d1", "c0035fd6")]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    data = bytearray(open(sys.argv[1], "rb").read())
    if hashlib.sha256(data).hexdigest() != IN_SHA256:
        sys.exit("%s: unexpected libaudioclient build, not patching"
                 % sys.argv[1])
    for off, old, new in PATCHES:
        assert data[off:off + 4] == bytes.fromhex(old), hex(off)
        data[off:off + 4] = bytes.fromhex(new)
    if hashlib.sha256(data).hexdigest() != OUT_SHA256:
        sys.exit("patched result does not match the expected build")
    with open(sys.argv[2], "wb") as f:
        f.write(data)


if __name__ == "__main__":
    main()
