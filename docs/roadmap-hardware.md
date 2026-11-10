# Hardware, after the display is up


The goal of `docs/roadmap-halium14.md` has been reached. On 2026-11-09 the user confirmed Ubuntu Touch had entered Lomiri, and that display, touch, GPU, brightness, charge detection, and vibration all work. This document only covers hardware that is not working yet. Do not reflash `vendor_boot`, `dtbo`, `vbmeta`, or `super`. `boot_b` is now the normal `boot-ut.img` (kernel `#7`). It has no passwordless sudo, and it does not return to fastboot by itself.

`/etc/os-release` is Ubuntu 24.04.5 LTS. The root filesystem comes from `ubuntu-touch-android9plus-rootfs-arm64.tar.gz` on the 24.04-2.x channel. adb is up, serial `stone`. The phone clock is still in 1970. If Wi-Fi associates and certificate checks then fail, set the time first.

## Already confirmed working

- Display, touch (`fts_ts`), GPU acceleration, a smooth UI, and brightness control.
- Charging: `/sys/class/power_supply/battery/status` is `Charging`. The user confirmed the phone recognizes that it is charging.
- Vibration: `/sys/class/leds/vibrator` exists, and the user confirmed it works.
- adb.

## Fix order

1. Grow storage. The cause is already clear, and only about 4G of free space remains. Later kernel builds and log captures all write to userdata.
2. Rebuild the vendor modules with this kernel tree. The Wi-Fi, sound, Bluetooth, and camera `.ko` files are all `5.4.259-qgki` and will not load into `5.4.283~positron`. `lsmod` is empty. Until this item is done, the next four stall because the drivers are not up.
3. Sound. PulseAudio has only a fake SCO sink. What the user hears is complete silence.
4. Wi-Fi. The Android wifi HAL is already running. What is missing is `wlan0`.
5. SIM. ofono has no modem at all. This is not the same path as the `.ko` files above, so it is investigated separately, after the drivers.
6. Bluetooth. `/dev/vhci` does not exist, and bluebinder is in a restart loop. Enable `CONFIG_BT_HCIVHCI` in the same kernel build as item 2. Leave verification for this item.
7. Camera. The nodes are present, and the app exits as soon as it opens. This is last, because the display stack already works and a crash is more likely `camera.ko` and the HAL.

## 1. Grow storage

Goal: the root filesystem uses all of `sda19`, and Internal Storage in Settings is close to this machine's userdata (128 GB class), not the current roughly 10 GB.

What is seen: the whole disk `sda` is 113.1G. `sda19` (label userdata, mounted at `/`) is 103.5G. `df -h /` shows only 7.7G, 3.4G used, 4.0G available. Settings shows about 9.9GB. `out/halium14/userdata-ut.img` was built as 8GiB. Flashing it covers only the start of the partition, and there was no `resize2fs`.

### Planned steps

1. Grow the ext4 online to the end of `sda19`. An ext4 grow can be done while mounted. userdata does not have to be reflashed.
2. The current image has no passwordless sudo, and the phablet password is unknown. Growing needs root. Solve that before running it.
3. After the grow, check `df` and the capacity in Settings. Confirm existing files are still there.

### Implementation notes

2026-11-09: grown online. Partition `sda19` is 217087640 sectors of 512 bytes. The filesystem was originally 2097152 blocks of 4K (8GiB). Both `resize_inode` and `64bit` are present. `resize2fs` 1.47.0 grew it while mounted to 27135955 blocks, exactly the end of the partition. `df -h /` went from 7.7G to 101G. Used is still 3.4G, available 93G. `/etc/os-release` and `/home/phablet` are still there.

The normal image has no passwordless sudo. phablet set a password in the wizard. `boot-ut-trace.img` (`5da875e07435848fb10dc3213a949eb4c4856c1849a7e792d14582fdce580365`) was written to `boot_b` temporarily, its passwordless sudo ran the grow, and then `boot-ut.img` (`7817dbfd45d4fa86b8a977f6504ba11ceb66aabc64b0b7b1c3884ea4596ef264`) was written back. userdata was not reflashed. After the write-back the phone booted normally, `df` was still 101G, `/etc/sudoers.d/` had no passwordless file from the trace image, and Lomiri was running. Nobody has looked at the number in Settings yet.

### Events

