# Hardware, part 2

`docs/roadmap-hardware.md` items 1 to 7 are done:
- storage;
- vendor modules;
- sound;
- Wi-Fi;
- SIM, data, calls and MMS;
- Bluetooth and wired headsets;
- camera.

This document covers the hardware that is still missing or untested after that. It follows the same rules:
- Fixes go into the repository (`boot/ut-init/rootfs-overlay/`, `boot/ut-init/stone-vendor-fixups.py`, `kernel/patches/`, `tools/`).
- Live tests run on the phone first, through scripts in `tools/phone-debug/`.
- The user flashes and commits.
- Do not reflash `vendor_boot`, `dtbo`, `vbmeta`, or `super`.

The phone has no passwordless sudo. Anything that needs root has to be run by the user with `adb shell -t 'sudo …'` (exit code 129 after it finishes is the SIGHUP from `-t`, not a failure). Push single files with adb, never a directory (a directory push drops the USB connection until it is replugged).

State at the start (2026-11-10):
- `boot_b`: `e1554638…` (kernel `#13`).
- `boot_b`: `7d432e5d…` (kernel `#14`, USB MTP, item 2), written and confirmed on 2026-11-10. Before it: `e3d83362…` (MMS over Wi-Fi and the sensors fixes of item 1), kept as `out/halium14/boot-ut-e3d83362.img`. `15c0d147…` (MMS only) is kept as `out/halium14/boot-ut-15c0d147.img`.
- Ubuntu Touch 24.04-2.x, Halium 14, crDroid 14 vendor.
- The deferred system update work is at the end of `docs/roadmap-hardware.md`.

## Already confirmed working

See `docs/roadmap-hardware.md`, "Already confirmed working". In short:
- display, touch, GPU, brightness, charging, vibration;
- speaker, Wi-Fi;
- SIM, 5G data, calls (3G and IMS), MMS (also on Wi-Fi);
- Bluetooth audio and calls, wired headsets (3.5 mm and USB);
- rear and front camera photos and video.

Done here: rotation and all sensors (item 1), USB MTP with adb alongside (item 2), hardware video decoding in the Media Player (item 3, it already worked).

## Fix order

