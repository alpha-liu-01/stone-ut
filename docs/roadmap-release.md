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
13. Bluetooth: turning Bluetooth off and on, and reconnecting.
14. System journal: the start of every boot is lost.
15. Android log (logcat) reads back empty.
16. Top panel: an indicator sits on the front camera.

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

The user entered the recovery (`sudo reboot recovery` in Ubuntu Touch); `adb devices` showed the phone in recovery. The only visible problem was very small text. Checked over adb (root):
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
  - the PC got UBports' RNDIS identity `1209:0004` (`lineage_stone`, the bootloader serial) and a "Wired connection" with `10.15.19.2`;
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
- **Personal data:** removed from the tree on 2026-11-12. See the notes below. The email in two patch headers was left (normal for authored patches; the user's choice). Phone numbers and coordinates are only in `out/` (ignored).
- **History:** rewritten in the same pass, so the removed identifiers are not in any commit. The remote still has the old history until it is force-pushed; that push has not been done.
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

### Implementation notes

2026-11-12, steps 1 and 2:

- Docs no longer record the SIM identity, the device serial, or the Bluetooth adapter address (either byte order). No separate earbud address was in the tree; the hardware notes only had the phone adapter.
- The six init scripts (`boot/ut-init/init`, `init-disk`, `init-logs`, and the three under `boot/droidian-init/`) take the USB gadget serial from `androidboot.serialno` on the kernel command line. If the bootloader does not pass one, the serial is `stone`.
- History was rewritten with `git filter-repo` so those values are not in any commit. Reflogs were dropped and unreachable objects were pruned. Nothing was pushed. The patch-header email was not changed.

2026-11-12, steps 3 to 5:

- **Step 3:** `README.md` (what it is, status, variants, build, layout), `docs/install.md` (crDroid 14 v10.11 first, then `userdata` and `boot`, then `resize2fs`; recovery; going back), `LICENSE` (GPL-3.0, the user's choice; item 4, step 3) and `NOTICE` (the parts with other licences, and what the boot image combines).
- **Step 4:** `tools/fetch-inputs.sh` fetches and checks every input. `build.sh` is the entry point: `kernel`, then `rootfs`, then `boot`, or `all`.
  - Pins (SHA256, unchanged from the files used so far):
    - crDroid zip (SourceForge);
    - rootfs: UBports CI `ubuntu-touch-rootfs/ubports/24.04-2.x` build 154 (Jenkins' fingerprint of our file);
    - Halium: `halium-14.0` build 594 (identical to 586, its first build, and to 595–596);
    - recovery ramdisk: build 596 (identical to 595);
    - gcc 13.3.0 (kernel.org crosstool);
    - busybox (Alpine `busybox-static` 1.37.0-r31);
    - the kernel at `42e99ef7` (a `--depth 1` fetch of the commit, 1.5 GB).
  - The unpacked `android-rootfs.img` is checked too (`12d1606e…`).
  - **Upstream does not keep these files.** On 2026-11-12, rootfs build 152 already returned 404 (154 will follow within days), Halium 557 too, and Alpine no longer has busybox r31 (v3.23 has r30, edge 1.38.0).
    - The script falls back to a GitHub release of this repository, `inputs-2026-11` (`STONE_MIRROR` overrides). It mirrors the rootfs, Halium, the recovery ramdisk and busybox, and accepts any file only if its checksum matches.
    - `sh tools/fetch-inputs.sh --mirror-files DIR` stages the four assets with a `SHA256SUMS`. The user created the release on 2026-11-12. All four assets, downloaded with `gh release download`, match their SHA256. **The repository is still private**, so the script's anonymous download gets a 404 until it is public; until then a new machine has to fetch busybox with `gh`.
  - `build.sh kernel`:
    - Compares the kernel tree with the commit plus `kernel/patches/` (git trees built in temporary indexes, work tree untouched). It applies the patches to a clean checkout, accepts an already patched one (this machine's tree is), and refuses anything else.
    - Generates `moonstone_defconfig` plus the fragment in a scratch directory and copies it only if it changed.
    - Builds `Image modules` with clang 21 and `KCFLAGS=-Wno-implicit-enum-enum-cast`.
  - `tools/fetch-recovery-ramdisk.sh` now calls `fetch-inputs.sh recovery`.
  - Tested on 2026-11-12:
    - In an empty directory: the recovery and toolchain downloads, the kernel fetch, and a full kernel build. The patches applied cleanly; `.config` is identical to `kernel/build-14/.config`; the `hci_vhci.ko` vermagic is the same; the Image is 48130560 bytes like `#18`. A second run changed nothing (same Image SHA256).
    - The busybox download failed as expected (no release yet), with the message to place the file by hand.
    - In this checkout: `sh build.sh boot` gives `16bfa7b0…`. Its kernel and recovery files are identical to `2edde0c6…` (item 16). Its ramdisk differs only in `init`'s USB serial (steps 1 and 2; the bootloader passes `androidboot.serialno`, checked on the phone).
  - The kernel banner records the builder (`user@host`). `build.sh` now sets `KBUILD_BUILD_USER=stone` and `KBUILD_BUILD_HOST=stone-ut` (both overridable); checked with a stub `make`. Kernels up to `#18` still carry the old names; the next kernel build is the first without them.
  - **Image** `16bfa7b0531b411058fde6edaef43400b362b8428d3960cc15786a44c5229ce6` (`out/halium14/boot-ut.img`, copy `boot-ut-16bfa7b0.img`) replaces `2edde0c6…` as the image to flash (the user's choice). Written and confirmed on 2026-11-12: kernel `#18`, `stone.yaml` with the cutout settings, and `/usr/bin/logcat` on the phone.
- **Step 5:** archived, not deleted (the user's choice). `archive/README.md` explains what is there.
  - `boot/droidian-init/` → `archive/droidian-init/`, except `reboot-bootloader.c`, which moved to `boot/ut-init/` (the `trace` and `disk` images build it).
  - The 13 `tools/phone-debug/*-install.sh` live-install scripts and `stone-boot-trace.sh` → `archive/phone-debug/`; their fixes are in the image. The diagnostics stay in `tools/phone-debug/`.
  - The roadmaps keep the old paths, as a log.

## 4. Sources the licences require

Goal: anyone who gets a boot image can get its corresponding source.

What is seen: the boot image contains:
- the Linux kernel (GPL-2.0), crDroid's tree plus `kernel/patches/0001`–`0010` (`0010` since kernel `#18`) and `kernel/config/halium-sunstone.fragment`;
- busybox (GPL-2.0, `third_party/busybox-aarch64`);
- the overlay. Its programs, with their sources:
  - biometryd and its library (GPL-3.0/LGPL-3.0): built by `tools/biometryd/build.sh` from upstream plus a patch;
  - the patched UBports binaries built by `build-boot-image.sh` (telephony-service handler, media-hub, Halium's `libaudioclient.so`): patch scripts in `tools/`, applied to exact upstream versions;
  - the runtime-patched Mir platform: `display-setup.sh`, with the source patch in `tools/upstream/`.

Planned steps:
1. Publish a kernel fork: crDroid's commit plus the patches as commits, plus the config fragment. Tag every release with the boot image it went into.
2. Record each distributed binary's upstream source and version next to it (busybox version, biometryd commit, the UBports package versions the patch scripts check). Add license texts.
3. Choose a licence for this repository's own scripts. GPL-3.0 matches most UBports components; ask the user.

2026-11-12: step 3 done. The user chose GPL-3.0 (`LICENSE`); `NOTICE` lists the parts under other licences. The input mirror (item 3, step 4) redistributes the UBports rootfs, the Halium image, the recovery ramdisk and busybox. Those carry GPL parts, so their sources have to be offered as well. UBports publishes the package sources; busybox 1.37.0's source and Alpine's build recipe should go with the release.

2026-11-12, steps 1 and 2:

- **Step 1, kernel fork.**
  - `kernel/patches/0001`–`0010` are now `git format-patch` files: author `alpha-liu-01` with the GitHub noreply address, dated when each patch entered this repository, and each with a commit message. The messages were written from the roadmap entries and checked against the diffs. The diffs are unchanged (same `git patch-id` for all ten), so `build.sh` and `git apply` work as before, and `build.sh` still recognises this machine's tree as "commit plus patches".
  - `tools/make-kernel-fork.sh DIR [TAG]` makes a worktree of the kernel checkout on the branch `stone-ut`:
    - base `42e99ef7`;
    - `git am` of the ten patches (committer = author, committer date = author date);
    - one commit adding the fragment as `arch/arm64/configs/halium-sunstone.fragment`, dated by the fragment's last change here.
  - The same inputs give the same hashes: two runs gave tip `4880119163f88ac5a62aa1a1a020fded1b870413`.
  - The tree before the fragment commit is exactly this machine's patched tree (`49cd98c4…`). That is kernel `#18`'s source: `hci_core.c` (0010) was last changed at 22:04:52, before `#18` was built at 22:05:16. `hci_event.c` is newer only because 0011 was reverted, and the tree still equals commit plus 0001–0010.
  - The branch `stone-ut` and the tag `boot-16bfa7b0` exist in `third_party/android_kernel_xiaomi_sm6375` only. **Not pushed:** publishing needs a public GitHub fork of `crdroidandroid/android_kernel_xiaomi_sm6375` (forks of public repositories are public), which the user decides.
  - Tag scheme: `boot-<first 8 hex of the boot image's SHA256>` on the commit whose kernel went into that image.
- **Step 2, sources and licence texts.**
  - `SOURCES.md` lists every binary the boot and userdata images ship, with its upstream, exact version, SHA256 and licence: the kernel and `hci_vhci.ko`; busybox; the recovery ramdisk; the three patched UBports binaries; the boot-time Mir patch; biometryd; the copied data files; the rootfs and Halium images.
  - It also records the CI builds' source revisions, read from Jenkins:
    - `generic_arm64` `halium-14.0` at `9a95607a…` and `halium-build-tools` at `96088c8f…` (Halium 586/594/596);
    - `rootfs-builder-debos` at `608c8ff0…` and `build-tools` at `63470907…` (rootfs 154).
  - busybox r31 is Alpine aports commit `c3ef5d10e6ef…` (pkgrel 31, 2026-01-10, the build date in the binary's banner). `busybox-1.37.0.tar.bz2` matches the SHA512 in its APKBUILD. Both are staged for the `inputs-2026-11` release; not uploaded yet.
  - `licenses/` holds GPL-2.0, LGPL-3.0 and Apache-2.0 (GPL-3.0 is `LICENSE`); `NOTICE` and the README point to it and to `SOURCES.md`.
  - Licences checked: `media-hub` LGPL-3.0, `lomiri-telephony-service` GPL-3 (`debian/copyright`); `mir-android2-platform` GPL-3.0/LGPL-3.0, with the patched `real_hwc2_wrapper.cpp` LGPL-3.0.
  - Found on the way: `usr/share/stone/{audio_policy_configuration,r_submix,tables,volumes,bluetooth}.xml` are no longer used. Their only reference is the commented-out `module-droid-card-28` line in `stone-touch.pa`. They can be removed from the overlay.
  - The licence texts are not in the boot image itself. A release of the image should carry `LICENSE`, `licenses/`, `NOTICE` and `SOURCES.md` next to it.

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

## 13. Bluetooth: power off and reconnect

User (2026-11-11), earbuds Moondrop Nekocake (paired, `Trusted: yes`):
1. "Connect automatically when detected" does not work: take the earbuds out, turn Bluetooth on, nothing happens; a manual connect works.
2. Turning Bluetooth off with the earbuds connected does not disconnect them, and turning it back on does not recover the connection. The device page's "Disconnect" works.

What is seen:
- BlueZ 5.85, default `main.conf`. The adapter is `connectable`. "Connect automatically when detected" is BlueZ's `Trusted`.
- **The toggle is an rfkill block, not BlueZ's `Powered`.** `ayatana-indicator-bluetooth` uses a `/dev/rfkill` killswitch when one exists. Here there are two Bluetooth switches: `bt_power` (the chip's power driver) and `hci0` (the vhci device that bluebinder proxies to the Android HAL). `urfkilld` also runs.
- Kernel 5.4 `hci_rfkill_set_block()` calls `hci_dev_do_close()` at once. That drops connections on the host side only: no HCI Disconnect, and page scan stays enabled. BlueZ's own power off (mgmt) disconnects every link first, which is why "Disconnect" and `Powered=false` are clean.
- Trace of the user's test (journal; the btmon trace script stopped early because of its own `set -e`, now fixed):

  | Uptime | Event |
  |---|---|
  | 966.2 s | Bluetooth off. BlueZ drops its side; `hfp_ag` "not connected". |
  | 967.4, 968.4 s | bluebinder: "Writing packet from HAL to vhci device failed: No such device or address". The controller still sends traffic for the earbud link. |
  | 975.3 s | on |
  | 1001.5 s | the earbuds reconnect, 26 s later (the user saw them disconnect, then connect) |
  | 1034.1 s | off, with the earbuds in the case |
  | 1034–1047 s | more HAL packets to the closed host while the earbuds came out |
  | 1060.7 s | on |
  | 1082.4 s | the earbuds connect, 22 s later (user: "roughly 30 seconds") |
  | 1123.5 s | control: Bluetooth on, earbuds from case to connected in under 5 s |

- So "off" only closes the host side. The Qualcomm controller behind bluebinder stays powered: it keeps the earbud link (issue 2) and keeps taking connection requests nobody answers, so the earbuds back off (issue 1, 20–30 s once Bluetooth is back on). Turning it on resets the controller (the kernel's HCI Reset at init), which ends the stale link.
- BlueZ itself does not connect anything when the adapter is powered on; it only reconnects after a link loss. Android connects the last devices on Bluetooth on.

Fixes:
- **`kernel/patches/0010-bluetooth-disconnect-links-before-rfkill-close.patch`** (kernel `#18`, Image SHA256 `2d65575614ff4f587f739906adc2f63824b5ef1b127f2dc86477d8bc70f55063`; `#17` kept as `out/halium14/Image-17`). Before an rfkill block closes the device, `hci_rfkill_quiesce()`:
  - writes Scan Enable off (BR/EDR);
  - sends HCI Disconnect (reason 0x15, remote power off) for every connected ACL and LE link;
  - waits up to 2 s for the Disconnection Complete events, then closes as before, and logs whether links were left.
  This is what a mgmt power off does.
- **`usr/lib/stone/bt-autoconnect.py`**, `stone-bt-autoconnect.service` (wanted by `bluetooth.service`). When the adapter powers on, and at start:
  - it connects (`Device1.Connect`) the paired, trusted, unblocked audio devices that were connected when Bluetooth went off. That counts devices that disconnected up to 5 s before the power off, since the kernel now disconnects first.
  - Otherwise it connects the last audio device used (`/var/lib/stone/bt-autoconnect.json`).
  - It tries once, plus one retry after 10 s; a device that is not around then connects by itself.
  - A device the user disconnected (`Device1.Disconnected` with a `.Local` reason, Bluetooth still on 5 s later) is taken off the list.
- Live test of the service (2026-11-11): started with `systemd-run --user` (BlueZ's D-Bus policy allows any user). It found the earbuds connected and stored them as the last device.
- Test image `out/halium14/boot-ut-test-k18.img` SHA256 `e596cbec340b8aad872aa16bc7f522ca3becc53812c7b2e65cb32135714529a7`: kernel `#18`, plus the service, on top of the overlay of `7593d35c…`. That image is what runs on `boot_b`; the local copy of its file was overwritten by this build. `out/halium14/boot-ut-983f1711.img` (kernel `#17`) is the kept fallback.

Test of `e596cbec…` (2026-11-11; trace `bt-trace-1`):
- **Bluetooth off now disconnects the earbuds** (user: step 3 passes). Kernel: `hci0: rfkill: no links left after disconnect`, both times.
- **On reconnects them**: off at 99.7 s, on at 103.7 s, the service's `Connect` done at 105.7 s.
- Earbuds out of the case while Bluetooth was off, then on: connected at 170.1 s, but **about 10 s after the user's toggle** (user: "a bit slow").
  - The unblock was at 153.9 s, and the adapter only came back at 166.7 s.
  - At the unblock bluebinder logged "binder transaction has failed: status = 2", "Remote has died, trying to reconnect", "Turning bluetooth off", and exited.
  - systemd restarted it, `hci0` was unregistered and registered again (URfkill "removing killswitch idx 3 hci0"), bluetoothd "Failed to set mode", and the A2DP endpoints were dropped and re-added.
  - So the Android Bluetooth HAL died while Bluetooth was off (21 s that time). It did not die during the 4 s off in step 3. Why is not known yet: logcat needs root.
- **"Disconnect" on the device page did nothing.** There is no Disconnect in bluetoothd's log at all. Likely System Settings held the device object from before `hci0` was re-created. Not confirmed yet.
- Service bug: the power-off disconnect at 99.7 s was taken for a user "Disconnect" ("was disconnected by the user") when its 5 s check ran at 105 s, with Bluetooth already back on. The device was then connected anyway (the power-on list had been taken before) and re-remembered. Fixed: the service now records when the adapter powered off and ignores local disconnects within 1 s of that.
- At first boot the service had no stored "last device" yet ("reconnecting: nothing"); the earbuds connected by themselves at 89.6 s.

Follow-up (2026-11-11):
- With the service's fix installed live, the user's Disconnect (System Settings reopened) **worked**. So the earlier "Disconnect does nothing" was System Settings holding a device object from before bluebinder re-created `hci0`; it follows from the HAL death.
- But the service did not see that Disconnect as a user action. A Disconnect sent through BlueZ (`busctl … Device1 Disconnect`, then `Connect` again) gave `Device1.Disconnected` **`org.bluez.Reason.Remote`**, "Connection terminated by remote user".
  - BlueZ disconnects with HCI reason 0x13, and this controller echoes 0x13 in Disconnection Complete instead of 0x16 (local host). Kernel 5.4 maps the event's reason only (`hci_to_mgmt_reason()`).
- **`kernel/patches/0011-bluetooth-report-host-initiated-disconnect-as-local.patch`** (since removed, see below) (kernel `#19`, Image SHA256 `9bfc1b6176012844cdd53d205ba73937287a7d5b5740b6015f5e13f389b46dfb`; `#18` kept as `out/halium14/Image-18`). In `hci_disconn_complete_evt()`, a connection in `BT_DISCONN` (this host sent HCI Disconnect) is reported as `MGMT_DEV_DISCONN_LOCAL_HOST`.
  - The kernel's own idle disconnect (after the last L2CAP channel closes) also counts as local. Still to check: which reason earbuds going into the case produce. If that comes out as local, the service would forget them.
- `logcat` gives nothing from the host, even as root: logd is only reachable inside the container. `tools/phone-debug/stone-bt-step.sh` now runs `lxc-attach -n android -- logcat` and copies tombstones and the bluebinder journal into `/home/phablet/bt-hal-log/`.
- **The HAL death** (step 4 above):
  - Android's init restarted `android.hardware.bluetooth@1.0-service-qti` at about 148 s, 17 s after the power off (131.0 s) and before the unblock.
  - At the unblock (152.8 s) bluebinder still held the dead HAL and failed. Its own reconnect took 10 s ("Connected to HIDL" at 163.06 s); then it exited, systemd started a new one, and `hci0` was re-created at 166 s.
  - The tombstones are old (camera provider, 2026-11-10); none is from the Bluetooth HAL.
  - Not reproduced since, in three tries of the same sequence (earbuds into the case, off, out, 25 s, on) and one 30 s off with the earbuds connected: reconnect in 2–3 s each time, same HAL pid throughout.
  - `logcat` gave 0 lines with rc 0, both through `lxc-attach` and `-d`, so the cause is unknown. `tools/phone-debug/stone-logcat-check.sh` tries each way of reading it.
  - Also seen: while Bluetooth is off, bluebinder still logs "Writing packet from HAL to vhci device failed" now and then (1334 s, 1404 s). The controller still sends something up after the quiesce, which only stops BR/EDR scanning.
  - Open, intermittent.
- Test image `out/halium14/boot-ut-test-k19.img` SHA256 `a6d77dbe6aca93f336dce979d826c64bf13a4e8455c875c86d9e795b1af5ff2c`: kernel `#19` (patches 0010 and 0011, 0011 removed since; see below), plus the service with the power-off fix.
- With `a6d77dbe…`: **the earbuds did not connect after boot** (manual connect worked).
  - The service started at 18 s, together with bluetoothd. Its log is lost with the first 42 s of the journal.
  - At boot the adapter appears late (bluebinder waits for the HAL; about 76 s in an earlier boot). The service only acted on a `Powered` false → true change, or on an adapter that was already powered when it started. An adapter that bluetoothd exports already powered gives neither, so nothing connected.
  - Fixed: when `Adapter1` appears powered, or powers on within 5 s of appearing, the service waits 3 s for the paired devices to be exported, then acts as on a power on (unless something connected by itself).
  - Adapter removal (bluebinder re-creating `hci0` after a HAL death) now counts as a power off, so the devices connected then are reconnected when it comes back.
  - It also logs its start state.
  - Live test: `tools/phone-debug/stone-bt-autoconnect-test.sh` runs it from `/usr/local/lib/stone-test/` through a drop-in (the image restores `/usr/lib/stone/` at boot), and restarts bluebinder to re-create `hci0`.
- Live test of that fix (2026-11-11):
  - Reboot with the earbuds out: the service started at 73.9 s (no adapter yet); the adapter appeared at 76.6 s (unpowered) and powered on at 80.0 s; connect at 81.0 s, **connected at 81.8 s**.
  - bluebinder restart: adapter removed → "powered off; were connected: Moondrop Nekocake" → appeared → reconnect. Both attempts failed with `br-connection-page-timeout`; the earbuds then reconnected by themselves. An abrupt loss (no HCI Disconnect) leaves the remote believing it is connected until its supervision timeout, often about 20 s. The service now makes 3 attempts, 10 s apart.
- **Patch 0011 did not help, and was removed.** With kernel `#19`, a `Device1.Disconnect` still gave `org.bluez.Reason.Remote`.
  - BlueZ's Disconnect closes the profiles first and only sends the HCI Disconnect after a 2 s timer. These earbuds drop the link themselves as soon as the profiles are closed, so the disconnect really is remote at the HCI level; no reason mapping can show a user's Disconnect.
  - 0011 is reverted in the tree and its patch file deleted. The image goes back to kernel `#18` (`out/halium14/Image-18`, copied to `kernel/build-14/arch/arm64/boot/Image`). The objects in `kernel/build-14` are still `#19`'s, so the next incremental build rebuilds `hci_event.o` and is numbered `#20`.
- Instead, the service now watches the calls themselves: a second system bus connection with `org.freedesktop.DBus.Monitoring.BecomeMonitor` for `org.bluez.Device1` `Disconnect` and `DisconnectProfile` (both used by System Settings' Bluetooth panel). This needs root, which the service has.
  - 5 s after such a call, if the device is still disconnected and Bluetooth is on, the device is dropped from the "last used" list.
  - The `Disconnected` signal and its reason are no longer used.
- Live test of the monitor (2026-11-11; `stone-bt-autoconnect-test.sh --no-restart`, kernel `#19` still running):
  - It started without the "cannot watch" warning.
  - `Device1.Disconnect` via `busctl` (as phablet): 5 s later "Moondrop Nekocake was disconnected by the user; not reconnecting it", and the list became empty. `Connect` put the device back.
  - BlueZ power off and on (`Adapter1.Powered` false, then true, via `busctl`): "powered off; were connected: Moondrop Nekocake", "powered on; reconnecting", connected on the first attempt; the device stayed in the list.
- User tests with it (2026-11-11), both passed:
  - "Disconnect" in System Settings, 10 s, then Bluetooth off and on: the earbuds stayed disconnected.
  - Earbuds into the case, Bluetooth off, out, 10 s, on: connected within a few seconds.

**Image** `out/halium14/boot-ut.img` SHA256 `d9184e3c39a48130599ada3d603cf9f2330f90277016db0d54d3bc41f19a60b3` (copy `out/halium14/boot-ut-d9184e3c.img`), kernel `#18` (`2d655756…`, patches 0001–0010). Compared with `7593d35c…` it adds:
- kernel patch 0010 (clean disconnect before an rfkill block);
- `stone-bt-autoconnect.service` and `bt-autoconnect.py`, byte-identical to the tested copy (SHA256 `01718eec…`);
- init cleanup of the auto-connect test files.

Not yet written.

Still open:
- the intermittent Bluetooth HAL death while Bluetooth is off (seen once; the recovery is now automatic but takes about 13 s);
- empty `logcat`;
- earlier-found journal loss before the NTP sync.


## 14. System journal: the start of every boot is lost

The system journal never held the first ~40 s of a boot (everything before the NTP sync). That cost data in item 2 (USB), item 13 (Bluetooth) and earlier.

What is seen (2026-11-11, image `d9184e3c…`, kernel `#18`):
- `journald.conf.d`: `SystemMaxUse=500M` (`50-ubuntu-touch.conf`, lxc-android-config), `ReadKMsg=no`, `ForwardToSyslog=yes`.
- **The journal sits at its cap** (498.8 MB), and **there is no archived system journal at all**: only the active `system.journal` (8 MB). The other 93 files (491 MB) are `user-32011` (phablet) and `user-1001` (radio, i.e. ofono) journals from 2026-11-10 and -11.
  - They are not busy: about 2,500 lines an hour for phablet (lomiri, maliit-server, media-hub-server) and 775 for radio (ofono). The space is many mostly empty 8 MB files, two per boot.
- The active `system.journal` starts **at the NTP sync** (head realtime 23:08:46, "Initial clock synchronization" at 42.8 s) and held 271 entries.
- **Why system files are lost.** journald's vacuuming orders archived files by sequence number when they belong to the same series, and otherwise by their first timestamp. Each boot starts a new series, and its system journal starts with 1970 timestamps, so files from earlier boots that start in 1970 always come first.
  - At the NTP jump the current boot's file is closed too. It is then the oldest by timestamp, and goes at the next vacuum, while user files from earlier boots (which start after the clock was right) stay.
- **Why 1970:**
  - The Qualcomm RTC cannot be set; `/sys/class/rtc/rtc0/since_epoch` is 1210362 (14 days).
  - UBports' `timekeeper.service` (`/usr/sbin/timekeeper`) stores the offset to real time in `/data/time/timekeep` (= `/var/lib/android-data/time/timekeep`) at shutdown, and restores it at about 11.9 s. The stored offset is right: 1210362 + 1793246372 = now.
  - But at about 14 s the Android container starts the vendor's **`time_daemon`** (`/vendor/bin/time_daemon`, `CAP_SYS_TIME`, `settimeofday`). It sets the clock from the RTC plus its own offsets (`ats_*` in `/data/vendor/time`), which Android's framework updates and Ubuntu Touch never does. adbd's own timestamp at 16.6 s was "01-14 17:40", neither the RTC nor today.
  - systemd-timesyncd's restore from its timestamp file only happens at its start (12 s), and nothing corrects the clock again until NTP.

Fix:
- **`boot/ut-init/init`**: before `switch_root`, set the clock to RTC + `timekeep` offset (via the root filesystem's Python, `time.clock_settime`), only when the result is after 2020-01-01. The init logs it to the kernel log ("clock set to …").
- **`usr/lib/stone/clock-guard.py`**, `stone-clock-guard.service` (`sysinit.target`, before `lxc-android-config`):
  - It waits on a `timerfd` with `TFD_TIMER_CANCEL_ON_SET`, which wakes on every clock change; no polling (ctypes, since Python 3.12 has no `os.timerfd_*`).
  - When the clock is before 2020, it sets RTC + offset again and runs `journalctl --rotate`, so any entries stamped in between stay in a file of their own.
  - Nothing legitimate sets a phone's clock before 2020.
- Live install: `tools/phone-debug/stone-clock-guard-install.sh`. A live install has no init part: the first seconds before the guard starts are still stamped 1970.

Live test of the guard (2026-11-11, image `d9184e3c…`, so without the init part):
- **time_daemon confirmed.** At 14.96 s the guard logged "clock changed: clock was Wed Jan 14 19:18:57 1970; set back to RTC + offset, Wed Nov 11 23:18:29 2026", and rotated the journal.
- The boot's journal now starts at **12.1 s** instead of 42 s.
  - Archived file 12.1–14.96 s (head 23:18:26, correct, kept); active `system.journal` from 23:18:29.
  - Still lost: 0–12.1 s, including the guard's own correction at its start (3.3 s).
  - Until the flush to `/var`, journald writes to `/run`. The flush copies those entries, starting with 1970 ones, into the persistent file, so that file starts in 1970. timekeeper's restore at 12.1 s closed it, and it went at the next vacuum.
  - Hence the init part: nothing may ever be stamped 1970.

Test image `out/halium14/boot-ut-test-clock.img` SHA256 `663a4d80ae984d3c4e772dd7bd8564d926c9dbbf14e877167dc1d69abd951386`: `d9184e3c…` plus the init clock setting and the guard (byte-identical to the live-installed copy), kernel `#18`.

Test of `663a4d80…` (2026-11-12):
- **The journal starts at 3.17 s** ("Journal started", the first entry journald can have; `ReadKMsg=no`, so no kernel lines), stamped 2026-11-12 00:20:29, with **no 1970 entries** in the boot.
  - timekeeper (about 12 s) and the guard (3.34 s) come later, so the init set the clock.
  - Its own "clock set" line had already left the kernel log buffer.
- The guard caught time_daemon again at 15.0 s ("clock was Wed Jan 14 20:21:09 1970; set back … Thu Nov 12 00:20:41 2026").
- The system journal is now several files, all with correct head times: the previous boot's files (23:18:26, 23:18:29) and this boot's (00:20:29, 00:20:38 and the active 00:20:41). timekeeper's restore and the guard's rotation each close one, and none is deleted early.
- **The previous boot survived the reboot**: boot −1 (the guard-only boot) still has 3153 entries, from 12.1 s to its shutdown an hour later; boot −2 is listed too. Until now a previous boot's system journal never survived.
- The cap (`SystemMaxUse=500M`, 501 MB in use) still applies. Vacuuming now drops the oldest files across all users instead of the system's newest.
- After one more reboot: boot −1 (the first boot of `663a4d80…`) has **4027 entries, from "Journal started" at 3.17 s to "Journal stopped" at its shutdown (203 s), no 1970 entries**. Boot 0 starts at 3.11 s, and the guard caught time_daemon again.

Item 14 is done. `out/halium14/boot-ut-test-clock.img` (`663a4d80…`) is the current image, written and confirmed. It is built from the current sources and includes the Bluetooth work of item 13 (`d9184e3c…`, whose own file is kept as `out/halium14/boot-ut-d9184e3c.img`).

## 15. Android log (logcat) reads back empty

Since item 13, `logcat` printed nothing: as phablet, as root from the host, and as root through `lxc-attach`, which still worked for the GNSS debugging on 2026-11-11.

What is seen (2026-11-12, image `663a4d80…`):
- logd runs (`init.svc.logd=running`, `logd.ready=true`, uid 1036). `/dev/socket/logd`, `logdr` (both `srw-rw-rw-`) and `logdw` (`s-w--w--w-`) exist on the host, the same sockets as in the container. Properties: `ro.logd.kernel=true`, `logd.logpersistd.enable=true`, `ro.debuggable=1`, `userdebug`.
- As phablet (which has group `android_log`, AID 1007): `logcat -d -t 3` gives rc 0 and nothing. A line written with `/system/bin/log -t stonetest` is not read back. `logcat -g`: "failed to get the readable 'main,system,crash,kernel' log sizes".
- **The container has its own PID namespace**: logd is pid 1593 on the host and 452 inside (`NSpid: 1593 452`). logd checks a client's credentials by `SO_PEERCRED`, and its supplementary groups through `/proc/<pid>/status`. A host process's pid cannot be mapped into the container's namespace, so logd sees pid 0 and cannot find phablet's `log` group. That explains `-g` failing for phablet.
- It does not explain root reading nothing, even inside the container. Next: `tools/phone-debug/stone-logcat-check.sh` (root) collects:
  - logd's statistics (`logcat -S`);
  - a test line written and read back inside the container, and one from the host;
  - logd's open sockets;
  - the logpersist files in `/data/misc/logd`;
  - the log properties.
  It writes everything to `/home/phablet/logcat-check.txt`.

Result of the check (root):
- Inside the container as root: `logcat -d` gives nothing; `logcat -S` "Failed to read data"; `logcat -g` fails too. A line written with `log` inside the container is not read back. `/data/misc/logd` is empty.
- logd's fds 26–28 are the three sockets init created at boot (the socket files' inodes are 28555/28557/28559). fd 29 is `/proc/kmsg` (`ro.logd.kernel=true`).

**logd is wedged** (probes as phablet, 2026-11-12):
- Thread context switches before and after a write, a read and `logcat -g`: `logd.writer` 5612 → 5612; `logd.control` 4 → 4 (it has handled nearly nothing since boot); `logd.klogd` 6478 → 6478, although the kernel logs constantly; only `logd.reader` moved. All threads are in `S`.
- Raw sockets (Python): `connect()` to `/dev/socket/logd` and `logdr` fails with `EAGAIN`. For Unix sockets that means a full listen backlog: nobody accepts. A datagram to `logdw` times out: its receive queue is full and nobody reads.
- So logd's threads no longer service their sockets, which looks like a deadlock in logd. A guess: the clock jumps of item 14 (logd starts at 6.4 s; then time_daemon goes back 56 years and the guard forward again; before item 14 there were more jumps).
- Next: `tools/phone-debug/stone-logd-debug.sh` (root) saves the thread states, `/proc/<tid>/stack` and `debuggerd -b` for logd, then restarts logd and checks reading and writing. Output in `/home/phablet/logd-debug.txt`.

Result of `stone-logd-debug.sh` (2026-11-12):
- **A deadlock.** `logd.writer`, `logd.control` and `logd.klogd` all wait in `futex_wait` on the same address, `0x558069e600` (`FUTEX_WAIT_BITSET_PRIVATE`, value 2 = a locked, contended mutex, no timeout). It is in logd's own data segment, most likely its global `logd_lock`.
  - `logd.reader` waits with a timeout on another futex (a condition variable), and the main thread is in `sigsuspend` (normal).
  - No thread holds the lock in a way that ends. `debuggerd -b` printed nothing, so there are no user-space stacks.
- `ss`: logd's control socket had 5 connections stuck in `SYN-SENT` (the full backlog).
- **`setprop ctl.restart logd` fixes it**: `logcat -d` returns lines, a test line reads back, and `logcat -g` shows the 256 KiB buffers. 13 minutes later the new logd (pid 11223) still answers `getLogSize` (262144), takes writes, and all its threads are moving.
- The boot instance had wedged early: `logd.control` had only 4 context switches since boot. Suspected trigger: the clock jumps at boot (logd starts at 6.4 s; time_daemon sets 1970 at about 14 s; the guard sets 2026 right after).
- Test: `tools/phone-debug/stone-logd-clock-test.sh` (root) probes logd, sets the clock back to the raw RTC (January 1970) as time_daemon does, lets the guard correct it, and probes again; it restarts logd if it wedged.
- Result: **the clock is not the trigger.** logd was already wedged *before* the jump. It was the instance restarted at 00:47, which still answered at about 00:49. It stayed wedged after the jump, and a restart fixed it again.
- New suspect: **a reader on the host side.**
  - Between 00:49 and the test, the only unusual access was a `/system/bin/logcat -d` run from the host as phablet, in the same health check.
  - Earlier in that boot, the first command of `stone-logcat-check.sh` was a host-side `logcat -d` as root.
  - A host process is pid 0 in logd's PID namespace, and the deadlock fits logd's reader setup: `logd.reader` is in a timed wait, while writer, control and klogd wait on the same lock.
  - Host-side writes, which Halium processes do all the time through libhybris' liblog, are unlikely: logd would wedge right after every restart.
- Test: `tools/phone-debug/stone-logd-trigger-test.sh` (root). Each step starts from a freshly restarted logd, does one kind of host access (write, `getLogSize`, `logcat -d`; as root and as phablet), and checks logd from inside the container with `logcat -g`.

Result (2026-11-12), one fresh logd per step:

| Host access | logd afterwards |
|---|---|
| nothing (2 s idle) | ok |
| write (`log`), root / phablet | ok / ok |
| `getLogSize` on `/dev/socket/logd`, root / phablet | ok / ok |
| `logcat -d`, root | ok |
| **`logcat -d`, phablet** | **wedged** |
| `logcat -d` inside the container, root | ok |

- **Only an unprivileged reader wedges logd.** Every empty log in items 2, 13 and 15 followed a `/system/bin/logcat` run as phablet over adb earlier in the same boot; logd was never stuck from boot by itself.
- With primary group `android_log` (1007, via `sg`), phablet's `logcat -d` still hung logd. So it is not the group check (the PID 0 problem only hides phablet's supplementary groups). **It is the uid.**
  - Android 13+ logd exempts readers below `AID_APP_START` (10000) from the user-consent check for log access. Root and system services are exempt; phablet (32011) counts as an app.
  - For an app, logd asks the framework's `LogcatManagerService` for consent. Halium runs no framework, so the request never returns, and logd deadlocks: `logd.reader` keeps waiting with a timeout, while the writer, control and klogd threads wait on its main lock.
  - The logd binary is not readable as phablet, so this is read from the behaviour rather than from its code.
- Fix:
  - **`usr/bin/logcat`**: as root, it execs `/system/bin/logcat`. Otherwise it refuses with an explanation ("reading Android's log needs root on Ubuntu Touch; use: sudo logcat …"). Nothing on the host had a `logcat` in `PATH` before.
  - **`usr/lib/stone/logd-watchdog.py`**, `stone-logd-watchdog.service` (after `lxc-android-config`): every 30 s it sends a root `getLogSize` to `/dev/socket/logd`, which is safe (see the table). After two failures in a row it runs `lxc-attach -n android -- setprop ctl.restart logd` and logs the result. This covers `/system/bin/logcat` run directly, or anything else that wedges logd.
  - A restart empties logd's in-memory buffers. The lines lost are the ones logd never took while wedged anyway.
  - A stub `LogcatManagerService` that declines or approves at once (via gbinder, like `stone-netd-stub`) would remove the deadlock itself. It is not needed for now.
- Live install: `tools/phone-debug/stone-logd-fix-install.sh`.
- Live test (2026-11-12):
  - logd was wedged by the `sg` test. The watchdog started at 01:01:52, and at 01:03:01 logged "logd did not answer twice; restarted it: logd answers again". The new logd started at 01:02:57.
  - Half a minute later it answered `getLogSize` (262144), and its writer and klogd threads were moving.
  - `logcat -d -t 3` as phablet: the wrapper's message, exit code 1, and logd stays healthy.
  - `sudo logcat -d -t 5` printed the last lines (main and kernel buffers); logd stayed the same process and kept answering.

**Image** `out/halium14/boot-ut.img` SHA256 `92c0d49f9a8ecbe73456d5c9b35e6327f59bb4e2263e75f2a2dcc690b4a12a48` (copy `out/halium14/boot-ut-92c0d49f.img`), kernel `#18`. It is `663a4d80…` (kept as `out/halium14/boot-ut-663a4d80.img`) plus `usr/bin/logcat` and the logd watchdog, all byte-identical to the tested copies. Never written: `16bfa7b0…` (item 3) includes it and was written on 2026-11-12.

## 16. Top panel: an indicator sits on the front camera

The front camera is a punch-hole in the middle of the top edge. Lomiri's top panel was 63 px high (3 grid units of 21 px), and one indicator icon always sat on the camera.

What is seen (2026-11-12):
- Lomiri (24.04-2.x) supports display cutouts through deviceinfo (UBports' "Display cutouts" porting page). It reads these keys from `/etc/deviceinfo/devices/stone.yaml`, in physical pixels:
  - `CollapsedPanelHeight`: the panel height, used in portrait only;
  - `DisplayCutoutsCollapsed` and `DisplayCutoutsExpanded`: rectangles (`x y width height`) that indicators skip, with the panel collapsed or pulled down. The expanded panel is 147 px (7 gu);
  - `DisplayCutoutsCollapsedLight`: the same for the light theme (optional; falls back to the collapsed list).
- When `DisplayCutoutsCollapsed` is set, `lomiri` loads `Panel/WithCutouts` instead of `Panel/WithoutCutouts` at start. Our `stone.yaml` set none of these, so the panel ignored the camera.
- The camera's position, from the vendor overlay `FrameworksResOverlayStone.apk`:
  - `config_mainBuiltInDisplayCutout`: `M -25,52 a 25,25 0 1,0 50,0 …`, a 50 px circle centred horizontally at y 52, so x 515–565 and y 27–77 on the 1080×2400 panel;
  - `rounded_corner_radius` 102 px;
  - Android's own `status_bar_height_portrait` is 104 px.
- The camera reaches 14 px below the 63 px panel.

Fix, in `etc/deviceinfo/devices/stone.yaml`:
- `CollapsedPanelHeight: 95`. 104 px (Android's value, which centres the icons on the camera) looked too tall; 95 px covers the camera with a margin.
- `DisplayCutoutsCollapsed`: `0 0 34 95`, `488 0 104 95`, `1046 0 34 95`. These are the camera with 27 px of room on each side, and the two rounded corners. The corner width follows the porting page's estimate, w ≈ r − √(r² − (r − h/4)²).
- `DisplayCutoutsExpanded`: the same rectangles at 147 px.
- Landscape is unchanged: Lomiri uses neither the height nor the cutouts outside portrait.

Live test (2026-11-12): the yaml was copied to `/etc/deviceinfo/devices/stone.yaml` and `lomiri-full-greeter` restarted (`device-info get DisplayCutoutsCollapsed` printed the rectangles).
- At 104 px: no indicator on or next to the camera, nothing cut by the corners, and the pulled-down panel also keeps clear. The bar looked too tall.
- At 95 px: the right height.

**Image** `out/halium14/boot-ut.img` SHA256 `2edde0c6b6ca88b9a07577fae6ce2034dd39aba419ebd9d94f444137055ad8ba` (copy `out/halium14/boot-ut-2edde0c6.img`), kernel `#18`. It is `92c0d49f…` (item 15) plus the new `stone.yaml`, byte-identical to the tested copy. The kernel and all other ramdisk files are the same; the recovery ramdisk has the same files, only repacked. Never written: `16bfa7b0…` (item 3) includes it and was written on 2026-11-12.

## Sources

- [UBports installer configs](https://github.com/ubports/installer-configs) (v2 schema, `Spacewar.yml`)
- [halium-generic-adaptation-build-tools](https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools) (`gsi-port-ci.yml`, `make-bootimage.sh`, `deviceinfo.sample`)
- [devices.ubuntu-touch.io source](https://gitlab.com/ubports/infrastructure/devices.ubuntu-touch.io) (`data/devices`, `portStatus.json`, `progressStages.json`)
- [UBports porting: Display cutouts](https://docs.ubports.com/porting/configure_test_fix/device_info/DisplayCutouts.html) (deviceinfo keys, units, the corner estimate)
- [UBports porting introduction](https://docs.ubports.com/porting/introduction/Intro.html) and [UBports installer porting notes](https://ubports-docs-dev.readthedocs.io/en/latest/_sources/porting/finalize/UBports_installer.rst.txt)