- The user put the phone into fastboot. `current-slot` was `b`. The trace image was written and the phone rebooted. SSH was up after 10 seconds, and `sudo -n` was root.
- `resize2fs /dev/sda19` returned 0. Block count 2097152 → 27135955. `df` was 101G, 3.4G used.
- The normal `boot-ut.img` was written back and the phone rebooted. After adb came up, `df` was still 101G and existing files were still there.

## 2. Rebuild the vendor modules with this kernel tree

Goal: the Wi-Fi, audio, Bluetooth-power, and camera drivers are built from the same tree as kernel `#7`, the vermagic matches, and they show up in `lsmod` after boot.

What is seen: `uname -r` is `5.4.283~positron/42e99ef7`. `/android/vendor/lib/modules/` has 39 `.ko` files. The vermagic of `qca_cld3_wlan.ko` is `5.4.259-qgki-g3ad529ef5970 SMP preempt mod_unload modversions aarch64`. The two sides do not match, so none of them loaded. The source is in this `android_kernel_xiaomi_sm6375` 14.0 tree: `drivers/staging/qcacld-3.0`, `techpack/audio`, `techpack/camera`, `techpack/datarmnet`. `halium-sunstone.fragment` has not enabled them yet.

### Planned steps

1. Do not insmod the existing `.ko` files.
2. In the fragment, enable qca-cld3, the audio techpack (q6, bolero, wcd938x, machine), camera, and `CONFIG_BT_HCIVHCI`. Build them as modules when that is possible.
3. Produce a new kernel and write it to `boot_b`. Leave the other partitions alone. Keep the Android 14 rollback image `out/halium14/boot.img` untouched.
4. After boot, look at `lsmod`, `wlan0`, the sound card, and `/dev/vhci`. Leave the actual functions to items 3, 4, 6, and 7.

### Implementation notes

2026-11-09: the kernel was built and has not been written to the phone yet. `adb reboot` cannot write reboot arguments. The phone is still running `#7`.

The sound card, camera, and Wi-Fi character device were already present in `#7`. They were not left unbuilt. `/proc/asound/cards` has `holi-qrdsku1-snd-card`, `/dev/video*` is present, `/dev/wlan` (major 499) is present, and `/dev/btpower` is present. `lsmod` is empty because the techpack was built into the kernel with `obj-y`, not as modules. The vendor `.ko` files still do not match vermagic, and they were not used.

Two config options were actually missing. `CONFIG_BT_HCIVHCI` was off, so there was no `/dev/vhci`. `CONFIG_CNSS_QCA6750` was off, so qcacld did not take the WCN6750 IPCI path. Also, a built-in driver waits for userspace to write `ON` to `/dev/wlan` before it calls `hdd_driver_load()`. After `vendor.wifi_hal_legacy` came up it had already exited, and dmesg has no "Wifi Turning On".

`kernel/config/halium-sunstone.fragment` gained `CONFIG_BT_HCIVHCI=m` and `CONFIG_CNSS_QCA6750=y`. The `#7` Image is kept at `out/halium14/Image-7`. The new kernel is `#8 SMP PREEMPT Mon Nov 9 19:42:19 EST 2026`. `kernel/build-14/arch/arm64/boot/Image` is 48724480 bytes, SHA256 `9840667736b261d43c78e0619b89363188707f1d176ff1934fea7bf93b886433`. The vermagic of `hci_vhci.ko` is `5.4.283~positron/42e99ef7 SMP preempt mod_unload modversions aarch64`.

The boot image carries two things to do at boot. `stone-vhci.service` runs `insmod /lib/modules/stone/hci_vhci.ko`. `stone-wlan-on.service` writes `ON` to `/dev/wlan` after `lxc-android-config.service`. The `boot-ut.img` written first has SHA256 `db3ea3cf7d5f9bdefc4cd0f1445a446bab8e814931e6a6d26e87a0b06ea091b0`.

