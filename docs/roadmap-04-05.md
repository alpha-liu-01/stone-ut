# Roadmap items 4 (remainder) and 5

English translation of `docs/roadmap-04-05.md`. The Chinese file is the source of record.

Scope is the unfinished part of item 4 in `docs/feasibility.md`, plus the part of item 5 that says "get a Droidian root filesystem ready." The goal stops at images sitting on disk. Do not format userdata, do not flash, and do not reboot.

Current phone state: slot `_b`. crDroid `v12.9-20260416` has booted to `sys.boot_completed=1` on the Halium-config kernel built 2026-11-09. `super` and userdata are untouched.

## Whether to flash back to Android 14

Do not flash it in this stage.

The fingerprint of `third_party/crDroidAndroid-14.0-20241212-stone-v10.11.zip` is `POCO/moonstone_p_global`, not this `sunstone_cn`. The current Android 16 vendor already reaches the desktop together with the new kernel, and the display HAL is still HIDL Composer 2.4. Let Droidian try one boot against this vendor first. Treat Android 14 as the next experiment only if the container or libhybris fails specifically because the vendor interface is too new, and separately check that the moonstone global panel and firmware match this China-market phone.

Droidian 101's generic root filesystem is published only up to api33 (Android 13). There is no api36. `ro.vendor.api_level` is 31, which their docs call api32 (Android 12/12.1). This stage uses api32. api33 stays as a replacement rootfs if the same experiment fails. It does not require flashing a ROM first.

userdata may be wiped. The user has confirmed there is nothing in it to keep. Wiping is still a manual test for the next stage, and it is outside the execution of this document. After a wipe, writing back only `boot_b` and `vendor_boot_b` is not enough to bring Android back: userdata also has to be reformatted so crDroid can rebuild the encrypted f2fs. The system partitions in `super` stay as they are.

## 1. Obtain the api32 root filesystem

Goal: get Droidian 101's generic Phosh root filesystem and confirm it is an ext4 image.

### Planned steps

1. Download the stable release, not a nightly: `droidian-OFFICIAL-phosh-phone-rootfs-api32-arm64-101.20261023_20261022.zip`. Put it in `third_party/`. It does not go into git.
2. List the zip. Early ports used a recovery package, which should contain `data/rootfs.img`.
3. Extract `rootfs.img` and confirm the filesystem type and size.
4. Note that the default unlock passphrase, from the upstream notes, is `1234`. This stage does not boot it, so that cannot be verified yet.

### Implementation notes

2026-11-09: downloaded the stable release, not a nightly. The file is `third_party/droidian-OFFICIAL-phosh-phone-rootfs-api32-arm64-101.20261023_20261022.zip`, 1437967579 bytes, not in git. SHA256 `1f3b916d563a63b8e4cff663c4296c6ccfc0fd26f6fc8b125ed7c5fc304f4fd4`.

The zip contains `data/rootfs.img` (4325376000 bytes), `setup.sh`, `tools/busybox`, and a placeholder `updater-script`. The extracted image is `third_party/droidian-rootfs/data/rootfs.img`, also not in git. `file` identifies it as ext4, UUID `a6af57c5-8efe-4f89-918a-cd7c7b530307`, block size 4096, block count 1056000.

`/sbin/init` points at `../lib/systemd/systemd`. `/vendor` is a symlink to `/android/vendor`, and that directory does not exist yet. `/android` is an empty directory. The real vendor mount point is `/mnt/vendor`.

The default unlock passphrase, per the upstream notes, is `1234`. This stage did not boot, so it was not verified.

### Events

- Downloaded the api32 rootfs zip and computed its SHA256.
- Listed the zip and extracted `data/rootfs.img`.
- Confirmed ext4, and observed the real layout of `/sbin/init` and the vendor mount point.

## 2. Confirm the boot chain, and do not tear down a vendor mount that already works

Goal: know which ramdisk layer Droidian's init should live in, and whether a new init can mount the vendor logical partition directly.

### Planned steps

