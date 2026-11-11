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
- Current `boot_b` (updated 2026-11-11): `065ee6e5…` (kernel `#14`; USB MTP, the media log levels, the microSD mount options and the GNSS service), written and confirmed on 2026-11-11. Earlier: `a706816c…` (log levels). Before it: `7d432e5d…` (USB MTP), kept as `out/halium14/boot-ut-7d432e5d.img`. Before it: `e3d83362…` (MMS over Wi-Fi and the sensors fixes of item 1), kept as `out/halium14/boot-ut-e3d83362.img`. `15c0d147…` (MMS only) is kept as `out/halium14/boot-ut-15c0d147.img`.
- Ubuntu Touch 24.04-2.x, Halium 14, crDroid 14 vendor.
- The deferred system update work is at the end of `docs/roadmap-hardware.md`.

## Already confirmed working

See `docs/roadmap-hardware.md`, "Already confirmed working". In short:
- display, touch, GPU, brightness, charging, vibration;
- speaker, Wi-Fi;
- SIM, 5G data, calls (3G and IMS), MMS (also on Wi-Fi);
- Bluetooth audio and calls, wired headsets (3.5 mm and USB);
- rear and front camera photos and video.

Done here: rotation and all sensors (item 1), USB MTP with adb alongside (item 2), hardware video decoding in the Media Player (item 3, it already worked), microSD card (item 4), location (item 7).

## Fix order

