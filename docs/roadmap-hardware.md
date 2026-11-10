# Hardware, after the display is up


The goal of `docs/roadmap-halium14.md` has been reached. On 2026-11-09 the user confirmed Ubuntu Touch had entered Lomiri, and that display, touch, GPU, brightness, charge detection, and vibration all work. This document only covers hardware that is not working yet. Do not reflash `vendor_boot`, `dtbo`, `vbmeta`, or `super`. `boot_b` is now the normal `boot-ut.img` (kernel `#9`, carrying the netd stub; a copy is at `out/halium14/boot-ut-data.img`, SHA256 `b72e43e1…`). The image to flash next is `c1d90d44…` (items 5 and 6 complete; functionally the same as the running `880f4f24…`). It has no passwordless sudo, and it does not return to fastboot by itself. Anything that needs root has to be run by the user with `adb shell -t 'sudo …'`.

`/etc/os-release` is Ubuntu 24.04.5 LTS. The root filesystem comes from `ubuntu-touch-android9plus-rootfs-arm64.tar.gz` on the 24.04-2.x channel. adb is up, serial `stone`. Once mobile data was up on 2026-11-10, the phone clock went from 1970 to the correct time.

## Already confirmed working

- Display, touch (`fts_ts`), GPU acceleration, a smooth UI, and brightness control.
- Charging: `/sys/class/power_supply/battery/status` is `Charging`. The user confirmed the phone recognizes that it is charging.
- Vibration: `/sys/class/leds/vibrator` exists, and the user confirmed it works.
- adb.
- Speaker output (item 3).
- Wi-Fi (item 4).
- SIM, both IMEIs, mobile data (5G/NR), MMS, voice calls with audio in both directions (3G and IMS) (item 5).
- Bluetooth: pairing, A2DP music, and calls on the earbuds (item 6). Calls on earpiece, speakerphone or Bluetooth, chosen in the dialer.

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

> Superseded in part by item 6 ("Call audio routing: what fixed it"): steps 1 to 3 below are now the UCM profile `/usr/share/stone/ucm2/stone/HiFi.conf` applied by PulseAudio, `call-audio-watch.sh` and `~/.config/stone/call-route` are replaced by `call-audio-router.py`, and the route is chosen in the dialer. Steps 4 and 5 and the gain measurements below still hold.

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
- ~~The speaker button in the Phone app does not switch the route.~~ Fixed in item 6 (earpiece, speaker and Bluetooth from the dialer). Wired 3.5 mm headsets are still not handled (open, see item 6).
- Downlink volume is fixed: the call volume keys change the media volume, not `Voice Rx Gain` (open, see item 6).
- The fallback, if calibration is ever required: the vendor audio HAL is running in the container as `android.hardware.audio@7.0::IDevicesFactory/default` and could be driven over HIDL (`setMode(IN_CALL)` and so on), with ACDB. `module-droid-hidl` is only the AudioSystem passthrough and cannot serve as that client.

#### Debug tools

`tools/phone-debug/` (none of them go into the boot image; push them to the phone when needed):

- `stone-klog.py`: phablet cannot open `/dev/kmsg`. It polls `klogctl(READ_ALL)` every 100 ms and fsyncs, so the kernel log from right before a hard reset survives. **Writes about 10 MB an hour; stop it when done.**
- `mic-test.sh amic1|amic3|handset-mic`: records 2 seconds of microphone through MultiMedia1 and prints the level.
- `stone-radio-debug.sh` (sudo): turns on `persist.vendor.radio.adb_log_on` and restarts qcril (ofono pauses data for about 3 minutes afterwards), then captures 90 seconds. `stone-radio-debug.sh off` turns it back off (effective at the next boot).
- `stone-capture.sh` (sudo): copies pstore, the radio/main/system/crash logcat buffers, and dmesg.
- `call-audio.sh` debug subcommands: `route earpiece|speaker|bluetooth` (switches the PulseAudio ports the way the dialer does), `mute 0|1`, `gain DB`, `pcm-rx`, `pcm-tx`, `pcm-off`, `rec-ul [seconds] [file]` (in-call uplink recording, `MultiMedia9 <- VOC_REC_UL`, `hw:0,23`). Setting `STONE_CALL_REC_UL=1` on `stone-call-audio.service` (a user drop-in) records 8 seconds of every call into `$XDG_RUNTIME_DIR`.
- `stone-bt-sco-debug.sh` (sudo): re-powers the BT chip (restarts bluebinder) and saves dmesg and the BT HAL logcat. Its `BT_CMD_SLIM_TEST` check is a no-op on this kernel (see item 6).

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
- New `boot-ut.img` SHA256 `4af37a0d26ce4892184fcef1d6c19bce8603e770423bf052f1337e709207ce21` (kernel `#9`; default +20 dB, no droid card, no PartOf, `stone-call-audio` enabled, removal list for the debug drop-in and the core-dump drop-in). Superseded by `20b85c73…` in item 6.

