# Release: recovery, updates and going public

`docs/roadmap-hardware.md` and `docs/roadmap-hardware-2.md` are done.
- Every piece of hardware on this unit works, or has a recorded reason why not.
- The last image is `fced82d0…` (kernel `#17`).

That ends the bring-up on one phone. It does not yet make a port that other people can install, update, or trust. This document covers that next stage:
- a recovery;
- system updates;
- what has to change before the repository is public;
- what UBports needs to list the device.

It follows the same rules as the hardware documents:
- Fixes go into the repository.
- Live tests run on the phone first.
- The user flashes and commits.
- Do not reflash `vendor_boot`, `dtbo`, `vbmeta` or `super` without a decision recorded here first.

Checked 2026-11-11 for this document:
- the UBports installer configs (`ubports/installer-configs`, v2 schema; Nothing Phone 1 `Spacewar.yml` as a recent Halium 11+ example);
- the shared port build tools (`halium-generic-adaptation-build-tools`);
- the device list (`devices.ubuntu-touch.io`: `data/devices/*`, `portStatus.json`, `progressStages.json`);
- this phone's boot images and kernel command line;
- the tracked files of this repository.

## Where the port stands

- **Hardware:** everything in the two hardware documents works on `sunstone_cn`:
  - display at 120 Hz (with a 60/120 Hz switch), GPU, touch;
  - calls and SMS on both SIM slots; data; VoLTE; MMS (also over Wi-Fi);
  - Wi-Fi; Bluetooth audio and calls (wideband);
  - wired headsets (3.5 mm and USB); cameras; hardware video decoding;
  - sensors; GNSS; fingerprint unlock; USB MTP; microSD; IR emitter; in-call volume.
  - NFC is absent on this SKU and correctly hidden.
- **How it is built:** the Ubuntu Touch 24.04-2.x root filesystem fills the userdata partition. It boots through a custom busybox initramfs, which copies `boot/ut-init/rootfs-overlay` into the root filesystem on every boot. The Halium 14 system image runs the crDroid 14 vendor in the LXC container.
- **What it lacks for anyone else:** a recovery, an update channel, an installer, public sources, and testing beyond one unit.

## Fix order

1. Recovery. The phone has none at the moment (see below). It is needed for the UBports installer, system-image updates and factory reset, and as a way back when a boot image is bad.
2. Boot modes: offline charging and the recovery branch in the initramfs. They share the same mechanism, so they are done together.
3. Cleanup before going public: personal data, history, README, licences, a reproducible build.
4. Sources that the licences require: the kernel tree, busybox, and the patched programs.
5. Upstream the fixes that are not stone-specific, to shrink what the port has to carry.
6. Decide the port's structure: keep this layout, or move to UBports' standard community-port layout.
7. Updates: apt-safe first, then a system-image (OTA) channel.
8. UBports Installer config.
9. Device page on devices.ubuntu-touch.io.
10. The other stone variants.
11. Features not yet checked: the rest of UBports' feature matrix.
12. Security: AppArmor D-Bus and socket mediation in the kernel.

## 1. Recovery

Goal: a recovery that can apply UBports system images, factory-reset, and give adb access when the system does not boot. On this phone it is reached with Volume Up + Power, or `fastboot reboot recovery`.

What is seen (2026-11-11):
- stone has no recovery partition. crDroid 14 uses "recovery as boot": the stock `boot.img` ramdisk (17 MB, boot header v3) is the recovery. It contains `system/bin/recovery`, `init.recovery.qcom.rc` and `res/`, and Android's `init` picks normal boot or recovery from the kernel command line.
- The bootloader adds `androidboot.force_normal_boot=1` for a normal boot (seen in `/proc/cmdline`) and leaves it out for recovery.
- `boot_b` now holds our busybox initramfs, which never looks at that flag. So **the active slot has no recovery**: "reboot to recovery" boots Ubuntu Touch. The other slot (`boot_a`) has not been checked.
- Today the way back from a bad boot image is fastboot alone. `out/halium14/boot.img` (stock crDroid 14) and earlier images are kept.
- UBports' standard recovery is the **unified UBports recovery** (from `halium_bootable_recovery`). CI publishes it per Halium version; for this phone that is `halium-14.0`:
  `https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%2Fporting%2Fcommunity-ports%2Fjenkins-ci%2Fgeneric_arm64/job/halium-14.0/lastSuccessfulBuild/artifact/ramdisk-recovery.img`.