After it was written, `uname` was `#8`. The sound card was still `holi-qrdsku1-snd-card`. `lsmod` was empty, and `/dev/vhci` was absent. `/lib` is a symlink to `usr/lib`. The initramfs busybox `cp -R` did not copy `lib/modules/stone/hci_vhci.ko` in, and `stone-vhci.service` was skipped by `ConditionPathExists`. The module was moved to `usr/lib/modules/stone/`. The corrected `boot-ut.img` has SHA256 `c32153dbaab0b590d20c6d1e3ed90abefd4e643eff1d9fdcd08fe4ed87e5f4c6`. It was written after the user entered fastboot again. `/lib/modules/stone/hci_vhci.ko` is present, `stone-vhci.service` is active, `lsmod` has `hci_vhci` (24576, Used by 1), and `/dev/vhci` is `crw------- root root 10, 137`. The sound card is still there. `wlan0` is still absent. bluebinder can open vhci, but the Android Bluetooth service then exits (`Bluetooth binder service failed` / `Remote has died`). That is left for item 6. adb still did not enumerate.

There is no `wlan0`. The driver has already recognized the QCA6750. The firmware reports ready at 19.0 seconds, then crashes early during probe (`PD service down ... cause: FW crash`), and `hif_wlan_enable` returns -110. `stone-wlan-on.service` gets an I/O error from writing `ON`. This is the firmware crashing during probe, not a module that failed to load.

RNDIS and SSH are normal. adb did not enumerate this time. On the phone only `adbd-approver` was visible, not `adbd`.

### Events

- Compared with the running `#7`: the sound card and `/dev/wlan` were already registered by built-in drivers, `/dev/vhci` did not exist, icnss2 reported WLAN FW ready, but nobody wrote `ON`, so there was no `wlan0`.
- Built `#8` and `hci_vhci.ko`.
- After the user entered fastboot, `db3ea3cf…` was written and the phone rebooted. `#8` came up, the sound card was present, `lsmod` was empty, there was no `/dev/vhci`, and there was no `wlan0`. The firmware crashed while probing the QCA6750.
- The module path was changed to `usr/lib/modules/stone/`. The new image `c32153db…` had not been written yet.
- The user entered fastboot again, and `c32153db…` was written. `hci_vhci` is in `lsmod`, and `/dev/vhci` exists. `wlan0` is still absent.

## 3. Sound

Goal: the speaker, earpiece, and headphones produce sound.

What is seen: the user confirmed there is no sound at all. PulseAudio 16.1 is running. The only sink is `sink.fake.sco` (`module-null-sink`, suspended). There is no real sound-card sink. `audiosystem-passthrough-qti` (`IQcRilAudio`) exits with status 2 after it finds the hwbinder service manager. On the vendor side, `q6_dlkm.ko`, `bolero_cdc_dlkm.ko`, `wcd938x_dlkm.ko`, and `machine_dlkm.ko` are all unloaded. Vibration works, so it is not the case that every audio-related HAL failed to start.

### Planned steps

1. Wait for the audio modules from item 2 to load.
2. Look at `/proc/asound/cards` and PulseAudio's sink list, and confirm there is a real output.
3. Test the speaker with a short tone. Test the earpiece and headphones when a device is attached.
4. Call audio (`audiosystem-passthrough-qti`) waits until item 5, after the SIM has a modem.

### Implementation notes

The sound card was already registered in item 2 (`holi-qrdsku1-snd-card`). There is no sound because PulseAudio cannot build a droid sink.

`module-droid-discover` loads `module-droid-card-30` from `ro.build.version.sdk` (34). That module does not recognize `AUDIO_OUTPUT_FLAG_SPATIALIZER` while parsing `/vendor/etc/audio/audio_policy_configuration.xml` (`immersive_out`, line 141). The whole policy is discarded, and only `sink.fake.sco` remains. After that port is removed, card-30 can parse the policy, but then it indirect-calls device vtable offset `0x110` inside `pa_droid_stream_set_route`. That slot is empty, and PulseAudio segfaults and exits. This HAL's `common.version` is `0x200` (`AUDIO_DEVICE_API_VERSION_2_0`). `open_output_stream` is at `0xd0`, not `0x110`. `module-droid-card-28` calls `0xd0`.

card-28's parser is older. It does not accept several flags, sample rates, or channel masks separated by spaces, and an included Bluetooth policy file trips an assertion that kills the process. The policy given to it was reduced in these ways: the spatializer port was removed, each flag, sample rate, and channel mask keeps only one value the parser knows, and the four included files were replaced with copies of the same reduction. `primary output` keeps `AUDIO_OUTPUT_FLAG_PRIMARY`.

