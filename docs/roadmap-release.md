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

### What a boot was asked to be (2026-11-11)

The user reports that offline charging "already works". That alone does not say whether the phone charges with the system off (the PMIC and the bootloader charge without any boot), or whether it boots all of Ubuntu Touch while plugged in. The journal cannot tell: as `phablet` it shows only some boots, truncated. The bootloader passes its keys on the kernel command line only (no `/proc/bootconfig` on 5.4).

So `boot/ut-init/init` now appends one line per normal boot to **`/stone-boot-modes.log`** on the root filesystem (the last 50 boots are kept):
- `mode=`: `androidboot.mode` (`charger` for a charger boot, otherwise `none`);
- `force_normal_boot=`: the recovery flag;
- `pon=`: the PMIC's power-on reason from the kernel log, for example "Triggered from Hard Reset and 'cold' boot" (this boot). A charger insertion and a power key press are reported differently.

Recovery boots are not logged: they leave before the root filesystem is mounted. The ramdisk gained busybox `tail`, `cut` and `mv` for this.

First charger test (image `983f1711…`, 2026-11-11). The user powered off, plugged into the PC, and saw the charging animation; then the phone booted normally. `/stone-boot-modes.log`:

```
mode=none     force_normal_boot=y pon=Triggered from Hard Reset and 'cold' boot      (after flashing)
mode=charger  force_normal_boot=y pon=Triggered from CBL (External Power Supply) and 'cold' boot
mode=none     force_normal_boot=y pon=Triggered from Hard Reset and 'cold' boot      (right after it)
mode=none     force_normal_boot=y pon=Triggered from Hard Reset and 'cold' boot      (user's long-press reboot)
```

- The bootloader does pass `androidboot.mode=charger`, together with `force_normal_boot=1`. The power-on reason tells charger insertion (CBL) apart.
- **UT already has a charger mode.** `lxc-android-config` ships `lxc-android-config-charger-generator`: with `androidboot.mode=*charger*` it makes `charger.target` the default target. That target is only `sysinit`, `lxc-android-config` (the Android container, whose init draws the charger UI) and usb-moded; Lomiri and the session do not start.
  - In that mode `lxc-android-ready` remounts every filesystem read-only (`sysrq u`) against power cuts.
  - So our init needs no charger branch. It only has to stay out of the recovery branch, which it does.