- The shared build tools (`make-bootimage.sh`) put it into the boot image. On devices without a recovery partition they add it as a vendor ramdisk fragment, but fragments need vendor_boot header v4, and stone's `vendor_boot` is v3.
- The installer flow of recent ports (for example `Spacewar.yml`): flash boot images, format userdata ext4, reboot to recovery, then `systemimage:install` pushes the system image through that recovery.

Planned steps:
1. Read `boot_a` (root, read-only `dd`) to see whether a working crDroid recovery is still on the other slot. Optional, during the manual test.
2. Unpack the unified recovery ramdisk, and check that it runs with stone's v3 layout and our kernel: `recovery.fstab` (`slotselect`, dynamic partitions), the display, touch or keys, adb.
3. Put both ramdisks into our boot image. The initramfs `init` stays the first program: when `androidboot.force_normal_boot=1` is missing, it hands over to the recovery ramdisk's `init`; otherwise it boots Ubuntu Touch as now.
4. Manual test: `fastboot reboot recovery`; adb in recovery; a factory reset on a test userdata (decide first what reset may wipe, since the root filesystem *is* userdata here; see item 6).

### Implementation (2026-11-11)

- **The recovery:** UBports' unified recovery ramdisk, `generic_arm64` `halium-14.0` CI build 596 (15309942 bytes gzip, SHA256 `c9c32a41…`, LineageOS 14-based, `ro.ubuntu.recovery`). `tools/fetch-recovery-ramdisk.sh` downloads it into `out/recovery/` and checks it.
  - Unpacked (`out/recovery/tree`): Android `init` (`/init` → `/system/bin/init`), `recovery`, `adbd`, `fastbootd`, `system-image-upgrader` with UBports' archive keyring, and the LineageOS recovery UI.
  - It brings no `recovery.fstab` and imports `/init.recovery.${ro.hardware}.rc` (`qcom`); ports supply both.
  - Every entry is root-owned; there are no device nodes; it already has `ro.adb.secure=0` and `ro.debuggable=1`.
- **`boot/ut-recovery/`, the device files merged in:**
  - `init.recovery.qcom.rc`: crDroid 14's own, from its boot ramdisk (sets `sys.usb.controller` from `ro.boot.usbcontroller` = `4e00000.dwc3`, and the backlight).
  - `system/etc/recovery.fstab`: crDroid 14's (the logical partitions with `slotselect`, `metadata`, `persist`, `misc`, firmware mounts) **without `/data`**. userdata is the Ubuntu root filesystem, so with a `/data` entry "Factory reset" would format the whole OS. The fstab comment shows how to mount it by hand from adb. Factory reset waits for item 6.
  - `prop.append`: the USB ids and adb properties that `make-bootimage.sh` adds for unified recoveries (`ro.recovery.usb.vid=18D1`, `adb.pid=D001`, `fastboot.pid=4EE0`, `service.adb.root=1`, `ro.build.ab_update=true`).
- **`build-boot-image.sh`** (boot mode only): checks the pinned SHA256, unpacks the recovery, adds `boot/ut-recovery`, repacks with `-R 0:0`, and stores it as `/ramdisk-recovery.img` (gzip, 15249050 bytes) in our initramfs. It also adds busybox `gzip` and `cpio` links.
- **`boot/ut-init/init`**, first thing after the helpers: without `androidboot.force_normal_boot=1`, and unless `androidboot.mode=charger`, it unpacks `/ramdisk-recovery.img` into a tmpfs, unmounts `/proc`, `/sys` and `/dev`, and does `switch_root` to the recovery's `/init`. Normal boots take the old path unchanged.
- **Unlike Halium, `/lib/modules` is not moved over.** The vendor ramdisk's 49 GKI modules (`lib/modules/5.4-gki`) do not match our kernel, and Android's first-stage init skips module loading when the directory is missing (it would fail on modules that do not load). Display and keys are built into our kernel; touch in recovery may not work, and the volume and power keys drive the menu.
- **Image** `out/halium14/boot-ut.img`: 65835008 bytes (`boot_b` is 134217728), SHA256 `e8ff055e399e1459d6cf5c71dac09b02cff20fe446cdc48b57bef7627b3edc41`, kernel `#17` (byte-identical). Not yet written. The previous image (`fced82d0…`) is kept as `out/halium14/boot-ut-fced82d0.img`.
- **If the recovery does not come up:** a normal boot is unaffected (the bootloader passes `force_normal_boot=1`). Rebooting with the power key returns to Ubuntu Touch, and `out/halium14/boot-ut-fced82d0.img` restores the old image.

