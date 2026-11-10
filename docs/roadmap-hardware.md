# Hardware, after the display is up


The goal of `docs/roadmap-halium14.md` has been reached. On 2026-11-09 the user confirmed Ubuntu Touch had entered Lomiri, and that display, touch, GPU, brightness, charge detection, and vibration all work. This document only covers hardware that is not working yet. Do not reflash `vendor_boot`, `dtbo`, `vbmeta`, or `super`. `boot_b` is now the normal `boot-ut.img` (kernel `#9`, carrying the netd stub; a copy is at `out/halium14/boot-ut-data.img`, SHA256 `b72e43e1…`). The image to flash next is `4af37a0d…` (call audio at +20 dB, no droid card, media-hub, apndb, cleanup; see the end of item 5). It has no passwordless sudo, and it does not return to fastboot by itself. Anything that needs root has to be run by the user with `adb shell -t 'sudo …'`.

`/etc/os-release` is Ubuntu 24.04.5 LTS. The root filesystem comes from `ubuntu-touch-android9plus-rootfs-arm64.tar.gz` on the 24.04-2.x channel. adb is up, serial `stone`. Once mobile data was up on 2026-11-10, the phone clock went from 1970 to the correct time.

## Already confirmed working

- Display, touch (`fts_ts`), GPU acceleration, a smooth UI, and brightness control.
- Charging: `/sys/class/power_supply/battery/status` is `Charging`. The user confirmed the phone recognizes that it is charging.
- Vibration: `/sys/class/leds/vibrator` exists, and the user confirmed it works.
- adb.
- Speaker output (item 3).
- Wi-Fi (item 4).
- SIM, both IMEIs, mobile data (5G/NR), MMS, voice calls with audio in both directions (3G and IMS) (item 5).

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
- Correction from item 4: `CONFIG_CNSS_QCA6750=y` was wrong. This machine's WLAN is the Helium/Adrastea type on SNOC, not a QCA6750. That option is what made the firmware crash during probe in `#8`. It has been removed from the fragment.

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
- 2026-11-09: the user confirmed speaker sound works fully: key clicks, ringtone preview, and playback. The speaker part of this item is done. The earpiece, headphones, microphone, and call audio are still open.

## 4. Wi-Fi

Goal: scan, associate, and get an IP address.

What is seen: the user confirmed Wi-Fi is unavailable. There is no `wlan0`. On the Android side, `vendor.wifi_hal_legacy` and `wificond` are both running, and `wifi.interface` is `wlan0`. The driver is `qca_cld3_wlan.ko`, and it is not loaded.

### Planned steps

1. Wait for item 2 to produce `wlan0`.
2. Scan and connect to a known network, and confirm DHCP.
3. If association succeeds but web pages fail, first check whether the phone clock is still in 1970.

### Implementation notes

2026-11-09: kernel `#9` is built, and `boot-ut.img` has been packed. It has not been written to the phone yet.

`#8` had no `wlan0` because of a config option item 2 added by mistake. `CONFIG_CNSS_QCA6750=y` makes qcacld's `configs/default_defconfig` turn on `CONFIG_LITHIUM` and `ROME_IF = ipci`, which is the QCA6750 (11ax) path. This machine's WLAN is not a QCA6750. In the Android 14 dmesg captured on the host (`out/halium14/logs/`), both the stock kernel (`stock-kernel-dmesg.txt`) and our `#3` kernel (`halium-kernel-dmesg-3.txt`) use `hif_snoc_*`, which is the Helium/Adrastea SNOC path (`CONFIG_ICNSS2_HELIUM`, `PLD_SNOC_ICNSS_FLAG`). On Android 14, `#3` loaded the driver after "Wifi Turning On from UI", and `wlan0` associated (`connected to 34:98:b5:88:a8:a3`). That shows that without this option, the built-in driver, the firmware, and the vendor's cnss-daemon all work. With the IPCI path, `#8` crashed the firmware during probe (`PD service down ... FW crash`, `hif_wlan_enable` -110).

`CONFIG_CNSS_QCA6750=y` was removed from `kernel/config/halium-sunstone.fragment`. The fragment was not re-expanded. The option was turned off with `scripts/config --disable CNSS_QCA6750` on `#8`'s `.config`, followed by `olddefconfig`. Compared with `#8` (with comments excluded), the only `.config` difference is that one line. The build command, run in the kernel tree:

`PATH=/usr/lib/llvm-21/bin:third_party/toolchain/gcc-13.3.0-nolibc/aarch64-linux/bin:$PATH make O=kernel/build-14 ARCH=arm64 LLVM=1 CROSS_COMPILE=aarch64-linux- KCFLAGS=-Wno-implicit-enum-enum-cast Image modules`

Ubuntu only puts `clang` in `/usr/bin`, so `ld.lld`, `llvm-ar`, and `llvm-objcopy` come from `/usr/lib/llvm-21/bin`.

The rest of the path on Ubuntu Touch was checked in the current `#8` session, without root:

- Inside the container, `ueventd`, `cnss-daemon`, `android.hardware.wifi-service`, and `wificond` are all running.
- Firmware requests already go through the container's ueventd on UT (`adsp.mdt`, `ipa_fws.*`). The kernel has `FW_LOADER_USER_HELPER(_FALLBACK)=y`. `/vendor/firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini` points at `/vendor/etc/wifi/WCNSS_qcom_cfg.ini`, which exists. `wlan_mac.bin` points at `/mnt/vendor/persist`, which may not be mounted in the container. In that case the driver falls back to a MAC address it generates itself.
- `CFG80211`, `MAC80211`, and `RFKILL` are built in. Ubuntu's `wpa_supplicant` and `NetworkManager` are running. `10-globally-managed-devices.conf` keeps Wi-Fi devices managed. `nmcli radio` shows `WIFI enabled`, `WIFI-HW missing`. Nothing is soft-blocked in rfkill.
- `stone-wlan-on.service` stays as it is. After lxc it writes `ON` to `/dev/wlan`, up to 8 times, and waits for `wlan0`.

Kernel messages do not go to the journal (`_TRANSPORT=kernel` is empty), and the 256K ring buffer has wrapped after a few hours. After a boot, read `dmesg` (phablet can) soon, before it rolls over. Because the clock is in 1970, `journalctl -b` picks the wrong boot. Use `journalctl _BOOT_ID=$(cat /proc/sys/kernel/random/boot_id | tr -d -)` instead.

Products:

- `kernel/build-14/arch/arm64/boot/Image`, `#9 SMP PREEMPT Mon Nov 9 23:41:32 EST 2026`, 47999488 bytes, SHA256 `3a719ecdb983a41477a24b99fc471bbeba7c8d3286a7945c1181c02ed0910c31`. `System.map` has `hif_snoc_enable_bus` and `pld_snoc_register_driver`, and no `hif_ipci_*`, `pld_ipci_*`, or `hal_qca6750_attach`. `#8` is kept at `out/halium14/Image-8`.
- `out/halium14/boot-ut.img`, header v3, ramdisk 958566 bytes. Its kernel is byte-for-byte the `#9` Image. The ramdisk carries `hci_vhci.ko` (vermagic unchanged), `stone-wlan-on.service`, and the speaker overlay. SHA256 `beeb8e43a76bc11a0384fd801f374aba16787ca798a26ea6af95bb8220675b38`. The previous `#8` image is kept at `out/halium14/boot-ut-8.img` (`c32153db…`).