## 6. Bluetooth

Goal: bluebinder stays running and can scan for devices.

What is seen: the user confirmed Bluetooth is unavailable. `bluetooth.service` is active. `bluebinder.service` is stuck in activating, and the restart count has passed 646. `bluebinder_wait.sh` thinks the Android Bluetooth service is running, then `Failed to open /dev/vhci device`. systemd records `Error: 19 (No such device)`, and the result is `protocol`. `/dev/vhci` needs `CONFIG_BT_HCIVHCI`, which the current kernel does not have. `btpower.ko` is not loaded either.

### Planned steps

1. The kernel from item 2 already includes `CONFIG_BT_HCIVHCI` and `btpower`. This item only verifies.
2. Confirm `/dev/vhci` exists and `bluebinder` is no longer restarting.
3. Scan for nearby devices.

### Current status (2026-11-10)

| Check | Result |
| --- | --- |
| `/dev/vhci` | present (`crw------- root 10,137`); `hci_vhci.ko` loaded by `stone-vhci.service` |
| `btpower` | built in; `rfkill` lists `bt_power` and `hci0`, neither blocked |
| `bluebinder.service` | active (running), `NRestarts=1` per boot (harmless, see below) |
| `bluetoothd` | running; `hci0` powered, BR/EDR + LE, secure connections |
| Address | `redacted`, stable across boots |
| Scan | `bluetoothctl scan on` for 12 s found 7 devices: LE advertisers (for example a `LYWSD03MMC` sensor) and a BR/EDR device (a Samsung monitor with A2DP/AVRCP/HFP UUIDs) |
| PulseAudio | `module-bluez5-discover` and `module-bluetooth-policy` loaded; bluetoothd registered its A2DP SBC/SBC-XQ/aptX endpoints |
| Adapter name | `Xiaomi Redmi Note 12 5G` (was `Generic device`, fixed below) |
| A2DP | confirmed by the user: music plays on the earbuds, which connect and disconnect on their own |
| Calls | confirmed by the user: Bluetooth (both directions), earpiece and speakerphone; output chosen in the dialer |

### Implementation notes

- Nothing was missing on the kernel side. Kernel `#9` has `CONFIG_BT_HCIVHCI=m`, and `build-boot-image.sh` ships `hci_vhci.ko` built from the same tree into `/usr/lib/modules/stone/`. `stone-vhci.service` loads it in `multi-user.target`. `btpower` is built in (`/dev/btpower`, owned by bluetooth per `70-sunstone.rules`).
- The one restart each boot: `bluebinder_wait.sh` returns as soon as `init.svc.*bluetooth*` reads `running` (13.3 s), but the HIDL service is not registered yet. bluebinder exits with "Failed to connect to bluetooth binder service", and `Restart=always`/`RestartSec=1` brings it up for good a second later. Left alone.
- The address comes from `persist.vendor.service.bdroid.bdaddr` (`redacted`, stored byte-reversed). `bluebinder_post.sh` reverses it into `/var/lib/bluetooth/board-address`, and the controller reports the same `redacted`.
- Adapter name. bluetoothd advertises the pretty hostname, and `/etc/writable/machine-info` held `PRETTY_HOSTNAME="Generic device"`, last written on October 12. `update-machine-info-from-deviceinfo.service` runs each boot and already detects `stone` (run with `DEVICEINFO_DEBUG=1`), but upstream only sets the pretty hostname "when pretty hostname is not present yet" (`extras/update-machine-info-from-deviceinfo.cpp`). The first boot ran before `devices/stone.yaml` existed, so libdeviceinfo's fallback got stored and was never replaced. The initramfs `init` now deletes that line from `machine-info` only when it is exactly `Generic device` or `Generic Halium device`, so a name the user picks is kept. The updater then sets the name from deviceinfo on the same boot, before `bluetooth.service`. The regex was tested with the image's busybox on the phone.
- `stone.yaml`'s `PrettyName` was wrong (`Xiaomi Redmi Note 12 Pro 5G` is a MediaTek phone). It is now `Xiaomi Redmi Note 12 5G`, matching `sunstone_cn` in `docs/feasibility.md`. This is the name other devices will see when pairing.
- Bluetooth call audio: see "Call audio routing: what fixed it" below.