1. Rotation and sensors. Nothing turns the screen, and no app gets an accelerometer, light, proximity or compass reading. Proximity during calls (screen off at the ear), automatic brightness, and photo orientation in the camera all depend on it.
2. USB file transfer (MTP). Done 2026-11-10 (kernel patch 0007). Before the fix, turning on MTP in Settings turned developer mode off, adb disappears, USB falls back to charging only, and the PC never shows the phone. Added on 2026-11-10, ahead of the decoders.
3. Hardware video and audio decoding. Checked 2026-11-10: already working. H.264, VP9 and HEVC (also the camera's own recordings) play in the Media Player on Qualcomm's Codec2 hardware decoders, with zero-copy output to `hybrissink`. Video in Morph (QtWebEngine) is software-decoded, with no hardware path on this stack (2026-11-11). Open: media-hub's own CPU use.
4. Camera leftovers. Flash and torch, tap-to-focus, zoom, and the barcode reader have not been tested (`docs/roadmap-hardware.md` item 7, "Still open or untested").
5. Power. Suspend and deep sleep, standby battery drain, and the battery level and health readings in Settings. Not checked yet.
6. Location (GNSS). Not checked yet.
7. Fingerprint reader. Not checked yet.
8. Smaller items:
   - the second SIM slot (only slot 1 has been tested; slot 2 is empty);
   - call volume keys (they change the media volume, not `Voice Rx Gain`);
   - wideband Bluetooth calls (mSBC);
   - the IR emitter and NFC, if the hardware has them.

   None of these has been checked yet.

## 1. Rotation and sensors

Goal: the screen rotates with the phone. Apps get the accelerometer, gyroscope, magnetometer, light and proximity sensors through sensorfw, and the services built on them work: proximity during calls, and automatic brightness when it is turned on.

What is seen: the screen never rotates. `sensorfwd.service` never comes up. It hangs in `activating (start)` until systemd's 90 s start timeout kills it, and then it is restarted (restart counter 11 after about 15 minutes). The camera app logs "There is no sensor manager yet". Item 7 of `docs/roadmap-hardware.md` read that, and init's lookups for HIDL `android.hardware.sensors@2.x/1.0`, as "there is no sensors HAL". That was wrong (see below).

### Planned steps

1. Find out what the vendor provides for sensors and why sensorfwd does not finish starting.
2. Fix it in the image (rootfs overlay), and first as a live install.
3. Check that readings arrive. Then the user checks rotation, proximity in a call, and automatic brightness.

### Sensors: what fixed it

- The vendor sensors HAL is running. It is the **AIDL** `android.hardware.sensors-service.xiaomi-multihal` (`vendor.sensors-hal-multihal`), registered as `android.hardware.sensors.ISensors/default` on `/dev/binder`. The supporting services `vendor.sensors`, `vendor.sensors.qti` and `sensorscal-hal-1-0` are running. There is no HIDL sensors HAL, which explains the HIDL lookups.
- UBports' sensorfw (`sensorfw-qt5` and `libsensorfw-qt5-hidl` 0.15.1) supports AIDL: the gbinder-based "hidl" adaptor library has `Connected to sensor AIDL service`. `/etc/sensorfw/sensord.conf.d/30-hidl.conf` already selects the `hidl*adaptor` plugins, so the configuration was right.
- The cause is libgbinder's configuration:
  - `/etc/gbinder.conf` contains only comments, there is no `/etc/gbinder.d/`, and nothing sets `ApiLevel`.
  - libgbinder therefore falls back to its default `aidl` protocol on `/dev/binder` (Android 9/10 era).
  - Android 14's servicemanager does not understand that. Measured as phablet with python3-gbinder (`/dev/binder` is mode 666):

    | service manager / RPC protocol | services listed | `ISensors/default` |
    | --- | --- | --- |
    | `aidl` / `aidl` (default) | 0 | not found |
    | `aidl3` / `aidl3` | 49 | found |
    | `aidl4` / `aidl3` | 49 | found |
    | `aidl5` or `aidl6` / `aidl3` | 0 | not found |

    sensorfwd therefore waited forever for the HAL and never sent systemd `READY=1`.
  - libgbinder 1.1.52's `ApiLevel = 34` uses its API 33 preset: `aidl3` and `aidl3` on `/dev/binder` and `/dev/vndbinder`, and `hidl` on `/dev/hwbinder`. That matches the working row.
- The HIDL users of gbinder were never affected, because `/dev/hwbinder` is `hidl` in every preset: ofono's binder plugin, the netd stub, and bluebinder.
- Checked before changing anything: sensorfwd was run by hand in an unprivileged user and mount namespace (`unshare -rm`, `gbinder.conf` bind-mounted, a private `/run`). It connected to the AIDL service and initialized the HAL. It found every sensor, then stopped as expected at the D-Bus registration that the private `/run` hid:

  | Type | Sensor |
  | --- | --- |
  | Accelerometer, gyroscope (plus uncalibrated) | `icm4x6xx` |
  | Magnetometer (plus uncalibrated) | `qmc630x` |
  | Light, proximity (sensorfw takes the wakeup proximity) | `tmd2755` |
  | Fused | gravity, linear acceleration, rotation vector, game rotation vector, geomagnetic rotation vector |
  | Screen orientation | `Device Orientation` (type 27, which `hidlorientationadaptor` uses) |
  | Others | step detector and counter, significant motion, tilt, pick-up, stationary/motion detect, Xiaomi private `Aod` and `Touch Sensor` |

Fix:
- `boot/ut-init/rootfs-overlay/usr/share/stone/gbinder-api34.conf`: `[General] ApiLevel = 34`.
- `boot/ut-init/rootfs-overlay/etc/systemd/system/sensorfwd.service.d/zz-stone-gbinder.conf`: `BindReadOnlyPaths=/usr/share/stone/gbinder-api34.conf:/etc/gbinder.conf` and `After=lxc-android-config.service`. Only sensorfwd sees this config.

Why the config is not global: `audiosystem-passthrough` also uses gbinder and registers `media.audio_flinger` on `/dev/binder`. With the default protocol that registration fails today. With a global `ApiLevel` it would succeed, and camera_service's libaudioclient would start talking to it. Changing that is a separate decision with its own tests (calls and camera recording).

Live install without a flash: `tools/phone-debug/stone-sensors-install.sh` (sudo). Readings without the UI: `QT_QPA_PLATFORM=minimal QT_SELECT=qt5 qmlscene /home/phablet/sensors-monitor.qml` (`tools/phone-debug/sensors-monitor.qml`) prints orientation, accelerometer, light, proximity, gyroscope and magnetometer once a second for 6 s, through QtSensors' sensorfw backend.

### Proximity during calls and automatic brightness: what fixed it

After the sensorfwd fix, the user confirmed rotation works. Proximity at the ear did nothing, and Settings → Brightness & Display had no "Adjust automatically" switch (the Nothing phone on 24.04-1.x has one). Both come from repowerd (`repowerd 2025.09`), not from Lomiri:

- **Proximity and the light sensor.** repowerd creates `SensorfwProximitySensor` and `SensorfwLightSensor` once, at start. If that fails, it logs "Failed to create Sensorfw…" and keeps a `NullProximitySensor`/`NullLightSensor` until it is restarted. At this boot, repowerd started at 12.2 s, while sensorfwd was still broken, and only became active at 32.5 s, apparently after about 20 s of trying sensorfw. Fixing sensorfwd later does not help the running repowerd.
  - Fix: `etc/systemd/system/repowerd.service.d/zz-stone-sensorfw.conf` (`Wants=`/`After=sensorfwd.service`). sensorfwd is `Type=notify` and reports ready once the HAL answers. The HAL registers at about 13.3 s (`ro.boottime.vendor.sensors-hal-multihal`), so the wait is short. The sensorfwd drop-in caps `TimeoutStartSec` at 30 s so that a missing HAL cannot hold repowerd (screen power) for 90 s. graphical.target and `keep-display-on-during-boot` depend on repowerd.
- **The switch in Settings and the curve.** repowerd reads `/usr/share/repowerd/device-configs/config-default.xml` and then `config-<deviceinfo Name>.xml` (`stone`). The default has `config_automatic_brightness_available=false` and no curve. repowerd reports `autobrightness_supported` from that flag, and builds its lux → brightness spline from `autoBrightnessLevels` and `autoBrightnessLcdBacklightValues` (integers, N levels and N+1 values, at most 255, in units of `screenBrightnessSettingMaximum`, which is 255).
  - Fix: `usr/share/repowerd/device-configs/config-stone.xml`, generated by `tools/repowerd-config-from-overlay.py` from the vendor's `/vendor/overlay/FrameworksResOverlayStone.apk` (the same values Android uses):
    - `config_automatic_brightness_available=true`;
    - 107 `config_autoBrightnessLevels` (1 to 100000 lux);
    - 108 `config_autoBrightnessDisplayValuesNits` (3.5 to 1000 nits), converted to 1..255 through the overlay's `config_screenBrightnessNits [4.5, 1000]` ↔ `config_screenBrightnessBacklight [1, 255]` (piecewise linear; checked to be monotone, from 1 to 255);
    - `config_screenBrightnessDim=13`.
  - The script has its own small `resources.arsc` parser, because androguard 4.1.2 fails on Android 14 aapt2 output (16-bit entry offsets, type flags `0x2`).
  - The panel is `/sys/class/backlight/panel0-backlight` (`max_brightness` 2047). repowerd scales value/255 onto it.

Readings checked over adb through QtSensors (sensorfw backend), phone lying flat: orientation `5` (face up), accelerometer `-0.06, 0.10, 9.92` m/s², gyroscope about 0, magnetometer about `-18, 3, 5` µT, proximity `near=false`. Light read `0.0` lux; not judged yet (dark room, or the sensor only reports on change).

### Status (2026-11-10)

| Part | State |
| --- | --- |
| sensorfwd | Working (live install, 22:07) |
| Screen rotation | Working (user confirmed) |
| Proximity in calls | Working (user confirmed): the screen turns off at the ear |
| Automatic brightness | Working (user confirmed): "Adjust automatically" is there and follows the light |
| Light sensor readings | Working (the `0.0` in the first reading was the light at that moment, not a fault) |
| Compass | Readings arrive; direction against a real compass not checked |
| Photo orientation (camera) | Not tested |
| In the image | `e3d83362…`, written and booted on 2026-11-10 (the user rebooted after flashing it) |

### Still open (sensors)

- Lomiri picked up sensorfwd without a restart (rotation worked right after the live install). repowerd does not (see above). The camera app has not been checked.
- The automatic brightness curve is Android's, without Android's per-user adjustment. If it is too dim or too bright indoors, `config_autoBrightnessLcdBacklightValues` can be scaled in the generator.
- Axis orientation: `30-hidl.conf` sets an identity matrix for the accelerometer and `-1,0,0,0,1,0,0,0,1` for the magnetometer. The compass direction still has to be checked against a real compass.
- Android's own `sensorservice` (Halium system) is also a client of the same HAL. Whether the multihal serves both clients, or the last `initialize()` wins, has not been checked. Only sensorfw matters here.
- Which process made the once-a-second HIDL `sensors@2.x/1.0` lookups has not been traced. Check after the fix whether they stop.

### Events

- 2026-11-10: `sensorfwd` was timing out on every start (restart counter 11). The vendor HAL is AIDL and runs fine. python3-gbinder showed that servicemanager answers only with the `aidl3` protocols, while libgbinder had no `ApiLevel` and used `aidl`. A hand-run sensorfwd with `ApiLevel = 34` found all sensors. The fix (an API 34 `gbinder.conf` bind-mounted for sensorfwd only) was written to the overlay. `stone-sensors-install.sh`, `sensors-monitor.qml`, `gbinder-api34.conf` and `zz-stone-gbinder.conf` were pushed to `/home/phablet`. Then the user ran `stone-sensors-install.sh`: `sensorfwd: active`, "Hybris sensor manager initialized".
- The user: auto-rotation works perfectly. Proximity at the ear in a call does not turn the screen off. There is no "Adjust automatically" switch under Brightness & Display, and automatic brightness does not work by default. Under Android the sensors work.
- Cause for both: repowerd (see "Proximity during calls and automatic brightness: what fixed it"). Added the repowerd drop-in, the 30 s sensorfwd start timeout, `config-stone.xml` and `tools/repowerd-config-from-overlay.py`. `stone-sensors-install.sh` now installs these too and restarts sensorfwd and then repowerd. Pushed.
- The user ran the new install and confirmed all three tests: the screen turns off at the ear in a call, Settings now has "Adjust automatically", and automatic brightness follows the light.
- New `boot-ut.img` SHA256 `e3d83362742ffbb39b97201f6e3509055d24bcde1af08cc2bed9cdd2c1afea9e` (kernel `#13`, unchanged; everything in `15c0d147…` plus `usr/share/stone/gbinder-api34.conf`, `sensorfwd.service.d/zz-stone-gbinder.conf`, `repowerd.service.d/zz-stone-sensorfw.conf` and `usr/share/repowerd/device-configs/config-stone.xml`). The ramdisk was checked: all of them are in it, with no `__pycache__`. The files installed live on the phone are byte-identical to the repository's. Not yet written. Writing it changes nothing on this phone, because the live install already put the same files in place. A clean boot with it is the remaining check that repowerd gets the sensors from boot.

## 2. USB file transfer (MTP)

Goal: with MTP on, the PC's file manager shows the phone and can copy files both ways. Developer mode (adb) keeps working alongside it (`mtp_adb`).

What is seen (user, 2026-11-10, image `e3d83362…`):
- Turning on USB MTP in Settings turns developer mode off, and adb disappears.
- Turning developer mode back on leaves USB in charging only.
- With MTP on, the PC never shows the phone.

### USB MTP: what fixed it

- usb-moded (`0.86.0+mer69`, `usb-moded-ubports-config`) builds its modes from configfs functions. `/etc/usb-moded/10-ubports-defaults.ini` has `function_mtp = mtp.mtp` and `function_adb = ffs.adb`. The `mtp` mode uses `sysfs_value = mtp`, and `mtp_adb` uses `mtp,adb` (it also restarts `adbd`).
- `mtp-server` (`0.1.0`, user unit, started by `mtp-server-usb-moded-watcher` when the mode is `mtp` or `mtp_adb`) only knows `/dev/mtp_usb`: its strings are `/dev/mtp_usb` and "Error opening /dev/mtp_usb, aborting now". It has no FunctionFS backend.
- `/dev/mtp_usb` and the `mtp` configfs function come from Android's kernel gadget `f_mtp` (`CONFIG_USB_CONFIGFS_F_MTP`). This kernel had no such option and no `f_mtp.c`. The Android common kernel removed `f_mtp` around 4.14/4.19, when Android moved MTP into userspace over FunctionFS. Of ACK's branches, only `deprecated/android-4.9*` still has it, and UBports' generic `android12-5.4-halium` kernel does not have it either. In `/sys/kernel/config/usb_gadget/g1/functions` there were only `ffs.adb`, `mass_storage.usb0` and `rndis.usb0`.
- So `mkdir functions/mtp.mtp` fails, usb-moded cannot enter `mtp` or `mtp_adb`, and it falls back. That fallback is what turned developer mode off and left USB on charging only (the mode afterwards was `charging_only_adb`).

Fix (kernel `#14 SMP PREEMPT Tue Nov 10 22:52:30 EST 2026`, `kernel/patches/0007-usb-gadget-add-f_mtp-for-ubuntu-touch.patch`):
- Qualcomm's msm-4.19 `f_mtp.c` and `include/{linux,uapi/linux}/usb/f_mtp.h` (CodeLinaro `clo/la/kernel/msm-4.19`, `kernel.lnx.4.19.r32-rel`), the closest relative of this msm-5.4 tree.
- Kconfig gains `USB_F_MTP` (tristate) and `USB_CONFIGFS_F_MTP` (bool, `select USB_F_MTP`, `depends on USB_CONFIGFS`). The function Makefile gains `usb_f_mtp`.
- One source change: the ChipIdea 16K Tx limit (`gadget->is_chipidea`, a msm-4.19-only field) was removed; this SoC's controller is DWC3 (`4e00000.dwc3`).
- PTP (`f_ptp.c`) is not added.
- The driver is self-contained: it answers its own control requests (`f->setup` = `mtp_ctrlreq_configfs`), so `configfs.c` needs no hook. It uses `vfs_read`/`vfs_write` on kernel buffers from its workqueue, which is still fine on 5.4 (workers run with `KERNEL_DS`).
- `kernel/config/halium-sunstone.fragment` gains `CONFIG_USB_CONFIGFS_F_MTP=y`. On `build-14/.config` it was turned on with `scripts/config --enable USB_CONFIGFS_F_MTP` plus `olddefconfig`. The only `.config` changes are `CONFIG_USB_CONFIGFS_F_MTP=y` and `CONFIG_USB_F_MTP=y`.
- The build had no errors. The only warning is the existing one in `drivers/bluetooth/btfm_slim.c`. `git apply --check -R` of patch 0007 on the tree is clean.

Already in place on the rootfs (nothing new needed): `85-android.rules` gives `/dev/mtp_usb` to `root:plugdev 0660`, and phablet is in `plugdev`. The usb-moded function names match the new kernel function, `mtp`.

New image: `boot-ut.img` SHA256 `7d432e5dd15411b69863850e0b84d52cb48eebf1d6c185220a2846c586897709`. It contains the `#14` Image (`418e3063…`, byte-identical to `kernel/build-14/arch/arm64/boot/Image`), and its rootfs overlay is the same as `e3d83362…` (kept as `out/halium14/boot-ut-e3d83362.img`; the `#13` Image as `out/halium14/Image-13`).

### Status (2026-11-10)

| Part | State |
| --- | --- |
| Kernel `f_mtp` | `#14`, in `7d432e5d…`, written and booted |
| `mtp` / `mtp_adb` mode switch | Working (user confirmed): developer mode stays on and adb works alongside MTP |
| PC file manager sees the phone | Working (user confirmed) |
| Copy both ways | Working (user confirmed) |

### Events

- 2026-11-10: the user reported the symptoms above. The usb-moded config, the mode files and the gadget functions were read on the phone (mode `charging_only_adb`; no `mtp.mtp`; no `/dev/mtp_usb`). The kernel config has no `F_MTP`, and the tree has no `f_mtp.c`. Ported `f_mtp` from msm-4.19 as patch 0007, built `#14`, and built `boot-ut.img` `7d432e5d…`. Waiting for the user: flash, then test MTP, MTP with developer mode, and file copies from the PC.
- The user flashed `7d432e5d…` and confirmed: MTP file transfer works both ways, and adb works alongside MTP. Item 2 is done.

## 3. Hardware video and audio decoding

Goal: videos (the camera's own recordings, files, and web video) play smoothly, using the Android codecs through the hybris media stack rather than software decoding.

What is seen: nothing was known before the test. Known from earlier items:
- media-hub runs as a patched copy (`/usr/lib/stone/media-hub-server`, `docs/roadmap-hardware.md` item 3).
- The camera records through `camera_service`/`minimedia` in the container.
- `mediaextractor` aborts on every boot (tombstones).

### Result (2026-11-10): hardware decoding already works, no fix needed

Test files (the user's, in `~/Videos`): the same clip, 226 s, once as 720p H.264 (`…_AVC_720P.mp4`, 18 MB) and once as 1080p VP9 in MP4 (38 MB). Both have AAC audio.

The decoders: when the `gsthybris` plugin first built its registry (`~/.cache/gstreamer-1.0/registry.aarch64.bin`), Android's MediaCodec list reported Qualcomm's Codec2 hardware decoders. GStreamer created `amcviddec-*` elements from them:
- `c2.qti.avc.decoder` (plus `.low_latency`);
- `c2.qti.hevc.decoder` (plus `.low_latency`);
- `c2.qti.vp9.decoder`.

The vendor service behind them is `media.hwcodec` (`/vendor/bin/hw/vendor.qti.media.c2@1.0-service`). The software fallbacks `openh264dec` (`libgstopenh264`) and `vp9dec` (`libgstvpx`) are also installed.

Direct test over adb, `tools/phone-debug/gst-decode-test.py` (ctypes on libgstreamer, because the rootfs has no `gst-launch-1.0` and no Gst typelib), to `fakesink sync=false`:

| Pipeline | Result | Speed | CPU |
| --- | --- | --- | --- |
| `h264parse ! amcviddec-c2qtiavcdecoder` | whole file to EOS, 6792 frames | 197 fps | client 15 s user + 9.3 s sys, `media.hwcodec` 16.8 s, in 20 s |
| `vp9parse ! amcviddec-c2qtivp9decoder` | whole file to EOS, 6787 frames | 112 fps | |
| `h264parse ! openh264dec` (software) | | 194 fps | 19.8 s user, `media.hwcodec` 0.01 s, in 20 s |
| `vp9parse ! vp9dec` (software) | | 90 fps | |

Without a sink surface, gst-amc copies every frame out of the decoder, so the hardware path costs as much CPU here as software decoding. Speed alone does not tell them apart on these cores. `media.hwcodec` doing the work does.

Gotcha for test tools: the hybris plugin loads libhybris's Android linker (`/usr/lib/aarch64-linux-gnu/libhybris/linker/q.so`) with `dlopen`, which needs static TLS. A Python process fails with "Failed to load hybris linker for Android SDK version 29: … cannot allocate memory in static TLS block", even with `LD_PRELOAD=libtls-padding.so`, which is what media-hub uses. `GLIBC_TUNABLES=glibc.rtld.optional_static_tls=65536` fixes it for the test.

Real playback: the user played each file for about 50 s in the Media Player app (`lomiri-mediaplayer-app` → media-hub): smooth, sound present and in sync, correct picture. A temporary user drop-in for media-hub (`GST_DEBUG=…amc*:4,hybris*:4,decodebin*:4,GST_ELEMENT_FACTORY:4`, removed afterwards) showed:
- playbin built `qtdemux → h264parse → amcviddec-c2qtiavcdecoder` and `qtdemux → vp9parse → amcviddec-c2qtivp9decoder`;
- the video sink was `hybrissink`, which gives the decoder an Android surface (`SurfaceTextureClientHybris`; the decoder waits for its texture id), so frames are not copied;
- audio was `aacparse → faad → pulsesink`;
- no software video decoder was created. The only errors, "Downstream returned flushing", fall at the moments playback was stopped.

CPU during playback (`tools/phone-debug/media-cpu-sample.sh`, ms of CPU per second):

| File | media-hub | `media.hwcodec` | player app | all 8 CPUs |
| --- | --- | --- | --- | --- |
| 720p H.264, 44 s | 451 | 146 | 243 | 2198 |
| 1080p VP9, 49 s | 504 | 174 | 259 | 2253 |

1080p VP9 (2.25× the pixels of 720p) costs about the same as 720p H.264, which fits the hardware doing the decoding. Logs: `out/halium14/logs/media-hw-decode/` (gitignored).

Second round, the same day: HEVC and the camera's own recordings.
- Files:
  - `2026-11-10 23-41-08_1080p60_HEVC.mp4`: `hev1`, 1920x1080, 216 s, 60 fps, AAC.
  - A new camera recording, `camera.ubports/video20261110_234703163.mp4`: `avc1`, 1920x1080, 12.1 s, 286 frames (just under 24 fps), AAC.
- Direct decodes, both to EOS:
  - `h265parse ! amcviddec-c2qtihevcdecoder`: 12951 frames in 110.5 s (119 fps, twice real time for 60 fps);
  - `h264parse ! amcviddec-c2qtiavcdecoder`: 286 frames (114 fps).
- The user played the HEVC file for over a minute, and the recording to its end, in Media Player: smooth, no issues. In the media-hub log, playbin built `h265parse → amcviddec-c2qtihevcdecoder` and `h264parse → amcviddec-c2qtiavcdecoder`, both into `hybrissink` with a `SurfaceTextureClientHybris` pool. No software video decoder was created.
- At the end of the recording, gst-amc logs `ERROR … Unexpected condition output buffer index 0` and then `dec_loop, flow_error, EOS`. That is Codec2's final buffer with the end-of-stream flag. The loop stops with `GST_FLOW_EOS`, and playback ends normally; the direct decodes end in a clean EOS too. Media Player then rebuilds the pipeline at the start of the clip, as it does after every finished video. Cosmetic.

| File | media-hub | `media.hwcodec` | player app | all 8 CPUs |
| --- | --- | --- | --- | --- |
| 1080p60 HEVC, 92 s | 592 | 269 | 411 | 2665 |
| camera 1080p H.264, 11 s | 428 | 147 | 198 | 2069 |

HEVC at 60 fps costs more mostly because it delivers twice the frames. Logs: `gst-hevc-camera.log`, `cpu-hevc-camera.log` in the same directory.

Morph browser (2026-11-11): YouTube "Never Gonna Give You Up", 1080p VP9, looping. **Software decoding.**
- Morph uses QtWebEngine (`libQt6WebEngineCore.so.6.10.2`, Chromium). It does not use GStreamer or media-hub, so it never reaches the Codec2 decoders.
- 10 s CPU sample during playback:
  - renderer (`QtWebEngineProcess --type=renderer`): about 1.8 cores. Four `ThreadPoolForeground` workers run at about 300 ms/s each, `Media` at about 85, `VideoFrameCompositor` at about 40.
  - `morph-browser`, where the GPU compositing runs (no separate GPU process; Adreno EGL through libhybris): about 0.5 core.
  - Audio utility process: about 27 ms/s.
  - lomiri and lomiri-system-compositor: about 0.1 core each.
  - `media.hwcodec`: 0. media-hub: 0.
- The renderer has `/usr/lib/aarch64-linux-gnu/libvpx.so.9.0.0` and `libopenh264.so.2.4.1` loaded: Ubuntu's QtWebEngine decodes with the system libvpx and openh264. No process has `libva` or a V4L2 decoder loaded.
- Why: on Linux, Chromium's only hardware video decode path is VA-API (its V4L2 decoder is built for ChromeOS only). There is no VA-API driver for this Adreno/Android (hybris) stack, so there is nothing to turn on. Getting Morph onto the hardware decoders would need either a VA-API driver that wraps Android's Codec2/MediaCodec through libhybris, or a QtWebEngine build with Chromium's V4L2 decoder pointed at the vendor `msm_vidc` V4L2 devices (UBWC/ION buffers, not a mainline venus driver). Neither exists; both are large projects outside this port.
- In practice: 1080p VP9 plays in software at about 1.8 cores in the renderer, on top of compositing. A lower YouTube resolution reduces this. Forcing H.264 does not help, because that is software (openh264) too.

### Still open (media)

- media-hub itself uses about 45 to 50 % of one core during playback. That is not the video decode (`faad` and pulsesink are small). Where it goes has not been measured per thread. It could be worth a look for battery life.
- Video in Morph is software-decoded (see above). Not fixable within the port.
- Not tested:
  - hardware audio decoding. AAC is decoded in software (`faad`), which is normal and cheap.
- `mediaextractor` still aborts at every boot. Playback goes through GStreamer's `qtdemux`, so nothing has been seen to depend on it.

### Events

- 2026-11-10: the user put the two test files on the phone. The registry listed the `c2.qti` decoders. Direct decodes worked for both files on the hardware decoders, and `media.hwcodec` did the work. The user played both files in Media Player (smooth, in sync, correct picture), and the GStreamer log showed `amcviddec-c2qti{avc,vp9}decoder` into `hybrissink` with no software video decoder. No fix was needed. The debug drop-in, the sampler and the temporary links were removed afterwards. `gst-decode-test.py` and `media-cpu-sample.sh` are in `tools/phone-debug/`, with copies in `/home/phablet`.
- 2026-11-10: second round. A 1080p60 HEVC file and a new 1080p camera recording decode in hardware, both directly and in Media Player (`amcviddec-c2qtihevcdecoder` and `amcviddec-c2qtiavcdecoder` into `hybrissink`). The user confirmed smooth playback. The gst-amc error at the recording's end is the EOS buffer and is harmless. The debug drop-in and the sampler were removed again.
- 2026-11-11: Morph and YouTube 1080p VP9 (looping): software, libvpx in the renderer (about 1.8 cores), with `media.hwcodec` idle. QtWebEngine has no hardware decode path here (Chromium on Linux would need VA-API).

## 4. Camera leftovers

Goal: flash and torch, tap-to-focus, zoom and the barcode reader work.

What is seen: not tested (`docs/roadmap-hardware.md` item 7). The flash shares TLMM pin 38 with the camera sensors (kernel patch 0005). Photo orientation depends on item 1.

## 5. Power

Goal: the phone suspends when the screen is off, standby drain is reasonable, and Settings shows the battery level and health.

What is seen: not checked yet.

## 6. Location (GNSS)

Goal: a position fix in a maps app, through the Android GNSS HAL.

What is seen: not checked yet.

## 7. Fingerprint reader

Goal: enrolling a fingerprint and unlocking with it in Lomiri, if the vendor's fingerprint HAL can be reached.

What is seen: not checked yet.

## 8. Smaller items

- The second SIM slot.
- Call volume keys controlling the call volume (`Voice Rx Gain`) instead of the media volume (`docs/roadmap-hardware.md` item 6).
- Wideband Bluetooth calls (mSBC). Calls are now narrowband CVSD with `enable_msbc=false`.
- The IR emitter and NFC: first check whether this model has them.