### First test (2026-11-11, image `e8ff055e…`)

The user entered the recovery (`sudo reboot recovery` in Ubuntu Touch); `adb devices` showed `stone recovery`. The only visible problem was very small text. Checked over adb (root):
- `ro.ubuntu.recovery=true`, slot `_b`, kernel `#17`, `sys.usb.controller=4e00000.dwc3`, adbd root, all 91 by-name partitions.
- Our init logged "recovery boot (no androidboot.force_normal_boot=1)"; Android's init: "First stage mount skipped (recovery mode)". The missing selinuxfs and `/system/build.prop` are harmless.
- **Display:** 1080 x 2400 @ 120 FPS, mode 0 ("Atomic Commit failed in DisableNonMainCrtcs" refers to secondary outputs the phone does not have).
- **Input:** `fts_ts` (touch), `gpio-keys`, `qpnp_pon` and `uinput-goodix`, so touch should work (its driver is built into our kernel).
- The recovery log's only errors are `Failed to find block device for partition system_b` (also `system_ext_b`, `product_b`, `vendor_b`, `odm_b`): the logical partitions are not mapped at startup. LineageOS maps them on demand (fastbootd, mounting); harmless for now.
- **userdata was mounted read-write at `/data`.** The recovery's `setup-fake-cache` (`ro.ubuntu.recovery.fakecache=true` from its `init.rc`) mounts userdata to provide `/cache` from `/data/cache`. Here that is the Ubuntu root filesystem, and its `cache` is a symlink to `/android/cache`, which does not resolve in recovery, so `/cache` stayed an empty directory.
- **LVM:** the recovery ships `lvm-migrate`, `lvm-fs-migrator` and `lvm-super-migrator` (UBports' LVM layout for userdata). At startup it ran only as a dry run ("not requested, skipping"). A real migration needs `ro.systemimage.use_lvm=true` in `system-image-upgrader` (not set); `lvm-migrate` also refuses userdata contents it does not recognise. Not run here.
- **`boot_a`** (read-only): boot header v3, 48120320-byte kernel, 1573252-byte ramdisk, SHA256 `efc1a895…` over 49704960 bytes. It matches no image kept in `out/` or `backups/`; most likely an early Droidian/Halium experiment from `docs/roadmap-04-05.md`. It is not a recovery; this phone's only recovery is the new one.

Changes after the test:
- **UI density:** the ramdisk ships mdpi images (font 12x22, `font_menu.png` 1152 px wide). crDroid's own recovery for stone uses an 18x32 font and a 2592x96 menu font, which is UBports' **xxhdpi** set.
  - `boot/ut-recovery/res/images` = `ubports/halium_bootable_recovery` (`halium-14.0`, `9cdb4a9`) `res-xxhdpi/images`, with `font.png` resolved from `fonts/18x32.png` (OFL, `res/OFL-fonts.txt`). That is what `make-bootimage.sh` does for `deviceinfo_unified_recovery_ui_density="xxhdpi"`.
  - The screen is about 395 PPI (between xhdpi 320 and xxhdpi 480).
- **`prop.append` gained `ro.ubuntu.recovery.fakecache=false`**, so userdata stays unmounted in recovery. Read-only properties from `prop.default` win over `init.rc`'s later `setprop`.
- New image SHA256 `2708ccaf6e01d5be7f73fec6e43760cb32ee3b8b676c4dfac546595927728b11` (kernel `#17`). Not yet written.

### Second test (2026-11-11, image `2708ccaf…`): done

User:
- "Reboot system now" from the first recovery returned to Ubuntu Touch;
- after flashing `2708ccaf…`, the recovery text is a normal size and **touch works**;
- "Enter fastboot" works (fastbootd), and `fastboot reboot` returned to Ubuntu Touch.

Checked over adb in recovery afterwards:
- `ro.ubuntu.recovery.fakecache=false`; `setup_fake_cache` ran and exited; **userdata is not mounted** (18 mounts, none of `sda19`). `lvm-migrate`: dry run only, as before.
- The rescue mount from the fstab comment works. Read-only for the test: `mount -o ro -t ext4 /dev/block/by-name/userdata /mnt/ut` showed Ubuntu 24.04.5, `/home/phablet` and 4.3G used of 100G; it unmounted cleanly.
- `adb reboot` from recovery: a normal boot (`androidboot.force_normal_boot=1`, kernel `#17`, 3 minutes later), so leaving recovery leaves no boot-into-recovery state behind.
- systemd was `degraded` only because of `logrotate.service`: "stat of /var/log/syslog failed" and `/var/log/auth.log` as well. `lxc-android-config` ships `/etc/logrotate.d/touch-syslog` for those files without `missingok`, but rsyslog is not installed on 24.04 (journald only). This is unrelated to the recovery: the timer had not fired in the earlier, short boots. It is an upstream fix (item 5).

Item 1 is done for what this layout allows:
- the recovery boots with the right density, touch and keys;
- adb works (root), and so do fastbootd and reboot;
- the Ubuntu root filesystem stays untouched unless mounted by hand.

Still open (they need the item 6 layout decision):
- factory reset (with `/data` out of the fstab, the recovery cannot format the OS);
- system-image installs through `system-image-upgrader`, which would write `ubuntu.img` and friends to the wrong place for this layout. Not to be used until then.

## 2. Boot modes: offline charging and recovery

Goal: plugging the charger into a powered-off phone shows charging and does not boot the whole system.

What is seen:
- The bootloader sets `androidboot.mode=charger` for a charger boot, and our init ignores it. So a charger boot most likely starts all of Ubuntu Touch. Not tested.
- UBports' feature matrix lists `offlineCharging`.
- Ubuntu Touch ports usually run a small charger UI from the ramdisk (Halium ramdisks have a charger mode).

Planned steps:
1. Test: power off, plug in, and see what boots.
2. Branch in the initramfs on `androidboot.mode=charger`, together with the recovery branch of item 1. Take the charger program from the Halium ramdisk, or from the unified recovery if it has one.

## 3. Cleanup before going public

Goal: a repository that can be published without personal data, and that someone else can build from.

What is seen (tracked files, 2026-11-11):
- **Personal data:**
  - the IMSI of the user's SIM in `docs/roadmap-hardware.md`;
  - the phone's serial number `stone` in `docs/feasibility.md` and hard-coded as the USB gadget serial in six init scripts (`boot/ut-init/init`, `init-disk`, `init-logs`, `boot/droidian-init/*`), so every phone would claim this unit's serial;
  - the phone's and the earbuds' Bluetooth addresses in both hardware roadmaps;
  - the user's email in two patch headers (normal for authored patches; the user's choice).

  Phone numbers and coordinates are only in `out/` (ignored).