### Events

- 2026-11-10: on the running image (`#9` kernel), `/dev/vhci` exists, bluebinder is running after one restart, and `hci0` is powered. A 12-second scan from `adb shell` found 7 nearby devices, LE and BR/EDR. Steps 1 to 3 of the plan are done without any kernel change.
- Found the adapter advertised as `Generic device` and fixed it as above. `stone.yaml` PrettyName corrected to `Xiaomi Redmi Note 12 5G`.
- New `boot-ut.img` SHA256 `20b85c73b295966583af52b30747ee234d8508cf9cb382c78da3719716922cd9` (kernel `#9`; everything in `4af37a0d…` plus the pretty hostname reset and the corrected PrettyName). Written by the user.
- Waiting for the user: flash, then from Settings > Bluetooth confirm the phone's name, pair a headset or speaker, and play audio over it.
- The user confirmed A2DP audio works, and the earbuds (Moondrop Nekocake) connect and disconnect on their own. Calls were not routed to them.

### Call audio routing: what fixed it

Ubuntu Touch lets the dialer choose the call output (phone, speaker, Bluetooth). `lomiri-telephony-service-handler` does it by switching the ports of a PulseAudio sink and source; normally the droid card provides them. Here the droid card cannot work (32-bit vendor HAL), so:

1. **UCM profile** `/usr/share/stone/ucm2/stone/HiFi.conf` (`ALSA_CONFIG_UCM2=/usr/share/stone/ucm2` for PulseAudio and `stone-call-audio`; only card id `holiqrdsku1sndc` matches). Transcribed from the vendor `mixer_paths_qrdsku1.xml`. The verb sets up the speaker chain and one mic, which PulseAudio's probe needs (MultiMedia5 does not prepare without `RX_MACRO RX2 MUX=AIF2_PB`, MultiMedia1 capture not without a decimator on `TX_AIF1_CAP`). Output devices `Speaker`, `Earpiece`, `Bluetooth` each carry media, the VoiceMMode1 downlink, the uplink mic chain and the +20 dB uplink gain (Bluetooth: `SLIMBUS_7` at 8 kHz). Input devices `Mic`, `BluetoothMic` route the MultiMedia1 capture front end.
2. **PulseAudio** (`etc/pulse/stone-touch.pa`) loads `module-alsa-card use_ucm=1` as `sink.primary` / `source.primary` with ports `[Out] Speaker|Earpiece|Bluetooth` and `[In] Mic|BluetoothMic`. Playback goes through `stone_mm5` (`etc/alsa/conf.d/50-stone.conf`, an alsa-lib `hooks` pass-through around `hw:0,9`): PulseAudio does not rewind a non-hw PCM, which this DSP needs (item 3); `max rewind 0`, 4x10 ms. `71-stone-pulseaudio.rules` keeps udev-detect off the card.
3. **telephony-service** only knows the droid port names. `tools/patch-telephony-ports.py` rewrites the five name constants in place (`output-earpiece` -> `[Out] Earpiece`, ... `input-bluetooth_sco_headset` -> `[In] BluetoothMic`) into `/usr/bin/lomiri-telephony-service-handler-stone`. It has to be in `/usr/bin`: elsewhere the handler thinks it is uninstalled, cannot find its protocol files, and never handles a call. `/usr/lib/stone/telephony-service-handler.sh` starts it only while the stock binary is the exact build it was patched from (SHA256 `f369e392…`), otherwise the stock handler.
4. **`call-audio-router.py`** (`stone-call-audio.service`, event driven: ofono signals and `pactl subscribe`) does what the HAL would do on top of the routing: runs the voice session while ofono has a call (`call-audio.sh on`: `voice-pcm-hold.py` + unmute), restarts it when the port changes, mirrors the source mute (dialer's mute button) into `Voice Tx Mute`, and keeps `source.fake.sco` open while the port is Bluetooth. That makes UT's bluez module ("SCO over PCM") open the SCO link, and the BT chip only appears on SLIMbus while the link is up, so the link must exist before the voice session starts (the router waits 0.6 s for the port to settle). If `sink.primary` is missing 10 s after PulseAudio starts, the router falls back to a plain `sink.speaker` (no call routes) so there is always a speaker.

Uplink levels measured with `call-audio.sh rec-ul` (`VOC_REC_UL`, 8 kHz): built-in mic at +20 dB peaks at -10 dBFS (item 5); the earbuds' mic (Moondrop Nekocake, CVSD) peaks at -6 dBFS with speech at about -20 dBFS RMS, so it needs no extra gain.

### Still open (calls and audio)

- **Wired 3.5 mm headset**: not handled at all (media and calls). The phone has the jack: `HPHL/HPHR` controls, `MBHC`, and input devices `holi-qrdsku1-snd-card Headset Jack` / `Button Jack`. Needs UCM devices from the vendor `headphones`/`headset-mic` paths and jack detection. PulseAudio only reads ALSA jack controls, and this card reports the jack only as input events, so either the kernel machine driver gets jack pins (kcontrols) or the router watches the input device. telephony-service would also need `output-wired_headset`/`output-wired_headphone`/`input-wired_headset` patched.
- **In-call volume**: the volume keys change the media volume during a call; the downlink volume is fixed. The HAL sends `Voice Rx Gain` `{index, vsid, ramp}` (write-only control); untested whether the DSP applies it without calibration. On UT the indicator controls a `media.role=phone` stream during calls (the droid card's virtual voice stream), which the router could provide and map to `Voice Rx Gain`.
- **Bluetooth uplink choppiness**: the user heard the earbud mic choppy at the far end on the first Bluetooth calls and clear on the measured one, with nothing changed that affected the uplink (see the events below). The recording has 250 ms stretches of exact digital silence between words (headset noise gate or lost SCO packets). If it comes back, record it with `STONE_CALL_REC_UL=1` to compare.
- Not yet tested by the user: the dialer's mute button, answering/hanging up with the earbud buttons, the ringtone on the earbuds for an incoming call, switching to Bluetooth by connecting the earbuds mid-call.
- Bluetooth calls are narrowband (CVSD, `enable_msbc=false`). Wideband (mSBC) would need the codec negotiated through ofono and `BT SampleRate KHZ_16`.
- No echo cancellation on speakerphone (no ACDB, item 5).

### Call audio route selection (investigation log)

How Ubuntu Touch does it: `lomiri-telephony-service-handler` (`handler/qpulseaudioengine.cpp`) looks for a PulseAudio sink that has both an `output-earpiece` and an `output-speaker` port (plus `output-bluetooth_sco` when a bluez card offers HFP/HSP). From that it builds the outputs the dialer offers (default, speaker, bluetooth). At call start it switches the bluez card to HFP, then sets the sink/source ports; at the end it restores A2DP and the speaker port. Normally the droid card provides those ports. Here there is no such sink, so the dialer gets no choices and the speaker button did nothing (a limitation noted in item 5).

What was checked:
- Bluetooth SCO works through bluebinder: with the earbuds on `handsfree_head_unit` and `source.fake.sco` opened (`parec`), `hcitool con` showed an eSCO link to them. UT's bluez module runs "SCO over PCM": it opens the link while the fake SCO sink or source is in use, and the audio goes over SLIMbus. `SLIMBUS_7` and the `btfmslim` slave exist. The vendor route is `voicemmode1-call bt-sco`: `SLIM_7_RX_Voice Mixer VoiceMMode1` + `VoiceMMode1_Tx Mixer SLIM_7_TX_MMode1`, and `SLIMBUS_7_RX Audio Mixer MultiMedia5` for media.
- The droid card cannot provide the ports (stub HAL, source does not open, voicecall switch aborts PulseAudio). module-alsa-card mixer paths cannot either: the simple mixer of this card does not load (`Mixer hw:0 load error: No such device`; about 300 vendor controls fail to read), and PulseAudio only builds path ports from it.
- UCM works without the simple mixer (it writes controls by name). PulseAudio 16.1 names UCM ports `[Out] <device>` / `[In] <device>`. The handler compares port names against string constants, so `tools/patch-telephony-ports.py` changes the five constants in `.rodata` in place (each shorter, NUL padded; llvm-objdump shows no reference into the middle of any of them; the separate `earpiece`/`speaker`/`bluetooth` strings are untouched).
- module-alsa-card cannot take `rewind_safeguard`, which the speaker sink needs (item 3). PulseAudio disables rewinds on any non-`hw` PCM (`pa_alsa_pcm_is_hw`), so playback goes through `stone_mm5`, an alsa-lib `hooks` pass-through around `hw:0,9`. `aplay -M` on it shows `MMAP_INTERLEAVED` on both the hooks and the hw layer.

Implementation (not yet tested on the phone):
- `usr/share/stone/ucm2/` (selected by `ALSA_CONFIG_UCM2` in the PulseAudio and stone-call-audio units; only card id `holiqrdsku1sndc` matches): verb `HiFi`; output devices `Speaker`, `Earpiece`, `Bluetooth`, each carrying media, the VoiceMMode1 downlink, the uplink mic chain and +20 dB gain (previously hard-coded in `call-audio.sh`); input devices `Mic`, `BluetoothMic` for the MultiMedia1 capture front end.
- `etc/pulse/stone-touch.pa`: `module-alsa-card use_ucm=1` replaces `sink.speaker`, as `sink.primary`/`source.primary`, same 4x10 ms buffer. `71-stone-pulseaudio.rules` keeps udev-detect off this card. `speaker-route.sh` is gone (the `Speaker` device does it).
- `call-audio-router.py` replaces `call-audio-watch.sh` and `~/.config/stone/call-route`: it runs the voice session while ofono has a call, restarts it when the port changes, mirrors the source mute into `Voice Tx Mute`, and keeps `source.fake.sco` open while the port is `[Out] Bluetooth`. `call-audio.sh` keeps only the session primitives plus `route` and `rec-ul` for debugging.
- 2026-11-10 09:36: while running read-only `alsaucm` queries against the new profile, the phone dropped off USB for more than 10 minutes. Once it was back, its uptime showed it had booted at 09:11 (the flash) and had not rebooted: a USB disconnect, not a crash.
- `alsaucm` on the phone: verb `HiFi` and the five devices parse; `PlaybackPCM` is `stone_mm5`, `CapturePCM` `hw:holiqrdsku1sndc,0`. Enabling Earpiece, then Bluetooth, then Speaker leaves exactly that device's media, voice downlink, uplink and mic routes on, and clears the others.
- PulseAudio restarted with the card (test overrides in phablet's home: `~/.asoundrc` for `stone_mm5`, a `pulseaudio.service.d` drop-in for `ALSA_CONFIG_UCM2` and a copy of the .pa without udev-detect). `alsa_card.stone` profile `HiFi`; `sink.primary` ports `[Out] Speaker` (300, active), `[Out] Earpiece` (100), `[Out] Bluetooth` (50); `source.primary` ports `[In] Mic` (active), `[In] BluetoothMic`; no combination ports. `max rewind: 0 KiB`, `fixed latency: 40.00 ms`, buffer 7680/1920 bytes: the same no-rewind behaviour as `sink.speaker`. One second of audio played in 1.05 s. The expected `Unable to load mixer` / `Error opening hctl device` messages are harmless. `pactl set-sink-port`/`set-source-port` run the UCM sequences: the controls read back as in the `alsaucm` test, including the recording route following the source port.
- Bluetooth without a call, the way telephony-service does it at call start (earbuds to `handsfree_head_unit`, ports to Bluetooth): the router logged `route: [Out] Speaker -> [Out] Bluetooth`, opened `source.fake.sco`, and `hcitool con` showed an eSCO link. Back to Speaker: the source was closed and the eSCO link dropped.
- The first router polled ofono every 0.5 s and used about 2 s of CPU per minute (the old `call-audio-watch.sh` used 5 min 6 s in 45 min). Rewritten on ofono's `CallAdded`/`CallRemoved`/`PropertyChanged` signals and `pactl subscribe` in a GLib loop, with a 30 s resync: 1 tick in 30 s while idle.
- Live test setup on the phone (no flash needed; removed once the image is confirmed): the overrides above, plus `lomiri-telephony-service-handler.service.d/zz-stone-test.conf` (patched handler, SHA256 `2c309e8d…`) and `stone-call-audio.service.d/zz-stone-test.conf` (router and `call-audio.sh` from `~/stone-ucm-test`).
- New `boot-ut.img` SHA256 `4675dab3b156f0335d9520c5399e12fba99246bc518ad64b4f5b797a5a689cef` (everything in `20b85c73…` plus the above). Not written; superseded below.
- Live call test with the overrides, reported by the user: outgoing calls no longer worked; an incoming call could be answered, but the timer stayed at 0:00, and after the far end hung up it could not be hung up; Bluetooth connected mid-call did not take over; the speaker/earpiece button did nothing. ofono only ever saw the incoming call, and the router ran it on `[Out] Speaker`. The handler logged nothing for either call (no "Setting up pulseaudio for voice call"), although the approver and indicator saw the incoming one; its `HandledChannels` was empty.
- Cause: the restarted handler took 50 s to start (two 25 s D-Bus timeouts, `No such signal ... ProtocolsChanged`; at boot it starts in 2 s). telephony-service's `isRunningInstalled()` (`config.h.in`) only treats the binary as installed when it runs from `/usr/bin`. From `~/stone-ucm-test` (and from `/usr/lib/stone`, where the image would have put it) it looks for its protocol files in the build's source directory, finds none, and asks its own D-Bus name for them, which cannot answer while it is starting. Without protocols it never sets up its accounts, so it neither starts nor handles calls. All four symptoms are this one failure; the routing never got a chance. Confirmed by restarting the test copy with `TELEPHONY_SERVICE_PROTOCOLS_DIR=/usr/share/lomiri-telephony-service/protocols`: started in 0.3 s, like at boot.
- Fix in the image: the patched copy is installed as `/usr/bin/lomiri-telephony-service-handler-stone` (a new file no package owns), started by `/usr/lib/stone/telephony-service-handler.sh` from the unit drop-in. The wrapper runs it only while the stock `/usr/bin/lomiri-telephony-service-handler` still has SHA256 `f369e392…` (the build it was patched from), otherwise the stock handler.
- All test overrides were removed from phablet's home (`~/.asoundrc`, the three user drop-ins, `~/stone-ucm-test`), so the next boot runs only from the image.
- New `boot-ut.img` SHA256 `3e0068dba57dacc6416e16fc117644c561024cc3dbe6b62a350cf623301368e9`. Written by the user.
- After that flash the user reported: calls can be made again, but with the earbuds connected the call audio stayed on the earpiece (both directions), the volume rocker changed the speaker volume, and with the earbuds off there was no speaker sound at all. A2DP still worked.
- Cause of the missing speaker: PulseAudio could not load the UCM card at boot (`Failed to find a working profile`), so the only sink was `sink.fake.sco`. Without `sink.primary` telephony-service had no ports, so no Bluetooth route; the call worked only through the router's fallback (`no sink.primary; enabling UCM Earpiece directly`). Debug log of a manual load: opening `stone_mm5` failed on `SNDRV_PCM_IOCTL_PREPARE` (-22), kernel `RX_CDC_DMA_RX_1: ASoC: backend prepare failed -22`. PulseAudio probes right after setting the verb, before any device is enabled, and at a clean boot the codec side of both back ends is unrouted: MultiMedia5 does not prepare while `RX_MACRO RX2 MUX` is not `AIF2_PB`, and MultiMedia1 capture does not prepare without a decimator on `TX_AIF1_CAP` (both reproduced: `play=1 capture=1`). In the live test these had been left set by `speaker-route.sh` and earlier calls. Fix: the verb's EnableSequence now sets up the speaker chain and one mic (amic1); the device DisableSequences no longer clear `TX_AIF1_CAP Mixer DEC0`. From the cleared state, the new verb alone gives `play=0 capture=0`.
- Safety net in the router: if `sink.primary` is still missing 10 s after PulseAudio answers, it logs an error, applies the UCM Speaker device with `alsaucm` and loads a plain `module-alsa-sink` on `stone_mm5` as `sink.speaker` (speaker sound, no call routes).
- `adb push` of a directory drops the phone off USB until it is reconnected (happened twice, the first time at 09:36); push single files or a tar instead.
- Live session repaired by hand (`pactl load-module module-alsa-card ...`, defaults set): `sink.primary` with the three ports, `max rewind 0`, router `route: None -> [Out] Speaker`.
- Bluetooth SCO path itself: with the port on Bluetooth, playback fails at `btfm_slim_hw_init: failed to get slimbus btfmslim_slave logical address: -6`, `SLIMBUS_7_RX: ASoC: BE open failed -6`. The NGD controller (`a5c0000.slim`, `ngd_msm_ctrl`) is bound and answers, but the ADSP (bus master) returns logical address 0xFF for the chip's enumeration address `00:01:20:02:17:02`: the BT chip (`QCA_APACHE_SOC_ID_0121`, `vendor.qcom.bluetooth.soc=cherokee`) has never reported present on SLIMbus. So the DSP has no audio path to the BT chip even when the SCO link is up. The vendor BT libraries contain nothing SLIMbus related. Needs root to see more: `tools/phone-debug/stone-bt-sco-debug.sh` tests enumeration directly with btpower's `BT_CMD_SLIM_TEST` ioctl (it runs the same `btfm_slim_hw_init`), re-powers the chip by restarting bluebinder and tests again, and saves dynamic-debug dmesg, the SLIMbus IPC log and the BT HAL logcat to `~/bt-sco-debug.txt`.
- New `boot-ut.img` SHA256 `880f4f2486ef39ecc225a6b276803dcbd0ff3ae2571d1e588da9c5c9ad6bf133` (the verb fix and the router safety net). Written by the user.
- The user ran `stone-bt-sco-debug.sh` (output in `out/halium14/logs/bt-sco-debug.txt`). Both `BT_CMD_SLIM_TEST` results ("ok (0)") are meaningless: that ioctl case is compiled only with `CONFIG_BTFM_SLIM_WCN3990`/`BT_SLIM_QCA6390/6490`, and this kernel (like the vendor `holi_QGKI.config` and `moonstone_defconfig`) has only `CONFIG_BTFM_SLIM=y`, so it returns 0 without calling `btfm_slim_hw_init` (no btfm lines in dmesg during the tests). Debugfs has no `dynamic_debug`. The useful part is the HAL log: restarting bluebinder powered the chip off and on (`PowerUpChip enable(0)` / `enable(1)`) and reloaded `apbtfw11.tlv` + `apnv11.bin` from `/vendor/bt_firmware` (`BTFM.CHE.2.1.6-00057-QCACHROMZ-1`, `APACHE_VER_1_2_1`), the same files Android uses.
- Opening SLIMBUS_7 right after that re-power still fails the same way (`logical address: -6`). So it is not boot order: the chip does not report present on SLIMbus even with the ADSP and bus up and fresh firmware.
- Android sends both BT SCO and A2DP offload over `SLIMBUS_7` (`audio_platform_info*.xml`: `SND_DEVICE_OUT_BT_SCO ... interface="SLIMBUS_7_RX"`, `SND_DEVICE_IN_BT_SCO_MIC ... SLIMBUS_7_TX`), and there the BT stack sets up the SCO link before the audio HAL opens the back end. All SLIMBUS_7 tests so far ran without an SCO link up. Next test: earbuds in HFP with the eSCO link up (fake SCO source open), then open SLIMBUS_7. If the chip enumerates only while a link is routed to it, the router has to bring the link up before the voice session starts. If it still does not, the Android BT stack is sending something bluez does not (a vendor command), and the HCI traffic needs comparing.
- The user flashed `880f4f24…` and reported: Bluetooth calls mostly work (audio in the earbuds both ways), earpiece and speakerphone calls work, A2DP still works. Only issue: the far end hears the earbud mic choppy, like the built-in mic before the gain fix.
- Why Bluetooth works now: the router opens `source.fake.sco` (SCO link up) when the port changes, and starts the voice session 0.6 s later. With the link up, the chip enumerates: `btfm_slim_hw_init`, `btfm_slim_alloc_port`, `btfm_slim_enable_ch ... rates:8000`, `slim_connect_sink(port: 16)`, `slim_connect_src(port: 0)`. So the BT chip only appears on SLIMbus while an SCO link is up; all earlier SLIMBUS_7 tests ran without one.
- Choppy uplink: the headset mic enters the DSP on `SLIMBUS_7_TX` and goes straight into `VoiceMMode1_Tx`. The +20 dB of the built-in mic is `TX_DEC0 Volume` in the codec, which this path bypasses, and there is no other gain: the DSP controls are `Voice Rx Gain` (downlink) and `SLIMBUS_7 LOOPBACK Volume` (`AFE_PARAM_ID_LOOPBACK_GAIN_PER_PATH`, AFE loopback only); q6voice has only `voc_set_rx_vol_step`. The headset's own mic gain cannot be raised either: PulseAudio's ofono backend has no `+VGM` (only the native HSP backend does) and ofono's `HandsfreeAudioCard` has no volume.
- Fix (in test): `/usr/lib/stone/bt-mic-boost.py` copies the headset mic, amplified, into the uplink through the DSP's in-call music path, Android's `incall_music_uplink` (`USECASE_INCALL_MUSIC_UPLINK`, PCM 23): `SLIM_7_TX` -> MultiMedia1 capture (`hw:0,0`, routed by the BluetoothMic device) -> x gain (audioop, saturating) -> MultiMedia9 playback (`hw:0,23`) -> `Incall_Music Audio Mixer MultiMedia9` (added to the UCM Bluetooth device) -> uplink. 8 kHz mono, 20 ms periods. The direct path stays mixed underneath, 20 dB quieter. It logs the mic input level every 5 s. The router runs it while a session is on `[Out] Bluetooth` and the mic is not muted (+20 dB, or `~/.config/stone/bt-mic-gain`; 0 disables). Dry run without a call: it opens both PCMs and runs.
- Live test setup (no flash): `~/stone-test/{call-audio-router.py,bt-mic-boost.py}` via `stone-call-audio.service.d/zz-stone-test.conf` (with `STONE_CALL_REC_UL=1` to record the uplink), and `Incall_Music Audio Mixer MultiMedia9` set by hand (the installed profile does not have it yet). Image `73826cb7…` built with it, not written.
- The user reported the Bluetooth uplink as clear on the test call (10:56:26 to 10:56:41). The logs show the boost did not cause it: `bt-mic-boost: running, +20.0 dB` at 10:56:28, then `read: Input/output error` at 10:56:38, exactly ALSA's 10 s timeout for a capture that never delivers a period. MultiMedia1 got nothing from `SLIM_7_TX` although telephony-service had set `[In] BluetoothMic` at 10:56:26 (so `MultiMedia1 Mixer SLIM_7_TX` was on). The uplink recording (`out/halium14/logs/bt-call/stone-uplink-1794326190.raw`, 10:56:31 to 10:56:39) has speech at about -20 dBFS RMS in 250 ms windows, peaks -6 dBFS, the same before and after the boost died. So the earbud mic is loud enough on its own, and +20 dB would have clipped it. What made the first Bluetooth calls choppy is not known: there is no recording of them. Between words the recording has 250 ms stretches of exact digital silence (-99 dB), more like the earbuds' noise gate or lost SCO packets than a quiet mic.
- Removed `bt-mic-boost.py`, its router code and the in-call music route from the UCM Bluetooth device. The test overrides and test files were removed from the phone (`~/stone-test`, the drop-in, `stone-bt-sco-debug.sh`, `bt-sco-debug.txt`, recordings); the route control was set back to 0 and the router restarted from the image.
- New `boot-ut.img` SHA256 `c1d90d4485e9fe24c87a0a2a96fa164e49e8261a467bc1bdec20b7408e5c8803`. Compared with the running `880f4f24…`, only the router's docstring changed (no functional difference), so flashing it is optional. This is the image to write next.

## 7. Camera

Goal: the camera app can open and show a preview.

What is seen: the user confirmed the camera flashes and exits as soon as it opens. `/dev/video0`, `video1`, `video2`, `video32`, and `video33` are present, and so are `/dev/video/venus_dec` and `venus_enc`. `camera.ko` is not loaded. No application-side crash stack was captured this time.

### Planned steps

1. Wait for `camera.ko` from item 2 to load, then open the camera and see whether it still crashes or can preview.
2. If it still crashes, take the journal and logcat and check them against the HAL. Do not change the display stack first.

### Implementation notes

### Events