1. Rotation and sensors. Nothing turns the screen, and no app gets an accelerometer, light, proximity or compass reading. Proximity during calls (screen off at the ear), automatic brightness, and photo orientation in the camera all depend on it.
2. USB file transfer (MTP). Done 2026-11-10 (kernel patch 0007). Before the fix, turning on MTP in Settings turned developer mode off, adb disappears, USB falls back to charging only, and the PC never shows the phone. Added on 2026-11-10, ahead of the decoders.
3. Hardware video and audio decoding. Checked 2026-11-10: already working. H.264, VP9 and HEVC (also the camera's own recordings) play in the Media Player on Qualcomm's Codec2 hardware decoders, with zero-copy output to `hybrissink`. Video in Morph (QtWebEngine) is software-decoded, with no hardware path on this stack (2026-11-11). media-hub's own CPU use: per-frame debug logging from Halium's media compat layer was turned off (about 8 % of a core saved at 30 fps); the rest is inherent.
4. MicroSD card. Added and done 2026-11-11. Detection, mount, MTP, the media scanner, speed and integrity were already fine. Fixed: a fixed 100 ms per written file on FAT cards (udisks' vfat `flush`), now 6.6 ms per file including sync.
5. Camera leftovers. Skipped 2026-11-11: already working (user). Flash and torch, tap-to-focus, zoom, and the barcode reader have not been tested (`docs/roadmap-hardware.md` item 7, "Still open or untested").
6. Power. Skipped 2026-11-11: already working (user). Suspend and deep sleep, standby battery drain, and the battery level and health readings in Settings. Not checked yet.
7. Location (GNSS). Pure Maps found no position (2026-11-11). The engine was fine but always cold-started: Qualcomm's `xtra-daemon` was not enabled, and the HAL was never told about the network, so there was no time or XTRA data. Fixed with `stone-gnss-netstate.service` (an indoor fix in about 30 s, 4 m accuracy). Done 2026-11-11: confirmed in Pure Maps. SUPL is left out (unimplemented upstream).
8. Fingerprint reader. Not checked yet.
9. Smaller items:
   - the second SIM slot (only slot 1 has been tested; slot 2 is empty);
   - call volume keys (they change the media volume, not `Voice Rx Gain`);
   - wideband Bluetooth calls (mSBC);
   - the IR emitter and NFC, if the hardware has them.
10. GPU and graphics APIs. Checked 2026-11-11: the UI uses the intended path (Mir `graphics-android2` with Adreno GLES 3.2 through libhybris), and Vulkan 1.1 works through `libvulkan1-hybris`. Desktop OpenGL is software only (Mesa llvmpipe). No fix needed for the system; options for hardware desktop GL are recorded.

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

- media-hub's own CPU use (about 45 to 50 % of one core during playback): investigated on 2026-11-11, see "media-hub CPU during playback" below. One real waste was found and fixed (per-frame debug logging); the rest is how this path works.
- Video in Morph is software-decoded (see above). Not fixable within the port.
- Not tested:
  - hardware audio decoding. AAC is decoded in software (`faad`), which is normal and cheap.
- `mediaextractor` still aborts at every boot. Playback goes through GStreamer's `qtdemux`, so nothing has been seen to depend on it.

### media-hub CPU during playback

Profile (`tools/phone-debug/media-hub-profile.sh`, as phablet; no perf or gdb on the phone). It waits for `media.hwcodec` to start decoding, then records per-thread CPU over 20 s, `strace -c -f` for 10 s, and `strace -tt` of the busiest thread. The user played the 720p H.264 file in Media Player.

- media-hub: 515 ms/s, spread over about 15 threads:
  - `ALooper` 91 (MediaCodec's message loop);
  - `vqueue:src` 70;
  - two `multiqueue4:src` threads, 70 and 46;
  - `HwBinder` 48;
  - `threaded-ml` 46 (PulseAudio mainloop);
  - `amcvideodec-c2q…` 44;
  - `aqueue:src` 34;
  - `qtdemux0:sink` 15;
  - `CodecLooper` 12.
- The player app took 263 ms/s (`QSGRenderThread` 192), `media.hwcodec` 168, and all CPUs about 2.2 cores.
- No single thread runs away. The `ALooper` trace is `futex`/`clock_gettime`/binder `ioctl` (Android's own looper).
- The syscall profile stood out: in 10 s, 10,581 `writev`, 10,583 `getuid`, 10,582 `gettid` and 9,639 `getpid`. That is Android liblog writing about 1,000 lines/s.

What the log lines are (`strace -e writev` of the same decode in `gst-decode-test.py`):
- Halium's `libmedia_compat_layer` (the MediaCodec bridge that `amcviddec` uses) logs every call at DEBUG/VERBOSE under the tags `MediaCodecLayer` and `MediaFormatLayer`: about 23 lines per decoded frame (`media_codec_dequeue_output_buffer…`, `Dequeued output buffer:`, `size: 1382400`, `info->flags: 0`, …). In 12 s there were 2043 D and 1057 V lines from `MediaCodecLayer`.
- Each line is written twice: to the logd socket, and with the `lg` header to pmsg.
- liblog drops lines below `log.tag.<TAG>`, and nothing set it (`log.tag` and `persist.log.tag` are empty, `ro.debuggable=1`). phablet can set these properties with `/usr/bin/setprop`.
- With `log.tag.MediaCodecLayer=I` and `log.tag.MediaFormatLayer=I`: 147 log writes in 12 s (one-off Codec2 start-up messages) instead of 3259.

A/B, real-time decode (`sync=true`, 30 fps, 20 s, two rounds each):

| Codec logging | Decoding process user + sys | `logd` | All CPUs |
| --- | --- | --- | --- |
| DEBUG/VERBOSE (as shipped) | 8.3 s, 8.0 s | 690 ms, 680 ms | 1060, 1067 ms/s |
| `I` | 7.4 s, 7.2 s | 130 ms, 110 ms | 987, 966 ms/s |

That saves about 85 ms of CPU per second of 720p30 playback (about 8 % of a core), mostly kernel time in the decoding process plus logd. It scales with the frame rate (twice as much at 60 fps).

Fix: `stone-android-log-levels.service` (oneshot, `After=lxc-android-config.service`), which runs `usr/lib/stone/android-log-levels.sh`. The script waits up to 120 s for Android's property service, then sets `log.tag.MediaCodecLayer=I` and `log.tag.MediaFormatLayer=I`. INFO, WARN and ERROR lines of those tags are kept. Only these two tags are changed. A global `log.tag=I` would save more, but it would also hide every DEBUG line in the container (camera and radio debugging used them).

The rest of media-hub's cost (`fakesink` decodes in `gst-decode-test.py` cost about the same, so it is not media-hub itself):
- GStreamer's queues and demuxer;
- MediaCodec's looper;
- per-buffer binder IPC to the Codec2 service;
- PulseAudio.

Reducing that would mean changing the hybris GStreamer plugin or Android's MediaCodec. Not pursued.

Image: `boot-ut.img` SHA256 `a706816cfcdcbc2f6b2277ac805d0e991e626731a3cb11617264fc14153a7ca0` (kernel `#14`, unchanged; adds the service). `7d432e5d…` is kept as `out/halium14/boot-ut-7d432e5d.img`. Written and confirmed after a reboot on 2026-11-11.

### Events

- 2026-11-10: the user put the two test files on the phone. The registry listed the `c2.qti` decoders. Direct decodes worked for both files on the hardware decoders, and `media.hwcodec` did the work. The user played both files in Media Player (smooth, in sync, correct picture), and the GStreamer log showed `amcviddec-c2qti{avc,vp9}decoder` into `hybrissink` with no software video decoder. No fix was needed. The debug drop-in, the sampler and the temporary links were removed afterwards. `gst-decode-test.py` and `media-cpu-sample.sh` are in `tools/phone-debug/`, with copies in `/home/phablet`.
- 2026-11-10: second round. A 1080p60 HEVC file and a new 1080p camera recording decode in hardware, both directly and in Media Player (`amcviddec-c2qtihevcdecoder` and `amcviddec-c2qtiavcdecoder` into `hybrissink`). The user confirmed smooth playback. The gst-amc error at the recording's end is the EOS buffer and is harmless. The debug drop-in and the sampler were removed again.
- 2026-11-11: Morph and YouTube 1080p VP9 (looping): software, libvpx in the renderer (about 1.8 cores), with `media.hwcodec` idle. QtWebEngine has no hardware decode path here (Chromium on Linux would need VA-API).
- 2026-11-11: profiled media-hub during 720p playback (user played the file). Found about 1,000 Android log lines/s from `MediaCodecLayer` (DEBUG/VERBOSE, per frame). `log.tag.MediaCodecLayer=I` and `log.tag.MediaFormatLayer=I` save about 85 ms/s (A/B measured). Added `stone-android-log-levels.service` and built `a706816c…`. Not yet written.
- 2026-11-11: the user wrote `a706816c…` and rebooted. Kernel `#14`. `stone-android-log-levels.service` was `active (exited)`, status 0, at 12.7 s (lxc-android-config at 12.1 s). `log.tag.MediaCodecLayer=I` and `log.tag.MediaFormatLayer=I`. The installed files are byte-identical to the overlay. A traced 12 s decode right after the boot: 290 log writes (both copies), 8 of them `MediaCodecLayer` INFO lines, instead of about 6500 before. Fix confirmed.

## 4. MicroSD card

Goal: a card in the slot is mounted for phablet, works over MTP and in the apps (media scanner), reads and writes at the card's speed, and keeps its data intact.

What is seen (user, 2026-11-11): the user put a card in and formatted it with the built-in tools. It was detected and was reachable over MTP.

### Checked (2026-11-11, image `a706816c…`)

| Part | Result |
| --- | --- |
| Card | `SD64G`, SD, manfid `0x9f`, oemid `0x5449`, made 09/2022, 62.5 GB (122167296 sectors). SSR: Class 10, UHS U1, V10 |
| Controller | `4784000.sdhci` (`mmc1`), block device `/dev/mmcblk1` (`brw-rw---- root disk`), scheduler bfq |
| Filesystem | FAT32, label empty, UUID `A0F3-F9B7`, on the whole device (no partition table) |
| Mount | udisks2 2.10.1, `/media/phablet/A0F3-F9B7`, `vfat rw,nosuid,nodev,relatime,uid=32011,gid=32011,fmask=0022,dmask=0022,shortname=mixed,showexec,utf8,flush,errors=remount-ro`. 59 GB free |
| MTP | Works (user) |
| Media scanner | `mediascanner-service-2.0` indexes the card: a video copied to `…/Videos/` was in `~/.cache/mediascanner-2.0/mediastore.db` within 8 s, so Music, Gallery and Videos see card media |
| Sequential write | 18.8 MB/s (512 MiB random data, `dd oflag=direct conv=fsync`, bs 4M). U1 is rated for at least 10 MB/s |
| Sequential read | 45.7 MB/s (`iflag=direct`). That is above the about 23 MB/s ceiling of 4-bit High Speed, so the card runs in a UHS-I mode. The SSR's first byte (bus width 0) was a false alarm |
| Data integrity | SHA256 of the 512 MiB read back with direct I/O matches the source |
| Small files | **Slow: 101.6 ms per file** (200 × 64 KB in one process: 20.30 s in write+close, 0.02 s in sync). Internal ext4 takes 0.9 ms per file |
| Filesystems | Kernel has `vfat` and `exfat` (`CONFIG_EXFAT_FS=y`), plus `fuse`. No NTFS. `dosfstools` is installed, `exfatprogs` is not |

### Small files: what is wrong, and the fix

- The 100 ms is the vfat `flush` mount option. On every `close()` of a file opened for writing, `fat_file_release()` writes the file out and then sleeps `HZ/10`. The time all goes into close, not sync, and it is a fixed 100 ms, independent of the 64 KB size.
- Copying a folder of 1000 photos or songs to the card (MTP or a file manager) would spend at least 100 s just sleeping. Upstream Linux still has this sleep.
- `flush` comes from udisks 2.10's built-in `vfat_defaults=uid=$UID,gid=$GID,shortname=mixed,utf8=1,showexec,flush`. There was no `/etc/udisks2/mount_options.conf`. udisks' exFAT defaults have no `flush`.
- Android's vold mounts FAT cards without `flush`.
- Fix: `boot/ut-init/rootfs-overlay/etc/udisks2/mount_options.conf`, `[defaults] vfat_defaults=uid=$UID,gid=$GID,shortname=mixed,utf8=1,showexec`. That is udisks' default without `flush`. It applies at the next mount (reboot, or take the card out and back in).
- Trade-off: without `flush`, written data goes out with normal writeback (about 30 s) instead of at close, so pulling the card straight after copying can lose the most recent writes. The rule is to unmount (eject) first, as on Android.
- It also applies to FAT USB sticks on OTG.
- Live install: `tools/phone-debug/stone-sdcard-install.sh` (sudo), which installs the file from `/home/phablet/mount_options.conf`.

Result after the live install and re-inserting the card: the mount options are `…,shortname=mixed,showexec,utf8,errors=remount-ro`, without `flush`.

| Test | Before (`flush`) | After |
| --- | --- | --- |
| 200 × 64 KB, one process | write+close 20.30 s, sync 0.02 s: 101.6 ms/file | write+close 0.04 s, sync 1.29 s: **6.6 ms/file**, contents verified |
| Same on internal ext4 (reference) | 0.9 ms/file | 0.8 ms/file |
| 512 MiB `dd oflag=direct` write | 18.8 MB/s | 15.9 MB/s (direct I/O does not use `flush`; the card's own variation) |
| 512 MiB `dd iflag=direct` read | 45.7 MB/s | 45.7 MB/s |
| 512 MiB `cp` + `sync` (how a file manager copies) | — | 35.9 s (15 MB/s) |
| SHA256 of the 512 MiB on the card | matches | matches |

The real cost of a small file is now the card's own write time, flushed at `sync` (6.4 ms/file), instead of a sleep.

Image: `boot-ut.img` SHA256 `ec969650b803d156409dad34bd97e3a97508fc0fe32bdcad59af45e97136459e` (kernel `#14`, unchanged; adds `etc/udisks2/mount_options.conf`). The previous image is kept as `out/halium14/boot-ut-a706816c.img`. The live-installed `/etc/udisks2/mount_options.conf` is byte-identical to the overlay's, so writing the image changes nothing on this phone.

### Other findings (no change)

- The built-in formatter made FAT32, probably because `exfatprogs` (`mkfs.exfat`) is not installed. FAT32 cannot hold files of 4 GiB or more: long camera videos or large downloads to the card will fail at 4 GiB.
- Cards over 32 GB come formatted as exFAT from the factory. The kernel's exFAT driver and udisks' `exfat_defaults` mean such cards should mount, but this has not been tested with a real exFAT card. Without `exfatprogs`, the phone cannot check or repair exFAT, and its formatter cannot make it.
- The card has no partition table (a "superfloppy"). Linux, Android and Windows 10+ read that. Some cameras and older systems want an MBR partition.

### Status (2026-11-11)

| Part | State |
| --- | --- |
| Detection, mount, MTP, media scanner | Working |
| Sequential speed, integrity | Working (18.8 MB/s write, 45.7 MB/s read, checksum matches) |
| Small files | Fixed: 101.6 → 6.6 ms per file (live install, confirmed after re-inserting the card) |
| exFAT cards | Kernel support present; not tested with a real card |

### Events

- 2026-11-11: the user reported the card works (detected, MTP). Checked the device, the mount, the media scanner, speed and integrity (all fine) and small files (100 ms each, from vfat `flush`). Wrote `etc/udisks2/mount_options.conf` and `stone-sdcard-install.sh`, and pushed `mount_options.conf` and the script to `/home/phablet`. The test files on the card (`sdtest.bin`, `Videos/sdtest-video.mp4`) were removed; `/home/phablet/sdtest.src` (512 MiB random data) is kept for the re-test.
- 2026-11-11: the user ran `stone-sdcard-install.sh`. The script finished, but `adb shell -t` with sudo did not return; it was safe to kill. The user took the card out and put it back in: mounted without `flush`. Small files went from 101.6 to 6.6 ms/file, and the sequential tests and checksums are as before. Built `ec969650…`. Removed `mount_options.conf`, `stone-sdcard-install.sh` and `sdtest.src` from `/home/phablet`.

## 5. Camera leftovers

Goal: flash and torch, tap-to-focus, zoom and the barcode reader work.

What is seen: not tested (`docs/roadmap-hardware.md` item 7). The flash shares TLMM pin 38 with the camera sensors (kernel patch 0005). Photo orientation depends on item 1.

Skipped (2026-11-11): the user reports these already work well. No changes.

## 6. Power

Goal: the phone suspends when the screen is off, standby drain is reasonable, and Settings shows the battery level and health.

What is seen: not checked yet.

Skipped (2026-11-11): the user reports this already works well. No changes.

## 7. Location (GNSS)

Goal: a position fix in a maps app, through the Android GNSS HAL.

What is seen (user, 2026-11-11): Pure Maps (OpenStore, `pure-maps.jonnius` 3.5.0) could not find the position.

### Checked so far (2026-11-11, indoors)

- The stack:
  - `lomiri-location-service` 3.4.1, started through lxc-android-config's `lomiri-location-serviced-wrapper` with `--provider gps::Provider --provider remote::Provider`;
  - the GPS provider (`providers::gps::android::HardwareAbstractionLayer`) calls Halium's `libubuntu_platform_hardware_api` (`u_hardware_gps_*`), which reaches the vendor's HIDL `android.hardware.gnss@2.1-service-qti` (`gnss_service`, running) through `libubuntu_application_api.so` and the `gnss@1.0`–`@2.1` interfaces in the Halium system image;
  - `loc_launcher` is running.
- Service state over D-Bus (`busctl get-property com.lomiri.location.Service`): `State=enabled`, `DoesSatelliteBasedPositioning=true`, `IsOnline=true`, `DoesReportCellAndWifiIds=false`.
- Permission: `~/.local/share/LomiriLocationService/trust.db` has `pure-maps.jonnius_pure-maps`, answer 1 (granted).
- The HAL delivers satellite status: `VisibleSpaceVehicles` had 26 GPS entries after Pure Maps' attempt. Two had signal (PRN 11 at 29 dB-Hz, PRN 21 at 27), one had ephemeris, none was used in a fix. The chain from the Qualcomm engine to lomiri-location-service works, and the RF front end receives satellites. Indoors, with a cold start, no fix is expected.
- Assistance data:
  - UT's `/etc/gps.conf` (from `liblomiri-location-service3`) points XTRA at `http://xtra{1,2,3}.gpsonextra.net/xtra2.bin`. All three still serve data (200, 27 to 62 KB), and so does `path1.xtracloud.net`. The phone resolves them. The service downloads XTRA only when the HAL asks.
  - The vendor's `izat.conf` enables `xtra-daemon` and `slim_daemon`, but neither is running under `loc_launcher` and neither has a tombstone. `lowi-server` and the `xtwifi-*` agents are disabled. Without XTRA, a cold first fix outdoors can take minutes.
  - The vendor `gps.conf` has `SUPL_MODE=3`, `NTP_SERVER=time.xtracloud.net`, `XTRA_SYSTEM_TIME_INJECT=1`.
- Not related: `vndservicemanager` aborts on `selinux_status_open` (`selinux=0`). Its 19 tombstones are all from early boots; this boot it runs with a stable pid.
- Logging gaps:
  - lomiri-location-service uses glog without file output, so nothing it logs reaches the journal or `/tmp`. `GLOG_logtostderr=1` fixes that: the provider's start-up line (`android_hardware_abstraction_layer.cpp:276 … on_set_capabilities`) then appears in the journal.
  - Android logcat needs root (`lxc-attach`).
  - `lomiri-location-serviced-cli --test` refuses to run without root. **Do not use it with the service running**: its fixture (`runtime_tests.cpp`) runs `service lomiri-location-service stop` and only starts the service again when the test ends. The test does `delete_all_aiding_data()`, a standalone cold start, and waits up to 15 minutes for a fix, three times.

### First outdoor test (2026-11-11, invalid)

- The first `stone-gnss-debug.sh start` ran `cli --test` in the background. The test stopped lomiri-location-service at 09:28:02, 4 s after the debug restart, and nothing started it again until `stop` at 09:36:55. During the user's walk there was no service, so Pure Maps could not get a position. The logcat capture was empty because the script's `pkill -f` pattern matched its own `sh -c`. Both are fixed in the script.
- What the walk did show: the CLI test drove the HAL directly in standalone mode. Its output has 6 satellite reports, all empty, all at 09:28 (the file was last written then). For the remaining 8 minutes outdoors, the engine reported nothing to it.
- Indoors afterwards, as phablet, with `tools/phone-debug/gnss-monitor.qml` (a QtPositioning session through the `lomiri` plugin, like Pure Maps; `sourceError` 3 = `NoError`) for 2 minutes, plus `gdbus monitor` on the service:
  - the service went `active` with `ClientApplications=['unconfined']`;
  - in 2 minutes it published only 2 `VisibleSpaceVehicles` changes, each with one satellite (keys 163 and 80, about 29 dB-Hz, no ephemeris), and no position;
  - a running Qualcomm engine reports its whole satellite list every second. Either the engine barely runs, or the HAL → platform API → service path delivers only some reports. That is the next thing to find.

### Next: outdoor test with logging

`tools/phone-debug/stone-gnss-debug.sh` (sudo):
- `start` adds a runtime drop-in for lomiri-location-service (`GLOG_logtostderr=1 GLOG_v=1`) and restarts it, captures Android logcat in the container, runs `lomiri-location-serviced-cli --test` in the background (positions as they arrive, up to 30 min), and saves a snapshot of the processes, properties and satellites.
- `stop` saves everything to `~/gnss-debug/` and removes the drop-in. The drop-in lives in `/run` and is gone after a reboot anyway.

`run [SECONDS]` does `start`, holds `gnss-monitor.qml` as phablet for SECONDS (180), then `stop`. It can be run indoors, because the question now is what the HAL reports per second, not whether there is a fix.

### Indoor captures with logging (2026-11-11)

`stone-gnss-debug.sh run 180` twice, as root and indoors. The logcat capture was changed to `logcat -d` at stop: a background `logcat -f` started through `lxc-attach` does not survive it returning. Logs are in `out/halium14/logs/gnss-2/` and `gnss-3/` (gitignored).

- **The engine is healthy.** With `GLOG_v=200` the service logs every NMEA sentence: 181 `$GPRMC` in 180 s, and 180 `on_sv_status_update` calls (up to 12 satellites). Halium's bridge (`ubuntu_application_gps_for_hybris`) reports "AIDL IGnss service not declared, skipping AIDL backend", then "HIDL GNSS backend initialized successfully", and passes `gnssNmeaCb`, `gnssSvStatusCb`, `gnssStatusCb` and `gnssSetCapabilitesCb`.
- The sparse `VisibleSpaceVehicles` changes seen before come from the service. Its satellite handler is GPS-only and legacy (PRN 1 to 32 used as bit positions; every satellite typed `gps`; GLONASS 65 to 96 and BeiDou keys mislabelled), and the property only notifies on change. Cosmetic.
- **But it starts cold every time.** It tracked GPS 25 and 28 and GLONASS 69, 79 and 80 at 22 to 33 dB-Hz, all with elevation 00 and azimuth 000 (no almanac, ephemeris or XTRA). The NMEA showed `$GPRMC,,V`, `$GPGGA` quality 0 and `$GPGSA,A,1`: no fix. Nobody asked UT for time or XTRA either: `on_request_utc_time` and `on_xtra_download_request` were never called.
- SUPL: `LocSvc_Agps: NULL AGNSS NIF ! / No AGPS State Machine for agpsType: 1 apnTypeMask: 0x10`. The HAL wanted a SUPL data connection, but nothing registered the AGNSS callbacks Android's framework would register. Not fixed; see below.

### GNSS: what fixed it

1. **`xtra-daemon` was not running.** It is Qualcomm's assistance agent: it fetches NTP time (`time.xtracloud.net`) and XTRA orbit data (`https://path{1,2,3}.xtracloud.net/xtra3grej.bin`) and injects both into the modem's GNSS engine.
   - The vendor `init.qcom.rc` has `on property:persist.sys.xtra-daemon.enabled=*` → `restart loc_launcher`, and `loc_launcher` only starts it when that property is set. On Android, Qualcomm's framework apps set it; here it was unset.
   - `setprop persist.sys.xtra-daemon.enabled true` (phablet may set it): `loc_launcher` restarted, `xtra-daemon` (uid 1021) started at once, and `/data/vendor/location/xtra/` and `nvparam.sqlite` appeared.
2. **The HAL believed there was no network.** The next capture had `xtra-daemon: onRequestXtraData … isCon:0 isNonMetered:0 isGpsEnabled:1` and then `XTRA download result status:4 starting timer for 300 sec`.
   - On Android, the framework (`GnssNetworkConnectivityHandler`) reports every connectivity change to the HAL through `IAGnssRil::updateNetworkState`. Nothing on UT did that.
   - python3-gbinder as phablet, on `/dev/hwbinder`: `android.hardware.gnss@1.0::IGnss/default` → `getExtensionAGnssRil()` (transaction 9) → `IAGnssRil::updateNetworkState(true, WIFI, false)` (transaction 4) returned `true`. `updateNetworkAvailability` (transaction 5) returned `false` (not implemented in QTI's HAL; harmless).
   - Within 5 s, `xtra-daemon` connected to `18.164.96.40:443` (`path1.xtracloud.net`). DNS inside the container works; only the network state was missing.
3. **Result:** a 60 s QtPositioning session (`gnss-monitor.qml`) indoors:
   - first valid position at about 30 s, accuracy 4 m;
   - 115 updates in the minute;
   - `VisibleSpaceVehicles` had 16 satellites, 9 with signal, 14 with predicted azimuth/elevation, 4 with ephemeris and 4 used in the fix.

   (The coordinates are not recorded here.)

Made permanent: `stone-gnss-netstate.service` (`User=radio`, `Restart=always`), which runs `usr/lib/stone/gnss-netstate.py`:
- sets `persist.sys.xtra-daemon.enabled=true` if it is not `true` (fresh installs; on this phone the persist property already survives reboots);
- calls `updateNetworkState(connected, WIFI|MOBILE, roaming=false)` and `updateNetworkAvailability`. It does that at start, on every NetworkManager `StateChanged`/`PropertiesChanged` (connected when `State` ≥ 60; WIFI for `802-11-wireless` and Ethernet, otherwise MOBILE), whenever hwservicemanager reports `IGnss/default` registered (HAL restarts, and once at start), and every 10 minutes.
- It only uses the `IAGnssRil` extension and does not touch the IGnss callbacks that lomiri-location-service owns.

python-gbinder details: the readers return `(ok, value)`. `ServiceManager.add_registration_handler(name, func)` stores `func` as an instance attribute, which only works on a Python subclass of the Cython class.

Live install: `tools/phone-debug/stone-gnss-install.sh` (sudo). Image: `boot-ut.img` SHA256 `065ee6e561d036d5ba4c48c227b189b74d8dbba73102370f6f122fe81c0d5b81` (kernel `#14`, unchanged; adds the service). The previous image is kept as `out/halium14/boot-ut-ec969650.img`.

### Still open (location)

- SUPL / A-GNSS over the mobile network (`NULL AGNSS NIF`): **not implemented, by decision (2026-11-11).**
  - Halium's bridge (`libubuntu_application_api.so`) supports HIDL AGNSS: `IAGnssCallback`, `dataConnOpen`/`dataConnClosed`/`dataConnFailed`, `setServer`, IPv4 status ("AgnssStatusIpV6 not implemented").
  - lomiri-location-service 3.4.1 stops there. `on_agps_status_update()` only stores and logs the status, and nothing in the service ever calls `SuplAssistant::set_server` or `notify_data_connection_*`. SUPL is unimplemented upstream, on every device.
  - Adding it would mean a new component: a SUPL server (AOSP's default is `supl.google.com:7275`) and answering the HAL's data-connection requests. SUPL also sends the SIM identity and the serving cell to that server.
  - With XTRA and NTP time now working, the gain is small: a first fix in seconds instead of under a minute, and assistance without Wi-Fi or mobile data. XTRA files cover several days, so assistance also lasts through short offline periods.
- The service's satellite list is GPS-only and mislabels other constellations (upstream lomiri-location-service).
- In the third capture my unconfined test client got "Client lacks permissions to access the service with the given criteria" when started with `runuser` from the root script. The same client started from an adb shell was allowed. Only this test tool is affected; the apps (Pure Maps, uNav) have their trust entries (granted).
- Network-based location (Wi-Fi/cell, no GPS): `DoesReportCellAndWifiIds=false`, and no remote provider is installed. 24.04 ships none since the HERE provider and Mozilla Location Service went away. Out of scope.

### Result (2026-11-11)

Confirmed by the user: Pure Maps finds the position. The user flashed `065ee6e5…` and rebooted. Checked over adb:
- `stone-gnss-netstate` is active, the installed `gnss-netstate.py` is byte-identical to the overlay's, and `xtra-daemon` has run since boot;
- the user's network switches were followed: at 254 s `gsm/70 → updateNetworkState(connected=True, type=MOBILE) = True`, at 362 s back to `802-11-wireless/70 → … WIFI = True`.

The location item is done. What remains is optional or upstream (SUPL, satellite labelling).

### Events

- 2026-11-11: the user reported Pure Maps cannot find the position. Checked the stack, the service state, the permission, the satellite status (the HAL works: 26 satellites, 2 with signal indoors, no fix), the XTRA servers (alive) and the Qualcomm daemons (`xtra-daemon` enabled but not running). Wrote and pushed `stone-gnss-debug.sh`.
- 2026-11-11: outdoor walk, no position, but the test was invalid: `cli --test` had stopped the service (see "First outdoor test"). The script was fixed (no `--test`, logcat pattern, new `run` mode), and `gnss-monitor.qml` was added. Indoors: only two one-satellite reports in 2 minutes. Waiting for the user to run `stone-gnss-debug.sh run` indoors.
- 2026-11-11: indoor captures 2 and 3 (see above). Engine healthy, but a cold start with no time or XTRA. Set `persist.sys.xtra-daemon.enabled=true` (xtra-daemon started). Found `isCon:0`, and called `IAGnssRil::updateNetworkState` by hand: XTRA downloaded, and a first fix came indoors in about 30 s with 4 m accuracy. Wrote `stone-gnss-netstate.service`, tested it as phablet (start push, HAL registration push, keeps running), and built `065ee6e5…`.
- 2026-11-11: the user flashed `065ee6e5…`: Pure Maps finds the position. The service was active from boot and followed Wi-Fi → mobile → Wi-Fi. SUPL was looked at and left out (unimplemented upstream; privacy cost, small gain). Logs of the three captures are in `out/halium14/logs/gnss-{1,2,3}/`. The debug output and install copies were removed from `/home/phablet`; `stone-gnss-debug.sh` and `gnss-monitor.qml` are still there.

## 8. Fingerprint reader

Goal: enrolling a fingerprint and unlocking with it in Lomiri, if the vendor's fingerprint HAL can be reached.

What is seen: not checked yet.

## 9. Smaller items

- The second SIM slot.
- Call volume keys controlling the call volume (`Voice Rx Gain`) instead of the media volume (`docs/roadmap-hardware.md` item 6).
- Wideband Bluetooth calls (mSBC). Calls are now narrowband CVSD with `enable_msbc=false`.
- The IR emitter and NFC: first check whether this model has them.

## 10. GPU and graphics APIs

Goal: know which GPU path the system uses, whether that is the intended one, and which APIs (OpenGL ES, OpenGL, Vulkan) have hardware acceleration.

What is seen: hardware acceleration seemed to work since the first boot (smooth UI), but it was never tested.

### Current state (2026-11-11, image `065ee6e5…`)

**The path in use is the intended one.**
- UBports' Mir 1.8.3 fork (`mir1`) has a single server platform, `/usr/lib/aarch64-linux-gnu/mir1/server-platform/graphics-android2.so.16`. It composes through hwcomposer, as on any Halium device.
- Lomiri (`lomiri --mode=full-greeter`) has these mapped:
  - glvnd `libEGL.so.1` → `libEGL_libhybris` → Android `libEGL` (META-EGL) → `/vendor/lib64/egl/libEGL_adreno.so`, `libGLESv2_adreno.so`, `libgsl.so` (the KGSL client) and `libllvm-glnext.so` (Adreno shader compiler);
  - the QTI gralloc mapper 4.0, `graphics-android2.so.16` and `eglplatform_null`.

  `libEGL_mesa` is mapped too, because glvnd loads every vendor (`/usr/share/glvnd/egl_vendor.d/10_libhybris.json` before `50_mesa.json`), but it is not what renders.
- Apps (morph-browser, for example) map the same Adreno libraries.

Device nodes: `/dev/kgsl-3d0` (`system:system 0666`, the GPU) and `/dev/dri/card0` + `renderD128` (`root:android_graphics 0666`), which belong to the msm display (SDE) driver. That DRM device has no GPU behind it: the Adreno is only reachable through KGSL.

GPU: `Adreno619v2`, 266/390/490/650/700 MHz, devfreq governor `msm-adreno-tz`, scaling as expected (390 MHz, 38 % busy right after the tests), `thermal_pwrlevel` 0.

Measured with `tools/phone-debug/gpu-probe.py`: ctypes probes, because the rootfs has no eglinfo, glxinfo or vulkaninfo. They run as phablet, headless (pbuffer), with `GLIBC_TUNABLES=glibc.rtld.optional_static_tls=65536` for libhybris in Python (see item 3).

| API | Path | Result |
| --- | --- | --- |
| OpenGL ES 2.0/3.x | libhybris → Adreno (`EGL_PLATFORM=null`, pbuffer) | **Hardware.** `Qualcomm` / `Adreno (TM) 619` / `OpenGL ES 3.2 V@0530.0 (GIT@c263890aed, Ifb496a9c37, 1656315076) (Date:06/27/22)`, GLSL ES 3.20, 98 GL extensions, EGL 1.5 "Android META-EGL" with 45 extensions. glClear + glReadPixels read back exactly `[64, 128, 191, 255]` |
| OpenGL (desktop) | libhybris → Adreno | **Not available.** `EGL_CLIENT_APIS` is only `OpenGL_ES`; a GL config fails with `EGL_BAD_ATTRIBUTE` |
| OpenGL (desktop) and GLES | Mesa 24.0.9 (`EGL_PLATFORM=surfaceless`, Mesa vendor only) | **Software:** `llvmpipe (LLVM 17.0.6, 128 bits)`, OpenGL 4.5 Compatibility / GLES 3.2. The same with `MESA_LOADER_DRIVER_OVERRIDE=kgsl` or `msm`: surfaceless only opens DRM render nodes, `renderD128` is display-only, and Mesa 24.0's Gallium freedreno has no KGSL backend (`kgsl_dri.so` exists but is not reached) |
| Vulkan | `libvulkan1-hybris` (`/usr/lib/aarch64-linux-gnu/libvulkan.so.1.2.183`, libhybris's own loader; no Khronos ICDs installed) → `/vendor/lib64/hw/vulkan.adreno.so` | **Hardware.** 13 instance extensions including `VK_KHR_wayland_surface`. One device: `Adreno (TM) 619`, integrated, API **1.1.128**, driver `0x80212000` (512.530.0), vendor `0x5143`, 63 device extensions including `VK_KHR_swapchain` and `VK_ANDROID_external_memory_android_hardware_buffer`. `vkCreateDevice`, a queue and `vkDeviceWaitIdle` all succeed |
| Vulkan on screen | libhybris `test_vulkan` (Wayland client on Lomiri's `wayland-0`: surface, swapchain, render loop) | Runs: past 1140 frames in 12 s, clean exit. The screen was off, so presentation was not throttled and nobody saw the window |

Lomiri itself (Qt Quick on GLES through Mir) is proof of on-screen GLES. "`dlopen failed: library "libadreno_app_profiles.so" not found`" is printed by the Adreno driver at start. This vendor does not ship that library (per-app tuning profiles), so it is harmless.

### Recommendations

Nothing needs fixing for the system. The UI, Qt apps, QtWebEngine and Vulkan apps all get the GPU. Options, if they are ever wanted:

1. **Hardware desktop OpenGL** (Libertine/X11 desktop apps, some games). Today these fall back to llvmpipe on the CPU.
   - Lowest risk: **gl4es** (OpenGL 1.x/2.1 → GLES 2 translation, as a library or `LD_PRELOAD`) on top of the hybris GLES. It covers older GL apps and games. It is not in Ubuntu's archive, so it would need building and shipping.
   - Research only: **turnip (Mesa Vulkan) with its KGSL backend, plus zink** (Mesa OpenGL on Vulkan), which would give OpenGL 4.6 and Vulkan 1.3 in hardware with open drivers. It needs Mesa built with `-Dfreedreno-kmds=kgsl` (Ubuntu builds only `msm`), a Vulkan loader that coexists with `libvulkan1-hybris`, and buffer sharing with the hybris/Mir compositor. That is a large project.
   - zink on the vendor Vulkan through libhybris is not recommended: Vulkan 1.1.128 lacks much of what zink needs, and zink expects Mesa's winsys.
2. **Vulkan 1.1 → 1.3** would need newer Adreno blobs than this vendor's 2022 `V@0530` (the A619 hardware gets 1.3 from newer drivers). Replacing GPU blobs under a vendor is risky. Not recommended unless an app needs it.
3. Optional check: run libhybris' `test_vulkan` with the screen on and unlocked (`XDG_RUNTIME_DIR=/run/user/32011 WAYLAND_DISPLAY=wayland-0 test_vulkan`) to see its window. Headless and off-screen presentation already work.

### Events

- 2026-11-11: the user reports acceleration has seemed fine since the first boot. Checked the compositor path, the device nodes and the GPU clocks. Probed GLES (hardware), desktop GL (Adreno: none; Mesa: llvmpipe, also with the kgsl/msm overrides) and Vulkan (hardware, device creation, and `test_vulkan` presenting on Lomiri's Wayland). Wrote `tools/phone-debug/gpu-probe.py`. No changes to the image.