- The charger boot ran about 13 s on USB (PC: usb-moded's fallback `04b9:0afe` from 20:09:38 to 20:09:51). Then came a reboot ("Hard Reset", most likely the power-key long press on the charger screen) into a normal boot.
- **The normal boot after the charger boot had no adb or MTP.** At init-done (about 17 s) usb-moded chose `charging_only` (`1209:0afe`, mass storage) instead of its configured `mtp_adb`, before the session started, so the session watcher saw no MTP mode and did nothing. The next boot (the user's reboot) was normal again. The early journal is lost again, so why is not known yet. A guess: usb-moded decided "wall charger, not PC" from the charger driver's reported type after a charger-mode boot.
- Not yet checked: whether the charger boot actually charges and at what current. The journal kept nothing from it.

Next: a trace across a charger boot and the boot after it (`tools/phone-debug/stone-boot-trace.sh` and `stone-boot-trace-install.sh`):
- usb-moded `-D`;
- USB gadget, usb-moded mode, the charger driver's `online`/`type`/`usb_type`, and the battery, whenever they change, for 120 s;
- in charger mode, written to `/dev/pmsg0` (pstore), because the filesystems are read-only there; the next normal boot copies `/sys/fs/pstore`.

Second charger test (2026-11-11): charger boot (`mode=charger`, CBL) for at least 2.5 min, then a long press into a normal boot. **adb worked**: the first failure did not reproduce.
- Normal boot: the charger driver reported `usb_type=SDP` (PC) throughout. `mtp_adb` came up at 18 s; the PC's libmtp reset came at 23 s; the watcher reconnected at session start (37 s) and again at the unlock (48 s).
- **The charger-mode trace was lost.** pstore was empty: the power-on reason is a "'cold' boot", which does not keep ramoops RAM. Charger-mode data has to come some other way. `sysrq u` only remounts filesystems with a block device, so `/run` stays writable: the trace now records to `/run` in charger mode and, after its 120 s, copies the result to `/var/log/stone-boot-trace/` with `/` remounted read-write for about a second (test only).
- **The battery was at 100 % (Full)**, so this test could not show charging in charger mode anyway.
- **usb-moded ran without `-D`.** An `EnvironmentFile=` wins over `Environment=`, and the image's `stone-sunstone.conf` now sets `USB_MODED_ARGS=`. The trace now writes `/run/usb-moded/zz-stone-debug.conf` (read last) in `ExecStartPre`, before usb-moded starts.
- In upstream usb-moded, `set_mode` only stores the requested mode in memory (`control_set_selected_mode`), so the watcher cannot change what a later boot selects. But `set_mode` is **rejected while usb-moded is "busy"** (and when the cable is not seen as a PC). The watcher tried to switch back to the original mode only once, so a rejection would have left the phone in `charging_only` for the whole session. It now retries up to 10 times. Live test from `/usr/local/lib/stone-test/` through a user drop-in, because the image's overlay restores `/usr/lib/stone/usb-mtp-reconnect.py` at every boot.
- The init's cleanup list now includes all of these test files.

Third charger test (2026-11-11): **no adb reproduced on the first try** (charger boot about 2 min, then a long press). The charger-mode trace saved nothing: the boot ended before its 120 s were up (now 60 s).

Cause, from usb-moded's `-D` log of the normal boot after it:
- The charger driver reported `usb_type=SDP` (PC) throughout, so **the cable was not mistaken for a wall charger**; that guess was wrong.
- At init-done (16.9 s) usb-moded chose `mtp_adb` and started `adbd.service` (appsync `systemd_wait`). At 17.25 s, right after systemd reported adbd started, it bound the UDC: `UDC: write failure: No such device`, then "mode setting failed, try charging_only". It stayed in `charging_only` for the session. The session watcher (MTP modes only) and the user's unlock did not change that; a replug did.
- `adbd.service` is `Type=notify`. adbd reports ready at "adbd started", before its USB thread opens `/dev/usb-ffs/adb/ep0` and writes the FunctionFS descriptors. A UDC bind while an FFS function has no descriptors fails with `ENODEV`.
  - In the failing boot, the bind came about 5 ms after "opening control endpoint".
  - In the good boot the order happened to be the other way round.
- It is a race in UBports' adbd unit, not stone-specific (item 5). It shows up after charger boots, presumably because of their timing.

Fix: **`etc/systemd/system/adbd.service.d/zz-stone-ffs-ready.conf`**:
- `ExecStartPost` waits, at most 5 s and never failing the unit, until `/dev/usb-ffs/adb/ep1` exists. FunctionFS creates the endpoint files once the descriptors are written, which is when a bind can succeed.
- systemd completes the start job only after `ExecStartPost`, so usb-moded's wait now covers the descriptors.
- `$` is escaped as `$$` for systemd.
- Live install with `stone-boot-trace-install.sh` (same path as in the image).

Charging in that normal boot: 92 %, `Charging`, about 420–435 mA from the PC (SDP).

Fix test (2026-11-11): the user ran several charger → long-press → normal cycles, and adb was there every time.
- `/stone-boot-modes.log` holds four `mode=charger` (CBL) boots, each followed by a normal boot.
- In the traced normal boots, no `UDC: write failure`, and `mtp_adb` came up at init-done; that held for both adbd starts (init-done at about 16.5 s, the watcher's reconnect at about 37.7 s).
- adbd's `ExecStartPost` ran with `status=0` and added about 46 ms between the main process start and "started".
- **Charger mode, traced** (`2-charger`): `charger.target` only, no Lomiri or lightdm in the journal, `Charging`, about 356–364 mA into the battery at 92 % and 4.37 V from the PC.

**Offline charging works as intended**:
- the bootloader's `androidboot.mode=charger` → `charger.target`;
- the Android container's charger UI;
- charging;
- a long press boots normally, now with adb and MTP.

Not checked: a wall charger (DCP) in charger mode, and the screen and power behaviour over a long charge.

**Image** `out/halium14/boot-ut.img` SHA256 `7593d35ca9945681379266b050146f9d2ea23f8a84b3170120afde749d9f875b`, kernel `#17` (unchanged). Compared with `983f1711…` it adds:
- the adbd `zz-stone-ffs-ready.conf` drop-in;
- the watcher's retry when switching back;
- the init cleanup of the charger-test files: the trace, the debug drop-in, the test watcher and its drop-in.

Not yet written. `983f1711…` is kept as `out/halium14/boot-ut-983f1711.img`.

### USB with the cable plugged in at boot (2026-11-11)

User: **adb never works when the phone boots with the USB cable plugged in**; it needs an unplug and a replug. This is not a hardware problem. It is usb-moded's **rescue mode**, a UBports default that is wrong for a port that boots.

What is seen:
- UBports' `usb-moded.service` sets `Environment=USB_MODED_ARGS=-r`, and ports turn it off from `/etc/default/usb-moded.d/*.conf` (UBports' `device-specific-config.conf`: "Uncomment this to disable usb-moded's rescue mode. Only do this if you're sure your device will boot.").
- With a cable plugged in when usb-moded starts, rescue mode puts the gadget in `developer_mode` and keeps it there until the cable is unplugged. That mode is RNDIS only: the phone is at `10.15.19.82`, and there is no adb.
- Boot with the cable in (image `2708ccaf…`, usb-moded running `-r`):
  - the PC got UBports' RNDIS identity `1209:0004` (`lineage_stone`, serial `stone`) and a "Wired connection" with `10.15.19.2`;
  - `adb devices` was empty;
  - the phone answered ping on `10.15.19.82`, but ssh is off, so there was no way in.
- **The Type-C side is fine.** The kernel log of that boot shows `PowerOffCharge`, `Attached.SNK` at 1.7 s, and the gadget `CONFIGURED` at 13 s.
- A first guess blamed the Type-C controller. It came from reading `[CC_Alert] 15/15` and `Unattached.SNK` as the boot state, but those lines are what an unplug looks like. A boot service that redid Type-C detection was written and tested: it found the partner present and did nothing. It was removed again (the init deletes its files from the root filesystem).

Fix:
- `USB_MODED_ARGS=` (empty) in the overlay's `etc/default/usb-moded.d/stone-sunstone.conf`. The phone boots reliably, and when it does not, the recovery (item 1) gives adb.
- Live test: first `stone-usb-rescue-off-install.sh`, now part of `tools/phone-debug/stone-usb-install.sh`.
  - A first live test changed `stone-sunstone.conf` on the phone, and usb-moded still started with `-r`. The initramfs copies the boot image's overlay over the root filesystem on every boot, so image `2708ccaf…` put its old copy of the file back (138 bytes, dated 1970).
  - So the live test uses a drop-in the current image does not ship: `/etc/systemd/system/usb-moded.service.d/zz-stone-test-no-rescue.conf` with `Environment=USB_MODED_ARGS=`, read after the unit's `-r`. The next image's init deletes that drop-in. The image's own fix is the `stone-sunstone.conf` line.

Test with rescue mode off (drop-in, 2026-11-11):
- The RNDIS "Wired connection" is gone, but **adb and MTP still need a replug**. The PC's file manager: "Could not access device…".
- usb-moded ran without `-r`. adbd and mtp-server were running before the replug (systemd stopped them at the replug).
- Phone gadget events lined up with the PC's kernel log (the boot started at about 19:32:49):

  | Phone uptime | Phone | PC |
  |---|---|---|
  | 13.1 s | first gadget config | `04b9:0afe` USB mass storage: usb-moded's charging fallback ("in bootup; dynamic modes blocked") |
  | 15.6 s | `/run/systemd/boot-status/init-done` written | |
  | 16.7 s | mtp_adb configured | `1209:0003` (mtp_adb) |
  | 21.7 s | disconnect, connect, configured, all within about 240 ms | only "reset high-speed USB device", **no re-enumeration** |

- Nothing changed after that until the replug, which brought adb and MTP up at once.
- In upstream (Sailfish) usb-moded, `usbmoded_can_export()` is always true without `MEEGOLOCK`, and this build has no devicelock. So the screen lock does not gate the mode.
- The step at 21.7 s was first read as usb-moded reacting to the user session. The instrumented boot below showed it is the PC resetting the device.

Instrumented boot (`stone-usb-boot-trace.sh`: usb-moded `-D`, journal, gadget state every 0.2 s):
- **The phone changes mode only once:**
  - 13.3 s: `charging_only` (mass storage, `0afe`);
  - 16.5 s: init-done arrives as the D-Bus signal `com.nokia.startup.signal.init_done`, and `usb-rescue-mode-off.service` runs;
  - 16.8 s: usb-moded starts `adbd.service` (appsync), then sets `ffs.adb,mtp.mtp` and `0003` and binds the UDC;
  - 17.4 s: adbd has `FUNCTIONFS_ENABLE`, and its transport is up.
- **mtp-server starts only at 32.6 s.** It is a user-session service, started by `mtp-server-usb-moded-watcher` once the session is up.
- In between, the PC's KDE MTP backend opened the new device (`mtp-probe`: "was an MTP device") and got no answer. Five seconds later it logged `LIBMTP libusb: Attempt to reset device`; the kernel logged "reset high-speed USB device".
- On the phone that reset is the 22.6 s step: the UDC state goes `default` → `configured`, with no mode change. adbd logs `FUNCTIONFS_DISABLE`, "connection terminated", and never re-arms (no `FUNCTIONFS_ENABLE` afterwards). The PC's MTP backend has given up by then.
- **A replug works** because by then mtp-server is already running: the watcher restarts it within about 1.5 s, inside libmtp's 5 s timeout.
- Rescue mode is a separate problem. UBports' `usb-rescue-mode-off.service` clears it at init-done, but usb-moded stays in a rescue mode it has already entered "until something else is explicitly requested / cable is detached". So `-r` still has to go.

So: **the phone exposes MTP about 15 s before anything answers it, and a PC that probes MTP at once resets the device and breaks adb.** This is not stone-specific. It is a UBports usb-moded/mtp-server ordering problem and belongs in item 5. A PC without an MTP backend that probes immediately may not see it.

First fix, a system service that reconnected once mtp-server was up (`usb-mtp-reconnect.sh`, test of 2026-11-11):
- **adb now works without a replug.** The user saw adb briefly early in the boot, then gone, then back: that is adb before the PC's libmtp reset, and after the reconnect at 34 s.
- The PC saw a real disconnect and a new `0003` device, and there was no second libmtp reset.
- **MTP still failed** with "Could not access device… make sure it is unlocked", although the phone was unlocked. `kioclient ls mtp:/lineage_stone/` gives the same message.
  - KDE's `kmtpd` held the device (`/modules/kmtpd/device0`) with **no storages**. That message is KIO's text for a device without storages.
  - mtp-server never logged the requests.
  - UBports' mtp-server watches `com.lomiri.LomiriGreeter` `IsActive` on the session bus, and adds its storages only when the greeter goes inactive ("device is not locked, adding storage").
  - PC-side MTP clients read the storage list once, when the device appears. A PC that connects while the phone is locked therefore never sees the storages after the unlock. Android re-enumerates on unlock and "Allow"; UBports does not.
  - So this is not only a boot problem: **plugging into a PC while locked** should behave the same. That is another usb-moded/mtp-server issue for item 5.

Fix: **`usr/lib/stone/usb-mtp-reconnect.py`**, a user-session service (**`etc/systemd/user/stone-usb-mtp-reconnect.service`**, in `ubuntu-touch-session.target` like UBports' `mtp-server-usb-moded-watcher`):
- It does a software replug: usb-moded `set_mode` `charging_only`, then back to the same mode. The D-Bus policy allows `set_mode` for any user.
- It does this once at session start, if a PC is attached in `mtp` or `mtp_adb` mode (the boot case: the PC met no mtp-server, and its libmtp reset broke adb).
- And on an unlock, if a PC got the MTP device while the phone was locked, 1.5 s after the unlock so mtp-server has added its storages.
- With no PC attached, or in other modes, it does nothing.
- The system service from the first fix is gone; the init deletes its live-installed files.
- Live test 2026-11-11, started with `systemd-run --user` on the running phone (locked, PC attached): the start reconnect ran (`mtp_adb` → `charging_only` → `mtp_adb` in 2 s) and adb came back. KDE then had the device with no storages, as expected while locked.
- After the unlock, MTP worked (user).
- After a reboot MTP failed again, but adb worked. Expected: the watcher had only been started by hand, so that boot ran the earlier system service instead.
- Live install for the boot test: `tools/phone-debug/stone-usb-install.sh`. It installs the drop-in without rescue mode and the user watcher, and removes the boot trace, the system service and the Type-C test.
- Boot test with that installed (cable in, 2026-11-11): passed. adb came up without a replug; after the unlock, one USB reconnect, then MTP opened without a replug.
- **Image** `out/halium14/boot-ut.img` SHA256 `983f1711496c92325e1f41b6d42b6d4c7a19aac03033a4bb6d9aeb7a5ee8c30f`, kernel `#17` (unchanged). It carries:
  - `USB_MODED_ARGS=` in `stone-sunstone.conf`;
  - the session watcher;
  - the boot-mode log (`/stone-boot-modes.log`), with busybox `tail`, `cut` and `mv` added to the ramdisk;
  - init cleanup of the test files (the drop-in, the trace, the system reconnect service, the Type-C test).

  Not yet written. The previous image is kept as `out/halium14/boot-ut-2708ccaf.img`.

Also seen: the **system journal keeps only a boot's last part**. A boot with the cable in kept 75 system entries, none before the NTP sync at 42 s, while `/var/log/journal` holds many 8 MB `user-32011@…` files. It is likely journald rotation and vacuuming confused by the 1970 RTC time before the sync. Not investigated yet; it matters for bug reports (item 11).

A different bug, seen while installing this: **adbd sometimes segfaults on `adb push`**. A directory push, or a few file pushes back to back, gives `adbd.service: Main process exited, code=killed, status=11/SEGV`. systemd restarts it, and USB came back without a replug about 40 s later. The Type-C state does not change. Not investigated yet. It is UBports' adbd, so it belongs with item 5 once it can be reproduced.

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