The current session overrides `PULSE_SCRIPT` with phablet's user unit, pointing at `/home/phablet/.config/stone/touch.pa`, which was changed to load `module-droid-card-28`. That user configuration is still there after a reboot. The boot image does not have to be flashed again. The same change was placed in `boot/ut-init/rootfs-overlay/` (`/etc/pulse/stone-touch.pa`, the policies under `/usr/share/stone/`, and `pulseaudio.service.d/zz-stone-audio.conf`), so the next boot image carries it.

Result: both `sink.primary_output` and `sink.deep_buffer` exist, but the user confirmed neither the speaker nor the ringtone made any sound. `paplay` returning 0 only means the data entered the HAL. A 64-bit process loads `/vendor/lib64/hw/audio.primary.default.so` (an 11 KB empty AOSP implementation). The real HAL is the 32-bit `audio.primary.holi.so`, and PulseAudio cannot reach it.

Following `speaker` and `low-latency-playback` in `mixer_paths_qrdsku1.xml`, MultiMedia5 (`hw:holiqrdsku1sndc,9`) was connected to the speaker: `RX_MACRO RX2 MUX=AIF2_PB`, `RX INT2_1 MIX1 INP0=RX2`, `RX INT2_1 INTERP=RX INT2_1 MIX1`, `AUX_RDAC Switch=1`, `SpkrLeft Sipa Power=On`, `RX_CDC_DMA_RX_1 Audio Mixer MultiMedia5=1`. After a direct `aplay` to this device, the user confirmed they heard sound.

That path is now PulseAudio's default sink `sink.speaker` (`module-alsa-sink`). At boot, `speaker-route.sh` writes the mixer first. The current session uses the script and `touch.pa` in `/home/phablet/.config/stone/`, and they survive a reboot. The same files are `boot/ut-init/rootfs-overlay/usr/lib/stone/speaker-route.sh` and `etc/pulse/stone-touch.pa`, so the next boot image carries them. A 2-second 440 Hz tone was played again through `sink.speaker`, and the user confirmed they heard it. The earpiece and headphones are not on this path yet. The microphone and call audio are still undone.

The user then reported: the first key click after a pause is normal, and later ones are silent or very weak; ringtone preview in Settings does not play at all. The same operation plays the ringtone on Ubuntu Touch 24.04.2 on a Nothing Phone.

The unstable key clicks come from the mmap path in `msm-pcm-q6-v2.c`. At start it hands every period of the ring buffer to the DSP, and as soon as one finishes playing it queues it again. The DSP always holds the whole buffer. Data Pulse thinks it can still rewrite by rewinding has already been handed over. The first sound just after the device opens needs no rewind and is heard. While `module-suspend-on-idle` keeps the device open for about 5 seconds, later short sounds are inserted by rewind, so they are dropped or only a fragment remains.

The first change was `mmap=0`, and it was worse. In copy mode every write waits inside `msm_pcm_copy` for the DSP to return a period. Pulse's ALSA thread stays in D state for a long time, and the log says `q overrun, queuing locally`. The user heard a very large delay between key clicks, and the ringtone sounded about a minute later.

The current approach keeps mmap, shrinks the buffer to 4×10 ms (`fragments=4 fragment_size=1920`), and sets `rewind_safeguard=7680`, equal to the whole buffer. Pulse no longer rewinds, and a new sound starts at most 40 ms late. Six 80 ms tones in a row: each `paplay` took about 165 ms from connect to finished, with no queue. Both the user unit and the overlay `touch.pa` have been changed.

The ringtone does not play by writing to this sink directly. Preview in Settings is a Qt `Audio`, and Ubuntu Touch hands it to media-hub. This kernel's AppArmor does not fill in the peer label of a unix socket (`SO_PEERSEC` returns `ENOPROTOOPT`), and `/sys/kernel/security/apparmor/features/dbus/mask` does not exist. The session bus therefore answers `AppArmorSecurityContextUnknown` for every connection. media-hub gets an empty profile name and `abort`s, so the whole preview fails. The Nothing Phone's kernel can produce a label, so the same UI has sound.

The workaround lives in the user directory and does not need another boot image. `/home/phablet/.config/stone/media-hub-server` is a copy of `/usr/bin/media-hub-server`. An empty label is replaced with a static `unconfined` string, and parsing then continues as before. `~/.config/systemd/user/media-hub.service.d/zz-stone-unconfined.conf` points the service at that copy. `/usr/share/sounds/lomiri/ringtones/Ubuntu.ogg` was played along the same path Settings uses: media-hub no longer crashes, it plays on `sink.speaker` with `media.role=alert`, and it stops normally after about 8 seconds.