1. Unpack the lz4 cpio of the current `boot_b` and `vendor_boot_b`.
2. Record what is in the boot ramdisk. It is known to have been modified by Magisk. After switching to a Droidian init, this boot path no longer has Magisk. `boot_b.img` in the backup can still write the Magisk boot disk back.
3. Record the first-stage init and `fstab.default` in the vendor ramdisk. `vendor` is a logical partition inside `super`, not a standalone `by-name` partition.
4. Decide that this stage's init only has to mount userdata and `rootfs.img`. If the vendor mapper node does not exist yet while init is running, write that down as a known gap. Do not pretend it is mounted.

### Implementation notes

What was unpacked is the pair of ramdisks backed up before the Halium kernel was flashed. The running `out/halium/` images reuse that same ramdisk, so the contents match what is on slot `_b` now.

The boot ramdisk is a Magisk-modified cpio: `.backup/.magisk`, `.backup/init.xz`, `overlay.d/sbin/magisk.xz`, with `init` as the entry. After switching to the Droidian init below, this boot path has no Magisk. `backups/2026-11-09-crdroid-12.9/boot_b.img` can still write the Magisk boot disk back.

`init` in the vendor ramdisk is a symlink to `/system/bin/init`. `first_stage_ramdisk/fstab.default` marks `system`, `system_ext`, `product`, `vendor`, and `odm` as `logical`, `slotselect`, and `first_stage_mount`. They live in `super` and have no `by-name` nodes. userdata in this fstab is still encrypted f2fs: `/dev/block/bootdevice/by-name/userdata`.

This stage's init only mounts the ext4 on userdata, then loop-mounts `rootfs.img` inside it. While init is running there is no Android ueventd, and therefore no `/dev/block/mapper/vendor_b`. If that node is not seen, continue. Do not pretend vendor is mounted.

### Events

- Unpacked the boot and vendor ramdisks. Confirmed Magisk on the boot side, and first-stage init plus fstab on the vendor side.
- Confirmed from fstab that vendor is a logical partition in `super`.
- Left the vendor mount as a known gap.

## 3. Build a boot and vendor_boot that are not flashed yet

Goal: use the `Image` already shown to boot Android, with an initramfs that looks for `rootfs.img`. Keep the DTB and the DTBO index as they are.

### Planned steps

1. Build an initramfs with a static busybox. init mounts proc, sysfs, and devtmpfs, waits for `/dev/block/by-name/userdata`, mounts it as ext4, loop-mounts `/userdata/rootfs.img`, then `switch_root`s into its `/sbin/init`.
2. Compress the ramdisk with lz4, the same as this machine's existing boot ramdisk.
3. Pack a header v3 `out/halium-droidian/boot.img`. The kernel is still `kernel/build/arch/arm64/boot/Image`.
4. Pack a paired `vendor_boot.img`: reuse the current vendor ramdisk and DTB, and append `datapart=/dev/block/by-name/userdata` to the existing command line. Addresses and page size match the pair that already booted.
5. Check the magic, the header version, and that the two files are under 128 MiB and 96 MiB respectively.
6. Do not run fastboot.

### Implementation notes

init is `boot/droidian-init/init`. The packing script is `boot/droidian-init/build-boot-images.sh`. busybox is the aarch64 static binary from Alpine `busybox-static` 1.37.0-r31, at `third_party/busybox-aarch64/busybox`, not in git.

devtmpfs does not create `/dev/block/by-name/userdata` by itself. That link waits for Android's ueventd. The uevent root read on this machine is `DEVNAME=sda19`, `PARTNAME=userdata`, so the node is `/dev/sda19`. init was changed to look for `PARTNAME=userdata` in `/sys/class/block/*/uevent` and then mount that node. The command line still gets `datapart=/dev/block/by-name/userdata` as planned, for a later real initramfs. This busybox init does not read it.

The ramdisk uses `lz4 -l`, magic `02 21 4C 18`, matching the legacy frame of the existing boot ramdisk. After unpacking, `/init` and `/bin/busybox` are visible.