- **History:** all of the above is also in the 21 commits. Publishing this history publishes it, so the history has to be rewritten (or the repository started afresh) before it goes public.
- **No README, LICENSE or NOTICE files.**
- **The build depends on files only this machine has:** the crDroid zip, the UBports root filesystem and the Halium image, the unpacked `out/halium14/rootfs-tree`, the kernel tree and the toolchain. All of them sit in ignored folders (47 GB checkout).
- `boot/droidian-init/` belongs to the abandoned Droidian route (`docs/roadmap-04-05.md`).
- `docs/` is a work log. There is no install guide for someone else.

Planned steps:
1. Replace personal data in the docs (IMSI, serial, Bluetooth addresses), and make the USB serial come from the bootloader (`androidboot.serialno`) or a generic value.
2. Rewrite the history (for example `git filter-repo`), or publish a fresh repository and keep this one private.
3. Add a README (what it is, the status, the supported variants, how to install, how to build), licences (item 4) and a short install guide. Keep the roadmaps as the development log.
4. A fetch script that downloads and checks (SHA256) every input:
   - the crDroid 14 zip;
   - the UBports `ubuntu-touch-android9plus-rootfs-arm64.tar.gz` and `halium_halium_arm64.tar.xz` (pinned builds);
   - the kernel source (`crdroidandroid/android_kernel_xiaomi_sm6375` `14.0` at `42e99ef7…`) with `kernel/patches/`;
   - the toolchain.

   Then a single build entry point: kernel → root filesystem tree → boot image.