Manual test, after the user puts the phone into fastboot:

1. `fastboot flash boot_b out/halium14/boot-ut.img`. Leave `vendor_boot`, `dtbo`, `vbmeta`, `super`, and userdata alone.
2. `fastboot reboot`.
3. On the phone: the Wi-Fi toggle in Settings is available, nearby networks appear, and a known network connects and gets an address.
4. On the host: `adb shell 'ls /sys/class/net; dmesg | grep -iE "wlan|icnss|hif_" | tail -40; nmcli device; systemctl status stone-wlan-on.service'`.

If `wlan0` is still absent, read dmesg first. Do not reflash in a loop. To roll back, write `out/halium14/boot-ut-8.img` to `boot_b`.

### Events

- Read `dmesg` as phablet on `#8`. The ring buffer had wrapped, and no WLAN lines from boot were left. `stone-wlan-on.service` had failed: 8 `ON` writes, each an I/O error after about 25 seconds.
- Compared the host's Android 14 dmesg with the stock kernel and with `#3`. Both use SNOC, and `#3` associated on Android. The cause is `CONFIG_CNSS_QCA6750=y` from item 2.
- Removed the option and built `#9` incrementally. Confirmed that only the SNOC path is linked, then packed `boot-ut.img`. Nothing was flashed.
- The user wrote `beeb8e43…` to `boot_b`. After boot, `uname` was `#9`, and `wlan0`, `wlan1`, `p2p0`, and `wifi-aware0` all exist. NetworkManager shows `wlan0` connected. The user confirmed Wi-Fi works. Kept at `out/halium14/boot-ut-9-wifi.img`.

## 5. SIM

Goal: ofono can see a modem, and Settings can recognize the SIM.

What is seen: the user confirmed the SIM is not recognized at all. `ofono` is running, `GetAvailableModems` returns 0, and `GetErrors` is also 0. `rmnet_data0` through `rmnet_data5` and `rmnet_ipa0` already exist, so the data-interface path has at least been created. In the previous document `qcrilNrd` had a crash loop. This time adb logcat did not capture a new RIL line.

### Planned steps

1. Read logcat for `qcrilNrd` and `rild` inside the container, and ofono's journal. First separate "the baseband did not come up" from "ofono never tried to connect."
2. After a modem object exists, look at SIM state, signal, and the operator.
3. Call audio returns to the `audiosystem-passthrough-qti` left by item 3.

The user added to the goal: LTE (or NR) data and LTE calls should both work. The SIM is a Canadian Fizz card.

### Current status (2026-11-10)

| Item | Status |
| --- | --- |
| SIM, IMEI, operator | Working. ofono has `/ril_0` and `/ril_1`, and Settings can see both IMEIs. |
| Mobile data | Working. User confirmed 5G data. Measured on NR, Fizz 302/490: IPv4 ping and HTTPS work. |
| Voice calls | Working (user confirmed "voice calls work nicely"). On 3G (UMTS) the call connects. On 5G the status bar stays on 5G (IMS: VoLTE/VoNR). |
| IMS / VoLTE | IMS has registered (`Registered=true`, `VoiceCapable=true`, `SmsCapable=true`). Calls go out over IMS and connect. |
| Call audio | Working: earpiece downlink is clear, and the microphone uplink is clear (user confirmed). See "Call audio: what fixed it". |
| MMS | Working (user confirmed). The context has been changed to Fizz (`mobile.bm`, `http://mms.mobile.bm`, `mmsproxy.mobile.bm:80`). |

#### Why mobile data did not work, and the fix

It was not the APN, roaming, or the binder plugin. qcril's data module never initialized:

1. The vendor `netmgrd` (`ro.vendor.use_data_netmgrd=true`) waits after startup for `android.system.net.netd@1.1::INetd/default` (`V1_1::INetd::getService` plus `registerForNotifications`). The log stops at `NetmgrNetdClientInit(): Looking for Netd service`.
2. Halium runs no netd, and the Halium 14 system image has no netd stub. No netd service of any version exists on hwbinder or binder.
3. Until netmgrd is ready, DSI (`libdsi_netctrl`) cannot finish initializing. qcril initializes DSI only once, when it starts, so it never recovers. From then on, every `setupDataCall` gets `[CallManager]: DSI init not yet completed` inside qcril and is answered immediately with `respErr=4`, `cause=4100` (`OEM_DCFAILCAUSE_4`). It never reaches the modem. `imsd` gets stuck for the same reason (`dsi_get_data_srvc handle returned NULL`), so IMS cannot register either.
4. Side effect: `lomiri-indicator-network-service` retries immediately after every failure. That was over 10,000 times in one boot, and it stopped answering D-Bus, so Settings would not open and the Wi-Fi toggle did not take effect.

Fix: `stone-netd-stub.service` runs `usr/lib/stone/netd-stub.py` (python3-gbinder) and registers a stub INetd 1.1/1.0 on `/dev/hwbinder`. Every method returns a complete HIDL reply (transport status 0, then `StatusCode::OK`). `createOemNetwork` returns a handle of `(netId<<32)|0xfacade`. Routing and the firewall are still handled by NetworkManager. The stub has to register before qcril starts: `DefaultDependencies=no`, `After=lxc-android-config.service`, `Before=ofono.service`, `User=radio`. In practice it registers at 11.9 seconds, netmgrd calls `createOemNetwork` at 16.2 and 17.1 seconds (once per SIM), and qcril starts at about 15.3 seconds. Starting the stub after qcril is not enough (tested: netmgrd picked it up, but qcril stayed at `DSI init not yet completed`). Same idea as Halium/android_device_halium_halium_arm64 PR #39 and mer-hybris/dummy_netd.

Other configuration this depends on (in `boot/ut-init/rootfs-overlay/`):

- `etc/deviceinfo/devices/stone.yaml`: `OfonoPlugin: binder`, so `ofonod-wrapper` loads `ofono-binder-plugin` instead of the socket RIL plugin.
- `etc/ofono/binder.conf`: `ExpectSlots = slot1,slot2`. Each slot needs a `path` (`/ril_0`, `/ril_1`) and a unique `slot` (0, 1), or ofono silently drops the slot. Use `radioInterface = 1.5`, because the default 1.2 removes NR.
- `etc/ofono/binder.d/qti.conf`: `extPlugin = qti` (IMS registration, VoLTE calls, SMS over IMS).
- `etc/ofono/ril_subscription.d/stone.conf`: slots for `audiosystem-passthrough-qti` only.
- APN: ofono's apndb plugin does not match `mvno_type=gid` and picked Vidéotron's `media.ng` for this Fizz SIM. The internet context `/ril_0/context1` was changed by hand over D-Bus to `Name=Fizz`, `AccessPointName=mobile.bm`, `Protocol=dual`. ofono saves this per IMSI, so it survives a reboot, but a new SIM or a reflashed userdata needs it set again. `media.ng` was not what caused the 4100; it is simply the wrong APN for Fizz.