`/vendor` is a symlink and cannot be a mount point. init tries to mount ext4 onto the rootfs's existing `/mnt/vendor` only if `/dev/block/mapper/vendor_b` already exists. That node did not exist when this image was packed.

Products, none of them flashed:

- `out/halium-droidian/boot.img`, 49160192 bytes, under 128 MiB. Header v3, kernel 48402944 bytes, OS 16.0.0 / 2026-04. SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`
- `out/halium-droidian/vendor_boot.img`, 24264704 bytes, under 96 MiB. Header v3, page size 4096, vendor ramdisk 23817365 bytes, DTB 441127 bytes, addresses matching the pair that already booted. SHA256 `c3d904e5fdcff96fcc8de91f3f1950c6ee3a590fad15397c42475818668554d3`

DTBO was not rebuilt. `dtbo_idx` is still 1.

### Events

- Took a static aarch64 busybox and made an initramfs.
- Confirmed userdata's `PARTNAME` from the running phone's uevent. init now finds the block device that way.
- Produced header v3 boot and vendor_boot, and checked magic, addresses, and partition sizes. fastboot was not run.

## 4. Prepare userdata contents, but do not write them to the phone yet

Goal: on the host, have an ext4 image that can later be written to userdata, already containing `/rootfs.img`.

### Planned steps

1. From the `rootfs.img` extracted in item 1, make a slightly larger ext4 image. The mount layout matches the initramfs convention: the filename at the image root is `rootfs.img`.
2. The image only has to hold the root filesystem plus a little margin. It does not have to be 103 GiB. Later it can be written at the start of the partition; the ext4 superblock records its own size.
3. Compute the SHA256 and write the path into the notes.
4. Do not run `fastboot format`. Do not run `fastboot flash userdata`.

### Implementation notes

`out/halium-droidian/userdata.img`, 5033164800 bytes (4800 MiB), ext4, label `userdata`, UUID `d39d4bb1-41fc-47de-8e68-550de0443df1`. The root contains only `lost+found` and `rootfs.img`. That `rootfs.img` is 4325376000 bytes, the same size as the one in the zip. SHA256 `66e0a5cfe61e03ccc81921b78a7251501d948b059916eff94fa82ffe55e7113d`.

It is much smaller than the phone's userdata. Writing it at the start of the partition is enough. The ext4 superblock records these 4800 MiB. The image was not flashed when it was prepared. It was written to the phone only after the user confirmed userdata had nothing to keep and the phone was in fastboot. See the next section.

### Events

- Used `mke2fs -d` to put `rootfs.img` into a 4800 MiB ext4.
- Used debugfs to confirm the root filename is `rootfs.img`.
- Computed the SHA256. Nothing was written to the phone.

## 5. Write slot B and reboot

The user confirmed userdata can be wiped, and the phone was already stopped in fastboot. Write only boot, vendor_boot, and userdata. Do not write dtbo, vbmeta, or `super`.

### Implementation notes

2026-11-09, before writing: `current-slot` was `b`, `unlocked: yes`. The order was userdata first, and `boot_b` and `vendor_boot_b` only after that succeeded, so a userdata failure would leave the original Android boot disk in place.

`fastboot flash userdata` first reported `Invalid sparse file format at header magic`, then sent this raw ext4 in 5 chunks. Every Writing was OKAY. Total time 91.7 seconds. `boot_b` and `vendor_boot_b` were also OKAY. The slot was still `b` afterward. Then `fastboot reboot`.

In the host kernel log the phone disconnected from fastboot (`18d1:d00d`) at 11:15:48. It did not enumerate again. The user saw the first boot splash, then the Droidian logo for about a second, then a fully black OLED. Backlight could not be judged from the screen. The user returned to fastboot by hand. The logo being drawn means init had mounted userdata, loop-mounted `rootfs.img`, and `switch_root`ed into the root filesystem, and Plymouth had run. The black screen happened after that.

fastboot itself cannot read the log of that boot. The partition table has `logdump` (64 MiB) and `minidump`. This bootloader has no usable `fetch`. To avoid handing userdata to an Android recovery that would treat it as f2fs, `out/halium-droidian/boot-logs.img` was built separately: it mounts the root filesystem read-only, collects strings from pstore, the journal, and `logdump`, and sends them out the USB ACM serial port the kernel already has. It was not written yet. While reading `fastboot getvar all`, the host closed the pipe early. The bootloader then stopped answering commands. The log image can be flashed only after manually re-entering fastboot.

Rollback is still: enter fastboot, write back `backups/2026-11-09-crdroid-12.9/boot_b.img` and `vendor_boot_b.img`, then let Android format userdata as encrypted f2fs. `super` stays untouched.

### Events

- Confirmed slot `_b` and unlocked.
- Wrote `userdata`, `boot_b`, and `vendor_boot_b`. fastboot returned OKAY for all of them.
- Rebooted. After the host-side USB disconnect, the phone did not enumerate again.
- The user saw the Droidian logo for about a second, then a black screen, and returned to fastboot by hand.
- Built `boot-logs.img`, not yet written. After the truncated `getvar all`, the bootloader stopped responding.
- The user re-entered fastboot. The system had booted once more in between. Only `boot-logs.img` was written to `boot_b`. The slot was still `_b`. The host saw USB device `0525:a4a7`, product name `boot-log`. In the serial output pstore was empty, `rootfs.img` could not replay logs because it was mounted read-only, and `journalctl` did not run. This boot does not enter Droidian, so there was no logo.
- Switched to `boot-disk.img`, which exports userdata read-only as the USB disk `/dev/sdb`. After a read-write mount, `journalctl` said `No journal files were found`. `/usr/lib/systemd/journald.conf.d/10-journald-volatile.conf` in the rootfs sets `Storage` to `volatile`. The previous boot's logs lived only in memory and were gone after the reboot.
- Prepared `boot-patch.img`. After the user returned to fastboot it was written. About 13 seconds later the phone returned to fastboot by itself. No USB network interface or USB disk appeared in between, which matches the path where the patch finishes and reboots into the bootloader. Then the `boot.img` that can enter Droidian was written back and the phone rebooted. The slot was still `_b`.
- This boot drew the logo for about a second. The user waited nearly a minute and returned to fastboot. userdata was exported with `boot-disk.img`. The journal had been written to disk. `android-mount` failed: `/vendor` is a symlink to `/android/vendor`, which does not exist, and `parse-android-dynparts` reads only metadata slot 0, so it mapped `dynpart-vendor_a` instead of slot `_b`'s vendor. LXC android and Phosh both failed on that dependency. The new `boot-patch.img` creates the `/android/*` directories and changes the dynparts slot to 1.
- The patch boot was written to `boot_b` and returned to fastboot by itself after about 12 seconds. Then the Droidian `boot.img` (SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`) was written back and the phone rebooted. The slot was still `_b`. userdata, vendor_boot, dtbo, vbmeta, and super were not touched.
- After another black screen, the journal was read with `boot-disk.img`. The dynparts slot patch took effect: `dynpart-vendor_b` was mounted, and `/vendor/build.prop` passed. `android-rootfs.img` (Halium arm64, SDK 32) was also mounted at the container root. `android-mount` still failed because `ExecStartPost` binds `/android/system/lib64/libselinux_stubs.so`. That path is an empty directory. The real library is `/system/lib64` inside the container root. The LXC config also requires a bind of `/android/data`, which does not exist, and `lxc.arch` is written as `armhf` while `/system/bin/init` is aarch64. The new `boot-patch.img` (SHA256 `95f3b9017c96f2109a88d04824bb56acff0e170c7efbd923ed35b83e352fecb8`) fixes those three.
- That patch was written to `boot_b` and returned to fastboot by itself after about 12 seconds. Then the Droidian `boot.img` was written back and the phone rebooted. The slot was still `_b`.
- Black screen again. `android-mount` succeeded, LXC android entered running, the hostname became RedmiNote125G, and Phosh started. `linkerconfig` got signal 6 during early-init because `SANITIZER_DEFAULT_VENDOR is not defined`, and did not generate a linker namespace. `vndservicemanager` and `vendor.qti.hardware.display.composer` both exited with status 1, and the composer's onrestart could not find surfaceflinger. The new `boot-patch.img` (SHA256 `7bec092b186f197aa1f110d23f516683eab5e0a6986e8431860a3e378e496605`) replaces linkerconfig with a script that writes a permissive `ld.config.txt`, and lands `logcat` in `/var/log/stone-logcat.txt`.
- That patch was written to `boot_b` and returned to fastboot by itself after about 12 seconds. Then the Droidian `boot.img` was written back and the phone rebooted. The slot was still `_b`.
- Black screen again. The replacement `linkerconfig` exited with status 0 and no longer reported `SANITIZER_DEFAULT_VENDOR`. `vndservicemanager` still exited with status 1 after about 50 milliseconds. The container `/dev` is a fresh tmpfs, and `vndbinder` is not in it. This journal was truncated by the reboot while it was being rewritten, and the `logcat` file is empty. The new `boot-patch.img` (SHA256 `6ec50e4daa21aee689d7e3aea5cd0b51f792ee87e794fe28a15518f5bda1b230`) creates `binder`, `hwbinder`, and `vndbinder` inside the container and sends stderr from those two HALs to the kernel log.
- That patch was written to `boot_b` and returned to fastboot by itself after about 12 seconds. Then the Droidian `boot.img` was written back and the phone rebooted. The slot was still `_b`.
- The logo lasted about 3 seconds this time. `binder`, `hwbinder`, and `vndbinder` exist. After `vndservicemanager` was wrapped into `/vendor_real/bin`, the linker did not count it as part of the vendor namespace and loaded Halium's old `libc++`, which lacks the `std::stringstream` vtable. The new `boot-patch.img` (SHA256 `62ca25ccdf8a668efbe00fb375a5fe915bd84165e7f228d59e857f06632c11ee`) puts `/vendor_real/bin` into the vendor namespace.
- That patch was written to `boot_b` and returned to fastboot by itself after about 12 seconds. Then the Droidian `boot.img` was written back and the phone rebooted. The slot was still `_b`.
- The logo was still about 3 seconds. `ld.config` already contains `/vendor_real/bin`, and both `vndservicemanager` and `vendor.qti.hardware.display.composer-service` were wrapped. The 3.9G root filesystem was full. This boot's `dmesg` wrote only the first 16KB (kernel time 0.4 seconds). `journal` and `logcat` are empty, so the new linker error is not visible. Halium's `/system/lib64/libc++.so` does not have the `std::stringstream` vtable. The `libc++.so` in the same vendor ramdisk (NDK r28) has that symbol. The new `boot-patch.img` (SHA256 `d661ccad0d9de5eee6cb25ceaf30dd11a1eafcaa06a2c547d9e81a129f6f2bc6`) clears the apt cache and the old journal to free space, puts the `libc++` that has the symbol in `/vendor_real/lib64` at the front of the vendor namespace search path, and writes the link result into a small file first.
- That patch was written to `boot_b`. The patch boot left fastboot and returned to fastboot by itself after about 15 seconds. Then the Droidian `boot.img` (SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`) was written back and the phone rebooted. The slot was still `_b`. userdata, vendor_boot, dtbo, vbmeta, and super were not touched.
- The logo was about 1 second this time. The vendor `libc++` contains `stringstream` and has been placed in `/vendor_real/lib64`. The new link error is that `libapexsupport.so` cannot be found. `/vendor/lib64/libbinder.so` needs it, and Halium 12 does not have this library. `vndservicemanager` therefore still exits with status 1. The new `boot-patch.img` (SHA256 `6379cb98bc64f65be69da4d2f1fb64b9ccc36bfec9e695d1d31dd23f934f3382`) adds a `libapexsupport.so` that exports only the four `AApexInfo_*` symbols and returns `AAPEXINFO_NO_APEX` to non-APEX processes.
- That patch was written to `boot_b`. The patch boot left fastboot and returned to fastboot by itself after about 14 seconds. Then the Droidian `boot.img` (SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`) was written back and the phone rebooted. The slot was still `_b`. userdata, vendor_boot, dtbo, vbmeta, and super were not touched.
- The logo was still about 1 second. `libapexsupport.so` is in `/vendor_real/lib64` and `/system/lib64`. The container did not start: `lxc-start` received `ABORTING`. The wrapper wrote `ld.config.txt` into `/linkerconfig` inside the image before the container started. `/init` matches no `dir.*`, the linker looks for a `[default]` section that does not exist, and init cannot start. The new `boot-patch.img` (SHA256 `7278da93c54ea3fefcbe178efedde0bde6b08f67e5afed5d669840d1c151a653`) deletes that file, adds `[default]`, and no longer writes it early.
- That patch was written to `boot_b`. The patch boot left fastboot and returned to fastboot by itself after about 14 seconds. Then the Droidian `boot.img` (SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`) was written back and the phone rebooted. The slot was still `_b`. userdata, vendor_boot, dtbo, vbmeta, and super were not touched.
- The logo was about 2 seconds. `/linkerconfig/ld.config.txt` was deleted, and the container was still `ABORTING`. `lxc-android.log` is empty because `lxc-start -d` leaves the real error in a process that has already detached. The new `boot-patch.img` (SHA256 `0f1491344aff6dbbbd886cec94bcaf7310448d98ab06ad6cd5a6de9b8f8ce341`) switches to a foreground start and lands stderr in `/var/log/lxc-foreground.log`, and moves `libapexsupport.so` out of `/system/lib64` so only vendor processes keep it.
- That patch was written to `boot_b`. The patch boot left fastboot and returned to fastboot by itself after about 14 seconds. Then the Droidian `boot.img` (SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`) was written back and the phone rebooted. The slot was still `_b`. userdata, vendor_boot, dtbo, vbmeta, and super were not touched.
- The logo was still about 2 seconds. The foreground LXC log has only the repeated warning that `lxc.seccomp` is unsupported. No new information.
- Changed direction. The direct cause of the black screen: the logo is drawn by Plymouth through kernel DRM (`msm_drm`, 1080x2400@120). The kernel has no `DRM_FBDEV_EMULATION` and no fbcon. After Plymouth exits, the screen is black whenever phosh is not up. phosh is tied to the Android hwcomposer by Droidian's `20-wlroots-hwc-env.conf` and `40-droid-wait.conf`, and hwcomposer needs the Halium 12 system to run an Android 16 vendor's HALs. Treble only guarantees that system is not older than vendor. What this combination is missing is a whole generation of LL-NDK (`libapexsupport`, a new `libc++`, VINTF manifest 9.0, and so on). Filling in libraries one by one is not a path that converges.
- The new path is similar to Mobian: skip Android and run phoc directly on kernel DRM. The rootfs's own `libwlroots.so.12a` has a DRM backend and a pixman renderer. `phosh-session` already defaults to `WLR_BACKENDS=drm,libinput`. GL goes through glvnd, so Mesa can be selected. The new `boot-patch.img` (SHA256 `9679deaf2f5b9b7403d1dafb6b1ea08eaf8d5b1576df68c1be811e96da23fbba`) masks the two drop-ins above. phoc uses pixman, clients use Mesa software rendering and `GSK_RENDERER=cairo`, hybris `LD_PRELOAD` is cleared, and `DSI-1` is scaled by 3. Each phosh restart switches between legacy KMS (the interface Plymouth uses) and atomic. `lxc@android` and `android-service@hwcomposer` are masked. The original unit is kept at `lxc@android.service.stone-orig`. `android-mount` is still pulled in by `local-fs.target`, and vendor firmware still mounts. The rootfs was already 100% full. ext4's 5% reserved blocks are root-only, so the phosh user could not write a home directory. The patch deletes translations other than `en` and `zh`, deletes `/usr/share/doc`, and caps the journal at 48M.
- That patch was written to `boot_b`. The patch boot left fastboot and returned to fastboot by itself after about 16 seconds (about 2 seconds longer than before; deleting files takes time). Then the Droidian `boot.img` (SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`) was written back and the phone rebooted. The slot was still `_b`. userdata, vendor_boot, dtbo, vbmeta, and super were not touched.
- The logo lasted about 1–2 seconds, then the screen went black. The rootfs had 211M free. The journal has no phosh at all: `phosh.service` itself has no `[Install]` link. Droidian pulls it in only through `BindsTo=phosh.service` in `android-service@hwcomposer.service.d/20-phosh.conf`. After hwcomposer is masked, phosh is not in the boot transaction. Only an invisible tty1 getty remains, and the display is blanked when Plymouth exits at 6.6 seconds. A later `sed -i` also turned the `/dev/null` symlink of `lxc@android.service` into an empty file. The new `boot-patch.img` (SHA256 `17cc592ed19f1f1b49e42eabfed99159f1596c1a2333b1047cd06f43fc648c15`) adds phosh to `graphical.target.wants` and points the sed at `.stone-orig`. This failure has nothing to do with the Android 14 ROM.
- That patch was written to `boot_b`. The patch boot returned to fastboot by itself after about 11 seconds. Then the Droidian `boot.img` (SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`) was written back and the phone rebooted.
- **First time into the phosh desktop.** Display goes through kernel DRM, phoc uses pixman software rendering, there is no Android container, and touch works (the phone can be unlocked into the desktop). The patch changes the rootfs inside userdata, so later normal boots keep these changes. At this point the phone presented no USB device: the Droidian rootfs has no sshd, and USB networking was not configured. The kernel has `CONFIG_USB_CONFIGFS_NCM=y`, so USB networking can be done.
- Wi-Fi was unavailable, so the path changed to USB networking plus SSH. The new `boot-patch.img` (SHA256 `786b9b82b756f7f8310d783705c15bac8b12e20ad317a4946450a8e6284bbad0`) uses chroot + `dpkg` during the patch boot to install trixie's `openssh-server` offline, plus the 10 missing dependencies (debs and SHA256 checks are in `out/halium-droidian/debs/`). Host keys were generated on the computer so the phone would not wait for entropy early in boot. Only key login is allowed, for root and `droidian`. The private key is in `out/halium-droidian/ssh/`. `stone-usbnet.service` builds an NCM gadget with configfs: phone `10.15.19.82`, computer-side MAC `02:00:5e:10:15:19`. The phone's NetworkManager does not take this interface. A NetworkManager connection `stone-usb` was added on the computer, matched by MAC, static `10.15.19.100/24`, with no default route.
- That patch was written to `boot_b`, returned to fastboot after about 14 seconds, and the `dpkg` install succeeded. After the Droidian `boot.img` was written back, `enx02005e101519` appeared on the computer after about 10 seconds, and `ssh root@10.15.19.82` worked (the host key matched the one generated in advance). Helper script: `out/halium-droidian/ssh/phone`. Current state: phosh is running; 190M remains on the rootfs; the battery reading is normal (`battery` 100%, Full); `/dev/kgsl-3d0` and `/dev/dri/renderD128` are both present, so Mesa KGSL hardware acceleration can be tried; there is no `wlan0` (the WLAN driver is not loaded). The only failed units are `droidian-fpd`, `lxc-net`, `nfcd`, and `ofono`, all of which depend on the Android container.
- Decided to switch to Halium 14. Vendor uses the crDroid 14 package already checked as installable on sunstone, the system image uses UBports Halium 14, and the root filesystem uses Ubuntu Touch 24.04-2.x. Droidian has no published api34 files. The new roadmap is `docs/roadmap-halium14.md`. The Phosh experiment on the phone stops here.