### Events

- `module-droid-card-30` failed to parse `AUDIO_OUTPUT_FLAG_SPATIALIZER`. After that port was removed it crashed on a null pointer at HAL vtable `0x110`.
- Switched to loading `module-droid-card-28`. `sink.primary_output` appeared, but the user confirmed there was no sound. The cause is the 64-bit empty HAL.
- Played with `aplay` along the qrdsku1 speaker path. The user confirmed they heard it.
- PulseAudio's default output was changed to `sink.speaker` (MultiMedia5). A short tone was played again, and the user confirmed they heard it.
- Only the first key click after a pause was normal. The cause is that the DSP does not rewind. `sink.speaker` was changed to `mmap=0`.
- Ringtone preview crashed media-hub: the kernel cannot produce an AppArmor peer label, and the empty name triggers abort. The media-hub in the user directory treats an empty label as `unconfined`. The same preview path finished `Ubuntu.ogg`, with output on `sink.speaker`.
- The user reported an extreme delay between key clicks, and the ringtone about a minute late. The cause is `mmap=0` leaving Pulse stuck in `msm_pcm_copy`. Switched back to mmap, a 40 ms buffer, and `rewind_safeguard` covering the whole buffer. Short tones no longer queue, and the ringtone preview starts on the speaker within about 0.85 seconds.

## 4. Wi-Fi

Goal: scan, associate, and get an IP address.

What is seen: the user confirmed Wi-Fi is unavailable. There is no `wlan0`. On the Android side, `vendor.wifi_hal_legacy` and `wificond` are both running, and `wifi.interface` is `wlan0`. The driver is `qca_cld3_wlan.ko`, and it is not loaded.

### Planned steps

1. Wait for item 2 to produce `wlan0`.
2. Scan and connect to a known network, and confirm DHCP.
3. If association succeeds but web pages fail, first check whether the phone clock is still in 1970.

### Implementation notes

### Events

## 5. SIM

Goal: ofono can see a modem, and Settings can recognize the SIM.

What is seen: the user confirmed the SIM is not recognized at all. `ofono` is running, `GetAvailableModems` returns 0, and `GetErrors` is also 0. `rmnet_data0` through `rmnet_data5` and `rmnet_ipa0` already exist, so the data-interface path has at least been created. In the previous document `qcrilNrd` had a crash loop. This time adb logcat did not capture a new RIL line.

### Planned steps

1. Read logcat for `qcrilNrd` and `rild` inside the container, and ofono's journal. First separate "the baseband did not come up" from "ofono never tried to connect."
2. After a modem object exists, look at SIM state, signal, and the operator.
3. Call audio returns to the `audiosystem-passthrough-qti` left by item 3.

### Implementation notes

### Events

## 6. Bluetooth

Goal: bluebinder stays running and can scan for devices.

What is seen: the user confirmed Bluetooth is unavailable. `bluetooth.service` is active. `bluebinder.service` is stuck in activating, and the restart count has passed 646. `bluebinder_wait.sh` thinks the Android Bluetooth service is running, then `Failed to open /dev/vhci device`. systemd records `Error: 19 (No such device)`, and the result is `protocol`. `/dev/vhci` needs `CONFIG_BT_HCIVHCI`, which the current kernel does not have. `btpower.ko` is not loaded either.

### Planned steps

1. The kernel from item 2 already includes `CONFIG_BT_HCIVHCI` and `btpower`. This item only verifies.
2. Confirm `/dev/vhci` exists and `bluebinder` is no longer restarting.
3. Scan for nearby devices.

### Implementation notes

### Events

## 7. Camera

Goal: the camera app can open and show a preview.

What is seen: the user confirmed the camera flashes and exits as soon as it opens. `/dev/video0`, `video1`, `video2`, `video32`, and `video33` are present, and so are `/dev/video/venus_dec` and `venus_enc`. `camera.ko` is not loaded. No application-side crash stack was captured this time.

### Planned steps

1. Wait for `camera.ko` from item 2 to load, then open the camera and see whether it still crashes or can preview.
2. If it still crashes, take the journal and logcat and check them against the HAL. Do not change the display stack first.

### Implementation notes

### Events