Measured result (capture in `out/halium14/logs/mobile-data-ok/`, gitignored): in the whole boot, `setupDataCall_1_5` was sent once and succeeded (`status=0, cid=0, ifname=rmnet_data1`). NetworkManager had 0 `Activation: failed`. `rmnet_data1` is `10.116.33.97/30` with a default route through `10.116.33.98`. `ping 1.1.1.1` had 0% loss, 44 to 72 ms. DNS through NM's dnsmasq works. `https://ubuntu.com` returned 200 in 0.87 seconds. Registration was `registered`, `nr`, 302/490 "Fizz" (not roaming). The IMS PDN was brought up by the modem/imsd on `rmnet_data2` (a public IPv6 /64). The network indicator's CPU was 0 over 5 seconds and D-Bus answered in 30 ms. `vendor.dataqti` (`/vendor/bin/qti`) stopped crash-looping (pid stable). The phone clock is now correct (2026-11-10).

#### Still open for mobile data

- IPv6 on the internet PDN: `Protocol=dual` was requested (qcril received `IPV4V6`), but ofono's data call response is `type=0` (IP), so the network only granted IPv4 for `mobile.bm`. This is the carrier's choice, not a local configuration problem. The IMS PDN has IPv6.
- MMS: `/ril_0/context2` has been changed to `Name=Fizz MMS`, `AccessPointName=mobile.bm`, `MessageCenter=http://mms.mobile.bm`, `MessageProxy=mmsproxy.mobile.bm:80` (saved per IMSI). The internet and MMS APNs are the same, which is what UBports ofono-sailfish #8 says can fail, but here the user confirmed MMS works.
- apndb: `tools/apndb-prefer-mvno.py` is called from `build-boot-image.sh`. It takes the rootfs `lineageos-apndb/apns-conf.xml`, keeps only the Fizz entries for 302/500 (`mvno_type=gid`, `mvno_match_data=55`, with those two attributes removed), and drops Vidéotron's four 302/500 entries. The output is written to `/usr/share/stone/apns-conf.xml` (generated, not committed). `ofono.service.d/zz-stone-apndb.conf` sets `OFONO_SYSTEM_APNDB_PATH` to it. This only affects a SIM that has no saved contexts yet. The side effect is that a real Vidéotron SIM would get Fizz's APN.
- When data fails, the indicator's immediate-retry loop still freezes Settings. That is a bug in the indicator itself. Now that data works it does not trigger, but it will come back if data breaks again.
- Only SIM 1 has been tested. Slot 2 is empty.

#### Call audio: what fixed it

The Android audio HAL cannot be used here (PulseAudio can only load the 64-bit stub `audio.primary.default.so`, item 3), so nothing starts the ADSP voice session. `stone-call-audio.service` (a user unit, enabled through `pulseaudio.service.wants`) runs `usr/lib/stone/call-audio-watch.sh`. It polls ofono's `VoiceCallManager.GetCalls` every 0.5 seconds and, while a call is `dialing`/`alerting`/`active`/`held`, runs `call-audio.sh on`:

1. Mixer, following `mixer_paths_qrdsku1.xml`: earpiece `handset` + `RX_CDC_DMA_RX_0_Voice Mixer VoiceMMode1`. With `~/.config/stone/call-route` set to `speaker`, it uses the existing `speaker-route.sh` chain + `RX_CDC_DMA_RX_1_Voice Mixer VoiceMMode1`.
2. Microphone: by default a single mic, mono (`amic1`, SWR_MIC0/ADC1 -> DEC0; the speaker route uses `amic3`, SWR_MIC4), `TX_CDC_DMA_TX_3 Channels=One`, `VoiceMMode1_Tx Mixer TX_CDC_DMA_TX_3_MMode1`. Without ACDB the voice uses `VSS_IVOCPROC_TOPOLOGY_ID_NONE`. With the two channels of the vendor's `handset-mic` the far end could hear nothing at all.
3. Uplink gain: `TX_DEC0`/`1`/`2 Volume` is set to 84+20 (1 dB/step, 84 = 0 dB) and set back to 84 when the call ends. ACDB normally supplies this gain. Without it, the far end heard speech "drop several times a second" (the vocoder's VAD/DTX dropped the quieter speech). It can be tuned in dB through `~/.config/stone/call-mic-gain` (0 to 40). The in-call recordings through `VOC_REC_UL`, 8 kHz mono, 10 ms windows:

   | Gain | Peak | Clipping | Active speech | Far end |
   | --- | --- | --- | --- | --- |
   | +0 dB | -23.7 dBFS | 0 | -44.8 dBFS | choppy |
   | +14 dB | -14.3 dBFS | 0 | -32.3 dBFS | good once, choppy once |
   | +20 dB (default) | -10.3 dBFS | 0 | -31.1 dBFS | clear |

   "Active speech" is the RMS of the windows more than 4 times above the noise floor (p10). The +20 call also had no PulseAudio crash (the droid card was removed), so the two changes cannot be fully separated. +20 still leaves about 10 dB of headroom.
4. `voice-pcm-hold.py` opens VoiceMMode1 (`hw:0,2`) in both directions, sets parameters, `snd_pcm_start`, and **never reads or writes**. This front end is hostless (`msm-pcm-voice-v2` has no `.copy`/`.pointer` and no DMA buffer). When aplay wrote to it, ALSA copied into a NULL `dma_area`, the kernel oopsed, and `panic_on_oops=1` reset the phone immediately (this happened twice). Once both directions are prepared, the kernel calls `voc_start_voice_call()` for the VoiceMMode1 session (vsid 0x11C05000, which qcril also reports for 3G calls).
5. `ctl-write.py` writes `{0, 0xFFFFFFFF, 20}` to `Voice Tx Mute`, `Voice Tx Device Mute`, and `Voice Rx Device Mute` (the equivalent of the HAL's `voice_set_mic_mute()`). These are write-only array controls that `amixer cset` cannot write.

When the call ends, `call-audio.sh off` stops the holder and clears the mixer and gain. The kernel logs `voice_get_cal: No cal data`, `ADSP_EBADPARAM` (dev cfg), and `voice volume failed` on every call. These are normal without ACDB and do not affect sound.

Known limitations:

- No ACDB calibration: no echo cancellation or noise suppression (fluence/ECNS) and no dual-mic processing. Over the earpiece the far end said it sounded fine. With speakerphone the far end may hear an echo.
- The speaker button in the Phone app does not switch the route. The route is only decided at call start from `~/.config/stone/call-route`. Wired headsets and Bluetooth calls are not handled.
- Downlink volume is fixed: the call volume keys do not change `Voice Rx Gain`.
- The fallback, if calibration is ever required: the vendor audio HAL is running in the container as `android.hardware.audio@7.0::IDevicesFactory/default` and could be driven over HIDL (`setMode(IN_CALL)` and so on), with ACDB. `module-droid-hidl` is only the AudioSystem passthrough and cannot serve as that client.

#### Debug tools

`tools/phone-debug/` (none of them go into the boot image; push them to the phone when needed):

- `stone-klog.py`: phablet cannot open `/dev/kmsg`. It polls `klogctl(READ_ALL)` every 100 ms and fsyncs, so the kernel log from right before a hard reset survives. **Writes about 10 MB an hour; stop it when done.**
- `mic-test.sh amic1|amic3|handset-mic`: records 2 seconds of microphone through MultiMedia1 and prints the level.
- `stone-radio-debug.sh` (sudo): turns on `persist.vendor.radio.adb_log_on` and restarts qcril (ofono pauses data for about 3 minutes afterwards), then captures 90 seconds. `stone-radio-debug.sh off` turns it back off (effective at the next boot).
- `stone-capture.sh` (sudo): copies pstore, the radio/main/system/crash logcat buffers, and dmesg.
- `call-audio.sh` debug subcommands: `mixer`, `mixer-off`, `pcm-rx`, `pcm-tx`, `pcm-off`, `unmute`, `rec-ul [seconds] [file]` (in-call uplink recording, `MultiMedia9 <- VOC_REC_UL`, `hw:0,23`). Setting `STONE_CALL_REC_UL=1` on the watcher records 8 seconds automatically on every call.

### Implementation notes

2026-11-10: the overlay is ready, and `boot-ut.img` has been packed. It has not been written to the phone yet.

The baseband is not the problem. In the `#9` session the following are all running: the modem subsystem, `pd-mapper`, `rmt_storage`, `tftp_server`, `netmgrd`, `imsdaemon`, `ims_rtp_daemon`, and two `qcrilNrd` instances (`persist.radio.multisim.config=dsds`). `ril.mcc.mnc0` is `302500`, which means qcril has already read the Fizz SIM (Vidéotron network). ofono simply never connected to qcril:

- `ofono.service` uses `lxc-android-config`'s `ofonod-wrapper`. It only loads `ofono-binder-plugin` when `device-info get OfonoPlugin` is `binder`. Otherwise it loads the socket RIL plugin, and `/etc/ofono/ril_subscription.conf` points at `/dev/socket/rild`, which does not exist on Android 14. `device-info` reports `Detected name: stone` (from `ro.product.device`), but `/etc/deviceinfo/devices/stone.yaml` does not exist, so the result is `Unknown prop`.
- The vendor manifest has HIDL `android.hardware.radio@1.5::IRadio/slot1,slot2`, `radio.config@1.1::IRadioConfig/default`, and `vendor.qti.hardware.radio.ims@1.7::IImsRadio/imsradio0,1`. Listing hwservicemanager as phablet with `python3-gbinder` showed every version from 1.0 to 1.5/1.7 registered, along with `vendor.qti.hardware.radio.am@1.0::IQcRilAudio/slot1,2`.
- The installed `ofono-binder-plugin` 1.1.33 defaults to `radioInterface` 1.2. Below 1.4, `binder_plugin.c` removes NR from the slot's technologies. `ofono-binder-plugin-ext-qti` registers itself as `qti`, but the package does not install the `binder.d/qti.conf` that enables it. That extension connects to `IImsRadio@1.2/imsradio<slot index>` and provides IMS registration, VoLTE calls, and SMS.
- In the source, `ofono_conf_merge_files()` merges `binder.conf` with `binder.d/*.conf`, and `ofono_conf_get_string()` falls back from `[slotN]` to `[Settings]`, so an `extPlugin` in `[Settings]` applies to both slots.
- The default identity is `radio:radio`. On UT, `radio` is uid/gid 1001. `/dev/binderfs/hwbinder` is 0666. `/etc/dbus-1/system.d/ofono.conf` allows `radio` to own `org.ofono`.
- In the LineageOS apndb that `ofonod-wrapper` uses, 302/500 has Fizz `mobile.bm` (default/mms/supl) and `ims` (IPv6), both matched by GID 55, plus the Vidéotron `media.ng`/`ims` entries.

`audiosystem-passthrough-qti` (exit status 2) gets its slots from `[ril_N] transport=binder:name=<slot>` in `/etc/ofono/ril_subscription.conf` and `ril_subscription.d/*.conf` (mer-hybris `src/impl-qti.c`). The default file only has `socket=`, so the client list is empty and it exits. This is unrelated to PulseAudio.

New overlay files, in `boot/ut-init/rootfs-overlay/`:

- `etc/deviceinfo/devices/stone.yaml`: `OfonoPlugin: binder`. Tested as phablet with `DEVICEINFO_DEVICE_PATH` pointing at a copy: `device-info get OfonoPlugin` returned `binder`, and `GridUnit` was still 21.
- `etc/ofono/binder.conf`: `ExpectSlots = slot1,slot2`, with `radioInterface = 1.5` for both slots.
- `etc/ofono/binder.d/qti.conf`: `extPlugin = qti`.
- `etc/ofono/ril_subscription.d/stone.conf`: `[ril_0] transport = binder:name=slot1` and `[ril_1] ... slot2`, only for audiosystem-passthrough. The socket RIL plugin is disabled, so ofono does not read it.

`out/halium14/boot-ut.img`: kernel unchanged, byte-for-byte the `#9` Image. The ramdisk adds the four files above. SHA256 `a9122c29ea6bad4d5826c768c3f4a7390bf2d69a2bd2240d257fbcbb0459d2ba` (stale; see the Events below. The current one is `610a4bc6…`). The Wi-Fi image before this change is `out/halium14/boot-ut-9-wifi.img` (`beeb8e43…`).

Call audio is not done. audiosystem-passthrough forwards qcril's `setParameters` through PulseAudio to the droid HAL. The HAL that can be loaded here is still the 64-bit empty `audio.primary.default.so` from item 3, so the passthrough alone produces no call audio. The ALSA side already has `VoiceMMode1` (`hw:0,2`, hostless playback and capture). `mixer_paths_qrdsku1.xml` has `voicemmode1-call`, `handset`, `voice-speaker`, and `handset-mic`. That has to be set up and tested during a live call.

Manual test, after the user puts the phone into fastboot:

1. `fastboot flash boot_b out/halium14/boot-ut.img`. Do not touch any other partition. `fastboot reboot`.
2. After unlocking, look at the status bar and at Settings → Cellular: whether the SIM is detected, the operator (Fizz / Vidéotron), and the network type (4G/5G).
3. Turn Wi-Fi off and open a web page, to test mobile data.
4. Place a call to a number you can answer, and see whether it rings and connects. Whether there is sound is not part of this pass. Report it as it is.
5. Host side, quickly: `adb shell 'device-info get OfonoPlugin; /usr/share/ofono/scripts/list-modems; systemctl --user status audiosystem-passthrough-qti'`.

If there is no modem, read ofono's journal first. Do not reflash in a loop. To roll back, write `out/halium14/boot-ut-9-wifi.img`.

### Events

- Separated the two cases: qcril is running and has read the SIM (`ril.mcc.mnc0=302500`). ofono loaded the socket RIL plugin and waited for a `/dev/socket/rild` that does not exist.
- Confirmed the HIDL radio and IMS services are registered on hwbinder.
- Added the device-info, binder plugin, QTI extension, and passthrough slot configuration, and packed `boot-ut.img`. Nothing was flashed.
- The user wrote `a9122c29…`. No SIM was detected, and "show IMEI" was missing from Settings. On the phone: `device-info get OfonoPlugin` was `binder`, ofonod ran as `radio` with `-P ...,ril`, and the binder plugin initialized. `audiosystem-passthrough` now stays running. But `list-modems` was empty. The ofono journal had `Missing path for slot slot1` and `slot2`. In `binder_plugin_create_slot()`, the `path` key is required for every slot, whether it is auto-discovered or listed in `ExpectSlots`. Without it the function returns NULL and the slot is not created. The previous `binder.conf` had only `radioInterface` in each `[slotN]`. This was missed in the previous round.
- `binder.conf` now gives `[slot1]` `path = /ril_0`, `slot = 0`, and `[slot2]` `path = /ril_1`, `slot = 1`. The slot number defaults to 0, and two zeros would fail the `Duplicate slot` check. The QTI extension also uses this number to pick `imsradio<N>`. `/ril_0` is the modem path UT's telepathy-ofono expects.
- Temporarily added `etc/systemd/system/ofono.service.d/zz-stone-debug.conf`, which passes `-d *binder*:*qti*:*sim*:*netreg*:*ims*` to `ofonod-wrapper` (ofono's `-d` splits on `:` and matches source file names). There is no root for live debugging, so if this boot still has no modem, the journal shows which step slot creation, the IRadio connection, or SIM status reached. Remove it once the modem works.
- The new `boot-ut.img` SHA256 is `610a4bc6e222e30debf0169a0033dad6a63c9ec042b37e40450034cbbd5dc8d5`. The kernel is still `#9`. Not yet written. The manual test steps are the same as above.
- The user wrote `610a4bc6…`. The status bar showed a 5G signal. ofono has `/ril_0` and `/ril_1`, and the IMSI is `redacted`. Then Settings would not open (it started, hung, and was closed about 25 seconds later; after a reboot it opened once with no cellular section), and turning Wi-Fi off in the control center did not take effect. Cause: `lomiri-indicator-network-service` was stuck in a loop. It kept asking NetworkManager to activate the gsm connection on `ril_0`. NM asked ofono to activate `/ril_0/context1`, `setupDataCall_1_5` returned `status=4100` (`OEM_DCFAILCAUSE_4`, a Qualcomm vendor cause) right away, and the indicator immediately retried. That was about 12 times per second, over 10,000 times in one boot, with NM's active connection IDs reaching 7000+. The indicator was so busy processing NM signals that it stopped answering D-Bus (a `NetworkingStatus` query timed out after 5 seconds). Both the Settings network pages and the Wi-Fi toggle depend on it.
- The contexts the apndb provisioned were Vidéotron's (`media.ng`). ofono's apndb plugin does not match on `mvno_type=gid`. According to the apndb and Fizz's own help pages, the Fizz APN is `mobile.bm` (MMSC `http://mms.mobile.bm`, proxy `mmsproxy.mobile.bm:80`). Through phablet's D-Bus policy (`ofono-phablet.conf`), `/ril_0/context1` was changed to `Name=Fizz`, `AccessPointName=mobile.bm`, `Protocol=dual`. ofono saves this per IMSI. It still returned 4100, so this is not the network rejecting the APN name or the IP family.
- logd only shows phablet's own logs, so qcril's radio log cannot be read without root. Neither the Sailfish/UBports discussions nor the AOSP documentation give a definition for 4100. Compared with Android's `setupDataCall`, the plugin's `DataProfileInfo` 1.5 has `profileId=INVALID`, `type=COMMON`, `bearerBitmap`/`mtu` 0, and `persistent`/`preferred` false (Android: profileId 0, 3GPP). Which field qcril rejects can only be decided from its log.
- Temporary unblock: setting `ConnectionManager.Powered=false` stopped it for a moment, but after the indicator restarted, `SetDefaultDataSim` turned data back on and the loop resumed. As long as setup keeps failing, the indicator cannot stop by itself. `systemctl --user mask --runtime lomiri-indicator-network.service`, then stopping it and sending SIGKILL. The runtime mask is lost on reboot. After that, `setupDataCall` stayed at 0 for 15 seconds, and `ril_0` stayed `disconnected`. The cost is that there is no network indicator in the status bar until reboot.
- The user confirmed that before the reboot Settings could see both IMEIs, the Phone app could see the Fizz network, calls could not be made, and the browser could not open pages. After the reboot the indicator loop came back, and Settings hung again. The user's `sudo logcat -b radio -d` actually succeeded and saved `~/radio.txt` (246 lines), but `persist.vendor.radio.adb_log_on=0`, so qcril only logged startup messages (including `qcril_data_get_dds_sub_info: DSD Client unavailable`). There were no data call details.
- Registration state: `NetworkRegistration` is `Status=roaming`, `Technology=hspa`, MCC/MNC `302/610` (Bell), `Name=Fizz EXT`. In ofono, `ConnectionManager.RoamingAllowed=true`. The plugin's `setupDataCall_1_5` always sends `roamingAllowed=TRUE`. HIDL IRadio has no separate `setDataRoamingEnabled`, so it is not a roaming switch that was never set. IMS `Registered=false`, `VoiceCapable=false`.
- Phone call: `binder_voicecall_dial()` reached qcril, `dialResponse` returned, and the call stayed at `status=2` (DIALING) for 18.6 seconds until the user hung up. It never went to ALERTING/ACTIVE, and ofono received no call state change in between.
- `vendor.dataqti` (`/vendor/bin/qti`, QTI USB tethering/RmNet bridge) is in a restart loop, with a new pid every 5 to 10 seconds. `vendor.qcrild`/`qcrild2` are `/vendor/bin/hw/qcrilNrd`, and they are not restarting. `qti` most likely conflicts with usb-moded over the USB gadget. It is not on the phone data path. It is recorded here for later.
- Prepared `~/stone-radio-debug.sh` (source in the scratchpad, not in the repository): run once with sudo. It sets `persist.vendor.radio.adb_log_on=1`, clears logcat, restarts `vendor.qcrild`/`qcrild2` with `ctl.restart` (ofono reconnects by itself), waits 90 seconds for the user to place a call while data keeps retrying on its own, and then writes radio/main/system/crash to `~/radio-debug.txt`. The persist property stays on until the cause is found.
- The user ran `stone-radio-debug.sh`, which saved 11078 lines. This time the call connected (3G, UMTS), but there was no sound in either direction. The qcril log has `QcRilUnsolAudioStateChangedMessage{vsid=297816064;call_state=2;call_type=UMTS}` (vsid 0x11C05000 = VoiceMMode1), but `sendUnsolAudioStateChanged: ind null: true`. Nobody receives qcril's audio state, and nobody starts the voice path. The call ended with `call failure cause 145`, and `getLastCallFailCause` returned 16 (normal clearing).
- The capture had no data calls in it. After `ctl.restart` of qcril, ofono's `setupDataCall` stopped for about 3 minutes (uptime minutes 13 to 16), exactly covering the 90 seconds of capture. Also seen: `binder_radio_power_on/off()` toggles slot1 every 100 ms or so. Earlier, "Unexpected data call failure" was followed by `binder_radio_power_off`. It belongs to the same failure loop.
- The user added: when this phone ran Android, VoLTE needed PixelIMS (a carrier-config override) before the VoLTE switch appeared. In other words the network and modem support IMS, and it is the carrier config that hides it. Right now it is 3G roaming (Bell), so IMS cannot register anyway. Look at this again once LTE data works.
- Call audio: following `voicemmode1-call[ handset]`, `handset`, `handset-mic`, and `speaker-mic` in `mixer_paths_qrdsku1.xml`, wrote `usr/lib/stone/call-audio.sh` (`on earpiece|speaker`/`off`: set the mixer, then hold `hw:0,2` open in both directions with `aplay`/`arecord`), `call-audio-watch.sh` (polls ofono `GetCalls` every 0.5 seconds, turns it on for dialing/alerting/active/held and off otherwise), and the user unit `etc/systemd/user/stone-call-audio.service`. All the controls exist, and phablet can access `pcmC0D2p/c` (group audio).
- The first dry run of `call-audio.sh on earpiece` with no call in progress rebooted the whole phone. USB dropped, it came back after 45 seconds with uptime 56 seconds, and `powerup.reason` changed from `0x40041` to `0x40141`. Opening the VoiceMMode1 PCM while the modem has no voice session is very likely an ADSP failure that escalated to a system reset. That only happens when this is run outside a call. The Android HAL also only opens it during a call. The `pulseaudio.service.wants` symlink was removed, so the unit is not enabled for now. Until pstore shows the cause, do not run it again with no call.
- Prepared `~/stone-capture.sh` (run once with sudo): copies `/sys/fs/pstore` (the kernel log from the reset), the radio/main/system/crash logcat buffers, and dmesg to `~/stone-capture/`. `adb_log_on` stayed 1 after the reboot, and ofono had already made 323 `setupDataCall` attempts in this boot, so this time the radio buffer should contain qcril's handling of the data call.
- The user ran `stone-capture.sh` (`~/stone-capture/`, 14700 lines of radio). pstore was empty, so the kernel log from the reset is gone. qcril's verdict on the data call: `[DataModule]: Handling msg = SetupDataCallRequestMessage Params=[3,-1,mobile.bm,IPV4V6,IPV4V6,...]`, then immediately `[CallManager]: DSI init not yet completed`, then `setupDataCallResponse resp=respErr=4 cid=-1{4100,...}`. That happened 406 times and never reached the modem. `imsd` hit the same thing (`dsi_get_data_srvc handle returned NULL so wait for dsi_init_cb`).
- The DSI holdup comes from `netmgrd` (`ro.vendor.use_data_netmgrd=true`). After starting it only logged `NetmgrNetdClientInit(): Looking for Netd service` / `registerServerNotification(): Successfully registered for Netd HAL service`, and then stopped there. Its symbols contain `V1_1::INetd::getService` and `registerForNotifications`, and it calls `createOemNetwork`, `addInterfaceToOemNetwork`, `addRouteToOemNetwork`, `setIpForwardEnable`, and `setForwardingBetweenInterfaces`. Neither hwbinder nor binder has any netd service, and the Halium 14 system image has no netd stub. Halium/android_device_halium_halium_arm64 PR #39 describes the same thing: Halium has no netd, and vendor data daemons get stuck waiting for INetd. The old HIDL stub was `android.system.net.netd@1.1-service.stub`, and mer-hybris/dummy_netd is the libgbinder version.
- Added `usr/lib/stone/netd-stub.py` (python3-gbinder, already installed): registers `android.system.net.netd@1.1::INetd/default` on `/dev/hwbinder` (interface chain 1.1, 1.0). Every method returns a complete HIDL reply (transport status 0, then the return values). `createOemNetwork` returns a handle in the form `(netId<<32)|0xfacade` and a mark of `netId|0x30000`. dummy_netd returns an empty reply, which a HIDL client would read as a transport error. Started temporarily as a phablet user unit: registration succeeded, and netmgrd immediately called `createOemNetwork` twice (netId 100/101, one per SIM). But qcril still returned `DSI init not yet completed`: DSI initialization happens once when qcril starts, and netmgrd was not ready at that point, so the stub has to be there before qcril starts.
- Added `etc/systemd/system/stone-netd-stub.service` (`multi-user.target.wants`): `DefaultDependencies=no`, `After=local-fs.target lxc-android-config.service`, `Before=ofono.service`, `User=radio`. `lxc-android-config` is marked started at about 11.8 seconds. From the container's `ro.boottime`, netmgrd is at about 14.6 seconds and qcril at about 15.3 seconds, so the stub registers before both. `stone-call-audio.service` is still not enabled.
- New `boot-ut.img` SHA256 `b72e43e134eecbefca6c40a024e51336b369405fb32f1226162b64cb60a7e21d`, still kernel `#9`. Not yet written.
- 2026-11-10: the user wrote `b72e43e1…` and confirmed 5G mobile data works. Measured results are in "Current status" at the start of this item. IMS has registered. Kept at `out/halium14/boot-ut-data.img`.
- The user started `stone-call-audio` (the version in the rootfs, which still used aplay/arecord) and placed a call. The status bar stayed on 5G (VoNR/VoLTE). The other phone rang, there was no sound, and then the phone rebooted. The persistent journal ends at 440.35 seconds (the watcher had just started), and the "call audio: off -> earpiece" line was never written. journald syncs only every few minutes, so the whole call was lost.
- Not a DSP crash: `adsp`, `modem`, and every other subsystem have `restart_level=RELATED`, so an ADSP fault would only restart the ADSP. `panic_on_oops=1`, `panic=5`. ramoops is configured (`ramoops@0xd0000000`, `CONFIG_PSTORE_RAM=y`), but pstore was empty after both resets.
- Added a kernel log recorder (`~/.config/stone/stone-klog.py`, in the scratchpad, not in the repository): phablet cannot open `/dev/kmsg`, so `dmesg -w` does not work. It polls `klogctl(SYSLOG_ACTION_READ_ALL)` every 100 ms and fsyncs each line, with step markers in between. It runs as a user transient unit.
- Step by step, with no call in progress: applying only the mixer (earpiece plus mic) was fine. Mixer plus `aplay -D hw:0,2` (playback only) reset the phone, and the log stops at "aplay started" with no messages at all. In `msm-pcm-voice-v2.c`, `msm_pcm_ops` has no `.copy`/`.pointer`, there is no preallocated buffer, and `hw_params` only sets `snd_pcm_set_runtime_buffer(substream, &substream->dma_buffer)`. This is a hostless front end. When aplay writes, ALSA copies into a NULL `dma_area`, the kernel oopses, and `panic_on_oops` resets it. A playback-only `prepare` does not call `voc_start_voice_call` at all (that needs both directions), which rules out the DSP. The Android HAL only does tinyalsa `pcm_open`/`pcm_start` on this PCM and never writes data.
- Added `usr/lib/stone/voice-pcm-hold.py` (ctypes plus libasound): opens `hw:0,2` playback and capture, S16_LE, 8 kHz, mono, 40 ms. `stop_threshold` is set to boundary and `start_threshold` to 1, then `snd_pcm_start`. It never reads or writes, and closes on SIGTERM. `call-audio.sh` now uses it for `pcm_on` (plus debug subcommands `mixer`, `mixer-off`, `pcm-rx`, `pcm-tx`, `pcm-off`). Repeating the same playback-only step with it: no crash. Both directions with no call: no crash. The kernel log shows `voc_start_voice_call` going all the way through CVS/CVP setup, but `voice_get_cal: No cal data for cal 5/6/8`, `voice_send_cvp_register_dev_cfg_cmd: ADSP_EBADPARAM`, and `voice_send_vol_step_cmd: ADSP_EFAILED`. There is no ACDB calibration (the Android HAL loads it through libacdbloader). Speaker playback shows the same "no cal" messages but still produces sound. Whether voice can be heard without calibration has to be tested with a real call.
- For testing, `call-audio-watch.sh` is running from the copy in the home directory as user transient unit `stone-call-audio-test` (`STONE_CALL_AUDIO=~/.config/stone/call-audio.sh`). It is lost on reboot. **The `/usr/lib/stone/call-audio.sh` in the current `boot_b` image is still the aplay version, so do not `systemctl --user start stone-call-audio`.**
- New `boot-ut.img` SHA256 `64a59fa4d54ee5f4ea4e178303b1639f462a8a30ffc9f30731a380f5688da4ca` (kernel `#9`, plus `voice-pcm-hold.py`, the fixed `call-audio.sh`, and the generated apndb with its drop-in). `stone-call-audio.service` is still not enabled. Not yet written.
- The user placed a call with `stone-call-audio-test`: no crash, the earpiece can hear the other side, but the other side cannot hear this phone. MMS sending and receiving work. In the call's kernel log, AFE `0xb030` (RX_CDC_DMA_RX_0) and `0xb037` (TX_CDC_DMA_TX_3) both start and stop with the call, and `voc_start_voice_call` gets the same no-cal errors as before.
- Microphone hardware is fine: with no call, recording 2 seconds each from `amic1` (SWR_MIC0/ADC1), `amic3` (SWR_MIC4/ADC2 INP3), and the two-channel `handset-mic` through MultiMedia1 (`hw:0,0`, `MultiMedia1 Mixer TX_CDC_DMA_TX_3`) gives RMS 50/78/45+72 and peaks 218 to 337, which is room noise, not digital silence. So the problem is inside the voice uplink.
- In q6voice, `default_mute_val = 0` (unmuted by default). Without calibration, `voice_get_topology()` falls back to `VSS_IVOCPROC_TOPOLOGY_ID_NONE` (passthrough). But the uplink was getting the two channels of `handset-mic` (`TX_CDC_DMA_TX_3 Channels=Two`). Android only uses dual-mic routing together with the dual-mic calibration in ACDB.
- `call-audio.sh` now defaults to a mono mic: earpiece uses `amic1` (DEC0 <- SWR_MIC0, `Channels=One`), speaker uses `amic3` (SWR_MIC4). Setting `~/.config/stone/call-mic` to `dual` switches back to two mics. After the PCM starts, it sends the HAL's `voice_set_mic_mute()` equivalent, writing `{0, 0xFFFFFFFF, 20}` to `Voice Tx Mute`, `Voice Tx Device Mute`, and `Voice Rx Device Mute`. These are write-only multi-value controls that `amixer cset` cannot write because it reads first ("Cannot read the given element"), so added `usr/lib/stone/ctl-write.py` (libasound `snd_ctl_elem_write`). A full dry run with no call (`on earpiece`, mono): no crash.
- Added debug stage `call-audio.sh rec-ul`: in-call recording of the uplink (`MultiMedia9 Mixer VOC_REC_UL`, `hw:0,23`, a normal capture FE). With `STONE_CALL_REC_UL=1`, the watcher records 8 seconds after the call becomes `active` to `$XDG_RUNTIME_DIR/stone-uplink-*.raw` and prints the RMS. That tells "the DSP never received the mic" apart from "the DSP sent it but the far end cannot hear it". `ofono-binder-plugin` 1.1.33 already provides IMS calls, and the vendor audio HAL is running as `android.hardware.audio@7.0::IDevicesFactory/default` inside the container (with ACDB). If ACDB calibration turns out to be required, the fallback is to drive that HAL over HIDL. `module-droid-hidl` is only the AudioSystem passthrough and cannot serve as a HAL client.
- Call with mono mic plus unmute: the other side can hear and understand, but it "drops several times a second, like a poor Bluetooth connection". This phone hears the other side clearly. The 8-second uplink recorded through `VOC_REC_UL` (what the DSP sends to the modem) has no exact-zero gaps. It is continuous speech plus pauses, but the level is low: speech peaks around 2145 (about -24 dBFS), the 10 ms window RMS is p50 8.3 and p90 211, and pauses are around RMS 3. The earlier room-noise recording through the plain recording path was RMS 50. Most likely the vocoder's VAD/DTX treats the softer parts of this low-level speech as silence and drops them. On Android, uplink gain comes from ACDB, and the passthrough topology has none.
- Gain controls: `TX_DECn Volume` (bolero tx-macro) is 1 dB per step with 84 = 0 dB and a maximum of 124 (+40 dB). `ADCn Volume` (wcd937x `analog_gain`, `DECLARE_TLV_DB_SCALE(0, 25, 1)`) is only 0.25 dB per step, so 0 to 20 covers only 0 to 5 dB. Measured on room noise: going from `TX_DEC0 Volume` 84 to 98 took RMS from 52.6 to 224.1 (+12.6 dB, nominal +14).
- `call-audio.sh` now sets `TX_DEC0`/`1`/`2 Volume` to 84+14 (configurable in dB through `~/.config/stone/call-mic-gain`, 0 to 40) when the call starts, and back to 84 when it ends. Verified on the phone: 98 during a call, 84 after hang-up. The watcher still has `STONE_CALL_REC_UL=1`, so the next call records the uplink again for comparison.
- The user confirmed "voice calls work nicely". Defaults were used (no `call-mic`/`call-mic-gain`/`call-route` files). Uplink RMS 554, peak 6326 (previous call 124/2145).
- Cleanup (2026-11-10). All of the following is commit `b9d199d` plus this round:
  - Stopped `stone-klog` (it had already written 11.6 MB, with an fsync every 100 ms). The logs, uplink recordings, and `stone-capture/` were moved to `out/halium14/logs/call-audio-debug/` (gitignored), and deleted from the phone's home directory along with `stone-*.sh`.
  - The whole of `~/.config/stone` and `~/.config/systemd/user` was backed up to `out/halium14/logs/phone-home-backup-2026-11-10/`. Then the unreferenced experiment leftovers from item 3 were deleted (`libaa-peer.so`, `libbt.so`, `preload.txt`, `pulse-ns.sh`, `bt.txt`, `pulse.log`, `click.wav`, `tone.wav`).
  - PulseAudio had been running all along from phablet's own `~/.config/systemd/user/pulseaudio.service.d/zz-stone-audio.conf` and `~/.config/stone/touch.pa`, which overrode the overlay. A diff showed the content was the same as the overlay's `/etc/pulse/stone-touch.pa` and `/usr/share/stone/*.xml` apart from paths and comments. Deleted the home drop-in and copies. After restarting, `PULSE_SCRIPT=/etc/pulse/stone-touch.pa`, the default sink was still `sink.speaker`, and the sinks were unchanged.
  - The media-hub fix from item 3 existed only in the home directory (a patched `media-hub-server` plus a user drop-in), so a reflashed userdata would have lost it. The whole patch is 66 bytes at `0x33ed4` (an empty label is replaced with the static UTF-16 `"unconfined"`). `tools/patch-media-hub.py` checks the input SHA256 (`fa86280b…`, media-hub 4.7~20260611100903.31~3b69471) and the output SHA256 (`c75069d1…`, identical to the copy that was verified on the phone). `build-boot-image.sh` uses it to generate `/usr/lib/stone/media-hub-server` from the rootfs tree, and the overlay gained `etc/systemd/user/media-hub.service.d/zz-stone-unconfined.conf`.
  - `ofono.service.d/zz-stone-debug.conf` was removed from the overlay. `init` only copies the overlay and never removes files that were dropped from it, so it now has a removal list: `zz-stone-debug.conf` and `etc/systemd/user/lomiri-full-greeter.service.d/stone-core.conf`. The latter is the `LimitCORE=infinity` from the Lomiri crash debugging in the halium14 work. It was never in git, and with `core_pattern=core` it would leave a full core dump on every greeter crash. Comparing the phone with the overlay, those are the only two stale stone files.
  - `stone-call-audio.service` enabled (`etc/systemd/user/pulseaudio.service.wants`). `STONE_CALL_REC_UL` is not set.
  - `tools/phone-debug/` gained `stone-klog.py`, `mic-test.sh`, `stone-radio-debug.sh` (with a new `off`), and `stone-capture.sh`.
  - `boot/ut-init/__pycache__/*.pyc` removed from git, and `.gitignore` gained `__pycache__/`.
  - Still needs root: `persist.vendor.radio.adb_log_on=1`. The user resets it with `sudo sh stone-radio-debug.sh off`.
- New `boot-ut.img` SHA256 `0fa70b9792f531e643521d09441553e9a260efaf001fb5633ba21033d444166e` (kernel `#9`). Not yet written. Once written, delete `~/.config/systemd/user/media-hub.service.d/` and the five copies left in `~/.config/stone/` (`call-audio*.sh`, `ctl-write.py`, `voice-pcm-hold.py`, `media-hub-server`). They are only there for the live session before the flash.
- The user wrote `0fa70b97…` and ran `stone-radio-debug.sh off`. `getprop persist.vendor.radio.adb_log_on` is `0`. The exit code 129 was SIGHUP when `adb shell -t` closed the terminal after the command finished, not a failure. After the flash, the home `media-hub.service.d/` and the five copies were deleted. `systemctl --user show media-hub` has ExecStart `/usr/lib/stone/media-hub-server` (SHA256 `c75069d1…`, the same as the verified one).
- After the flash, the first call was choppy again on the far end. `stone-call-audio` (now the system unit) worked normally: `call audio on: earpiece, mic mono +14 dB`, with the scripts byte-for-byte the same as the repository. The difference: the unit has `PartOf=pulseaudio.service`. On every call, `lomiri-telephony-service-handler` logs "Setting up pulseaudio for voice call" and then `Found card that supports voicecall: 'droid_card.primary'`. It switches the profile to `voicecall`, and PulseAudio aborts on `pa_source_assert_ref()` (`status=6/ABRT`). This crash happened on every call in the previous boot too, including the one with good sound. But back then the watcher was a transient unit and was not restarted along with PulseAudio. Now every PulseAudio crash also stops the watcher (`ExecStopPost=call-audio.sh off`). At call start that is not a problem, but if it happens mid-call the call audio is cut.
- `module-droid-card-28` can only load the 64-bit stub HAL. Its two sinks go nowhere, and its source cannot even be opened (`Failed to open input stream`). It has no option to drop the `voicecall` profile. Removed it from `etc/pulse/stone-touch.pa`, so the telephony service finds no voicecall card and does not touch PulseAudio. `stone-call-audio.service` no longer uses `PartOf=pulseaudio.service`.
- It is not clear that the choppiness comes from this. Both the good and the bad calls had the crash, and the bad call's uplink was not recorded. Uplink level at +14 dB was RMS 554, peak 6326 (about -14 dBFS), which leaves little margin for the vocoder's VAD.
- Test setup applied directly on the phone (no reflash): `pactl unload-module` on the droid card (lasts until PulseAudio restarts), `~/.config/stone/call-mic-gain` = `20`, and a temporary `~/.config/systemd/user/stone-call-audio.service.d/zz-debug-rec-ul.conf` (`STONE_CALL_REC_UL=1`). New `boot-ut.img` SHA256 `3b33787a7bec8e4f7009f40784f4464277f6ab003b08e70539c606763070d7a1` (without the droid card, without PartOf, default gain still +14). Not yet written. Decide the default gain after this test. Once it is decided, delete `call-mic-gain` and the debug drop-in.
- The user confirmed this call (droid card unloaded, +20 dB) was "clear". There was no PulseAudio crash during the call. The uplink recording peaked at 10040 (-10.3 dBFS) with no clipping, and active speech was about -31.1 dBFS (for the comparison with +0 and +14, see "Call audio: what fixed it"). The recording is in `out/halium14/logs/call-audio-debug/stone-uplink-1794295468.raw`. The call lasted about 9 seconds, so the 8-second recording ends with a stretch of silence after the hang-up (p10 = 0).
- The default gain was changed to +20 (`MIC_GAIN=20` in `call-audio.sh`). Deleted `~/.config/stone/call-mic-gain` and `~/.config/systemd/user/stone-call-audio.service.d/`, so there are no stone files left in phablet's home directory. Until the image is written, the `/usr/lib/stone/call-audio.sh` on the phone still defaults to +14.
- New `boot-ut.img` SHA256 `4af37a0d26ce4892184fcef1d6c19bce8603e770423bf052f1337e709207ce21` (kernel `#9`; default +20 dB, no droid card, no PartOf, `stone-call-audio` enabled, removal list for the debug drop-in and the core-dump drop-in). This is the image to write next.

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