5. Remove or archive `boot/droidian-init/` and the obsolete debug paths.

## 4. Sources the licences require

Goal: anyone who gets a boot image can get its corresponding source.

What is seen: the boot image contains:
- the Linux kernel (GPL-2.0), crDroid's tree plus `kernel/patches/0001`–`0009` and `kernel/config/halium-sunstone.fragment`;
- busybox (GPL-2.0, `third_party/busybox-aarch64`);
- the overlay. Its programs, with their sources:
  - biometryd and its library (GPL-3.0/LGPL-3.0): built by `tools/biometryd/build.sh` from upstream plus a patch;
  - the patched UBports binaries built by `build-boot-image.sh` (telephony-service handler, media-hub, Halium's `libaudioclient.so`): patch scripts in `tools/`, applied to exact upstream versions;
  - the runtime-patched Mir platform: `display-setup.sh`, with the source patch in `tools/upstream/`.

Planned steps:
1. Publish a kernel fork: crDroid's commit plus the patches as commits, plus the config fragment. Tag every release with the boot image it went into.
2. Record each distributed binary's upstream source and version next to it (busybox version, biometryd commit, the UBports package versions the patch scripts check). Add license texts.
3. Choose a licence for this repository's own scripts. GPL-3.0 matches most UBports components; ask the user.

## 5. Upstream the fixes

Goal: fewer binary patches and stone-only copies, which break on package updates (see "Deferred: system updates" in `docs/roadmap-hardware.md`).

Candidates, from the hardware documents:

| Fix | Upstream | Present here as |
| --- | --- | --- |
| HWC2 present-fence wait (120 Hz) | mir-android2-platform | runtime binary patch; `tools/upstream/mir-android2-platform-0001-*.patch` |
| AppArmor label by pid when D-Bus has none | biometryd (and a 24.04-2.x release of biometryd main) | rebuilt daemon; `tools/biometryd/` |
| Port names (`output-earpiece` …) | lomiri-telephony-service: make the port names configurable | binary patch (`tools/patch-telephony-ports.py`) |
| Empty AppArmor label → "unconfined" | media-hub | binary patch (`tools/patch-media-hub.py`) |
| `releaseAudioSessionId` hang | Halium (`libaudioclient` without AudioFlinger) | binary patch (`tools/patch-libaudioclient.py`) |
| mSBC through Enhanced Setup (kernels < 5.14) | Halium/UBports kernel patch collections; any QCOM SCO-over-PCM port | `kernel/patches/0009` |
| First refresh-rate command after continuous splash | crDroid kernel (`dsi_panel.c`) | `kernel/patches/0008` |
| APN MVNO `gid` matching | ofono apndb plugin / lineageos-apndb | `tools/apndb-prefer-mvno.py` |
| Codec-gain in-call volume without ACDB | none generic (a design note for the UBports porting docs) | `call_volume.py` |
| `touch-syslog` logrotate config without `missingok` (no rsyslog on 24.04, `logrotate.service` fails) | lxc-android-config | not worked around |

Planned steps: open merge requests in that order, starting with the smallest and most general. Track their state in this table.

## 6. Port structure: keep this layout or move to UBports' standard one

Goal: a decision, recorded here, on whether the port keeps its own structure or moves to the community-port layout UBports builds, hosts and updates.

What is seen:
- **UBports' layout** (`halium-generic-adaptation-build-tools`, CI template `gsi-port-ci.yml`):
  - a `deviceinfo` file;
  - the kernel built by `build-kernel.sh`;
  - a boot image with the Halium ramdisk (`initramfs-tools-halium`, "dynparts" for dynamic partitions) and the unified recovery;
  - device files as an overlay packed into a **device tarball** (`device_<codename>.tar.xz`), which system-image installs with the root filesystem.

  The root filesystem goes into the system partition or `ubuntu.img`, not over the whole userdata partition. Recent ports resize `system_a` to 4 GiB for it (`Spacewar.yml`).
- **This port:**
  - the root filesystem is the userdata partition;
  - our own initramfs: USB gadget, mounting, the overlay copy on every boot;
  - fixes that patch installed binaries at boot (`display-setup.sh`, `stone-vendor-fixups.py`), gated on exact SHA256 hashes.
- The device page's `sources` fields (`portType: community`, `portPath`, `deviceGroup`, `deviceSource`, `kernelSource`) point into UBports' GitLab group for community ports. To be confirmed with UBports: how a new port gets a place there (usually asked in the UBports porting channel).

Planned steps:
1. List what our initramfs does that the Halium ramdisk does not, and the reverse.
2. Map `rootfs-overlay` onto a device tarball. The hash-gated runtime patches stay as boot-time scripts.
3. Decide, with the user. Moving gives UBports CI, OTA and installer support "for free", but changes the partition layout, so it means one reinstall. Staying means items 7 and 8 are this repository's own work.

## 7. Updates

Goal: the phone can be updated safely, first with apt, later through Settings → Updates.

What is seen:
- There is no system-image channel (`/etc/system-image/config.d` is empty); updates are apt.
- What makes `apt full-upgrade` unsafe today is listed in "Deferred: system updates" (`docs/roadmap-hardware.md`). Since then the port has added more hash-gated pieces, which an upgrade turns off (logged, not broken):
  - the Mir platform patch;
  - the Settings Brightness page;
  - the biometryd drop-in (the packaged daemon would come back if its package changes; check).
- System-image OTA needs a device tarball, CI building it, and a channel on UBports' system-image server (`devel`, then `rc`/`stable`). Those channels are run by UBports.

Planned steps:
1. Do the "Deferred: system updates" list: patch at boot from whatever binary is installed, and add a check after an upgrade.
2. Run `apt full-upgrade` once on the test phone and verify the hardware checklist.
3. After item 6: CI building the device tarball and the boot images; then ask UBports for a `devel` channel.

## 8. UBports Installer

Goal: install with the UBports Installer, as on the OnePlus 6T.

What is seen:
- Configs live in `ubports/installer-configs` (`v2/devices/<codename>.yml`, schema `v2/schema/device.schema.yml`). There is no stone entry yet (79 devices).
- A recent port's steps:
  1. confirm the model and the base OS, then check the unlocked bootloader;
  2. flash `boot`/`vendor_boot` downloaded from the port's releases, with SHA256;
  3. optionally resize logical partitions in fastbootd;
  4. format userdata ext4;
  5. reboot to recovery, `systemimage:install`.
- This port needs the **crDroid 14 vendor** (`vendor`, `odm` in `super`), so a user would have to install crDroid 14 first. Stock Xiaomi Android 14 firmware (HyperOS) as the base has not been tried. It would be the simpler requirement for users.

Planned steps:
1. Decide the base: crDroid 14 (tested) or stock Android 14 firmware (to test).
2. Write `stone.yml`:
   - codename and aliases for `sunstone`/`moonstone`;
   - the prerequisite step;
   - the boot image from a release.

   Needs items 1 and 7 (recovery, system image) first.
3. Test with the installer's `--file` option, then open a merge request.

## 9. Device page on devices.ubuntu-touch.io

Goal: the device appears on devices.ubuntu-touch.io.

What is seen:
- A device is a merge request to `ubports/infrastructure/devices.ubuntu-touch.io` adding `data/devices/<codename>/data.md` (name, specs, sources, contributors, links) and `releases/noble.md` (port type `Halium 14.0`, kernel version, feature matrix). Format: devices.ubuntu-touch.io/about/device-file.
- The matrix decides the shown stage ("Booting Device" … "Fully Optimized"). Its IDs:
  - **Actors:** `manualBrightness` `notificationLed` `torchlight` `vibration`
  - **Camera:** `flashlight` `photo` `video` `switchCamera`
  - **Cellular:** `carrierInfo` `dataConnection` `dualSim` `calls` `volte` `mms` `pinUnlock` `sms` `audioRoutings` `voiceCall` `volumeControl`
  - **Endurance:** `batteryLifetimeTest` `noRebootTest`
  - **GPU:** `uiBoot` `videoAcceleration`
  - **Misc:** `anboxPatches` `waydroid` `apparmorPatches` `batteryPercentage` `offlineCharging` `onlineCharging` `recoveryImage` `factoryReset` `rtcTime` `sdCard` `shutdown` `wirelessCharging` `wirelessExternalMonitor`
  - **Network:** `bluetooth` `flightMode` `fmRadio` `hotspot` `nfc` `wifi`
  - **Sensors:** `autoBrightness` `fingerprint` `gps` `proximity` `rotation` `touchscreen` `dt2w`
  - **Sound:** `earphones` `loudspeaker` `microphone` `volumeControl`
  - **USB:** `mtp` `adb` `wiredExternalMonitor`
- The page expects public sources (item 6) and, for most users, the installer (item 8). Without them it can still be listed with external links, but it would show as a port without a way to install.

Planned steps:
1. Fill the matrix from the hardware documents. Items 2 and 11 fill the unknowns. Each value cites its test.
2. Write `data.md` (Redmi Note 12 5G / POCO X5 5G specs, aliases) after items 3, 4 and 6.
3. Merge request, after the installer (or with "manual install" links if the installer is not ready).

## 10. The other stone variants

Goal: know what works on the SKUs this repository has not run on.

What is seen:
- Xiaomi ships three models on the stone device tree: one SM6375 (`moonstone`, POCO X5 5G) and two SM4375 (`sunstone`, Redmi Note 12 5G).
- The st21nfc driver names `moonstone_p_global` and `sunstone_global` as the NFC SKUs; this unit is `sunstone_cn`.
- Known differences: the SoC (moonstone), NFC, the third rear camera, and possibly display panels and fingerprint or touch vendors.
- Port pieces that depend on this unit's hardware:
  - the panel patches (`0001` reads Xiaomi's `ss-ea` flag; `0008` applies to any panel using the `BC_*HZ` commands);
  - `display-setup.sh`'s hash-gated patches;
  - the UCM profile (card `holiqrdsku1sndc`, mixer paths `qrdsku1`);
  - the camera and sensor configs;
  - the NFC drop-in (written for the variants, untested there).

Planned steps:
1. List per variant what the vendor selects by SKU (panels in the device tree, mixer paths, camera configs).
2. Find testers for `sunstone_global` and `moonstone`; give them the checklist from item 11.

## 11. Features not yet checked

From UBports' matrix and the hardware documents:
- `offlineCharging` (item 2), `recoveryImage` and `factoryReset` (item 1);
- `shutdown` and `rtcTime`: shut down, then boot and check the time (also offline);
- `batteryLifetimeTest`, `noRebootTest`, suspend and deep sleep: "Power" was skipped in `docs/roadmap-hardware-2.md` item 6 because it seemed fine; measure standby drain and uptime;
- `hotspot`, `flightMode`, `torchlight`/`flashlight`, `dt2w` (double tap to wake), `waydroid` (Android apps, a separate project), `wiredExternalMonitor` (USB-C display output, probably not on this SoC);
- calls on both SIMs at once;
- other Bluetooth headsets (only one was tested, for wideband).

## 12. Security: AppArmor mediation

Goal: confined apps are confined on D-Bus and Unix sockets too, as on UBports' supported devices.

What is seen (`docs/roadmap-hardware-2.md` item 8):
- AppArmor confines processes on this kernel (profiles load, the kernel log shows denials).
- But it has no D-Bus or socket mediation: there is no `/sys/kernel/security/apparmor/features/dbus`, and `SO_PEERSEC` gives no label.
- So dbus-daemon does not mediate D-Bus for confined apps, and services get no caller label (biometryd had to fall back to `/proc`).
- UBports' matrix tracks this as `apparmorPatches`. Halium kernels usually carry a backport of Ubuntu's AppArmor.

Planned steps:
1. Find the AppArmor backport other 5.4 Halium kernels use, and apply it as a kernel patch.
2. Check that `features/dbus` appears and that dbus-daemon then mediates, and test confined apps (Morph, camera, OpenStore apps) for new denials.

## Sources

- [UBports installer configs](https://github.com/ubports/installer-configs) (v2 schema, `Spacewar.yml`)
- [halium-generic-adaptation-build-tools](https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools) (`gsi-port-ci.yml`, `make-bootimage.sh`, `deviceinfo.sample`)
- [devices.ubuntu-touch.io source](https://gitlab.com/ubports/infrastructure/devices.ubuntu-touch.io) (`data/devices`, `portStatus.json`, `progressStages.json`)
- [UBports porting introduction](https://docs.ubports.com/porting/introduction/Intro.html) and [UBports installer porting notes](https://ubports-docs-dev.readthedocs.io/en/latest/_sources/porting/finalize/UBports_installer.rst.txt)
