# Halium 14 and Ubuntu Touch 24.04


Align the vendor and the Halium system image inside the container on Android 14. The Linux root filesystem is Ubuntu Touch 24.04-2.x. Droidian 101 and the 2026-10-07 nightly did not publish a generic api34 root filesystem, so this document does not use Droidian.

The phone is still running the Droidian Phosh from the end of `docs/roadmap-04-05.md` (kernel DRM, SSH over USB networking). Until item 6, this document does not reboot, write partitions, or format userdata. Item 6 needs someone looking at the screen. Stop when execution reaches it.

## Decisions

- Stop using Droidian api32's `android-rootfs.img`. That image is Halium 12. Paired with the Android 16 vendor on this machine, vendor processes exit before they reach init because the LL-NDK does not match. The display HAL is still HIDL Composer 2.4. libhybris has not been reached yet.
- Vendor uses `third_party/crDroidAndroid-14.0-20241212-stone-v10.11.zip`, already in the workspace. The OTA assertion is `pre-device=moonstone,sunstone,stone`, so it can be installed on this sunstone. The fingerprint `POCO/moonstone_p_global` is the build product name of this unified `stone` tree. `post-sdk-level=34`, security patch 2024-12-01.
- The container system image uses UBports CI's generic Halium 14 arm64 package. The `halium-14.0` branch of `Halium/android` was still updated on 2026-05-18, and the porting scripts have carried this artifact's URL since 2025-04.
- The root filesystem is Ubuntu Touch 24.04-2.x. UBports' `prepare-fake-ota.sh` picks the root filesystem and the Halium version separately: 24.04-2.x corresponds to `ubuntu-touch-android9plus-rootfs-arm64.tar.gz`, and Halium 14 corresponds to a separate `halium_halium_arm64.tar.xz`. The android9plus in the filename is the channel's historical name.
- The kernel is `crdroidandroid/android_kernel_xiaomi_sm6375` branch `14.0`, commit `42e99ef7fcd885b2e8c2ebbc7e0c700f1294c52d`. `crdroidandroid/android_kernel_xiaomi_stone` now publishes only `16.0`. The running kernel comes from that 16.0 tree and stays with the previous document. This document does not overwrite `kernel/build/`.
- Flashing this zip replaces crDroid 16 inside `super`. The workspace has no complete crDroid 12.9 install package. `backups/2026-11-09-crdroid-12.9/` can only write boot partitions back.

Build products, the kernel tree, and the archives live in gitignored directories and are not committed.

## 1. Confirm the three pieces can still be downloaded

Goal: before downloading large files, confirm that the Halium 14 artifact, the Ubuntu Touch 24.04-2.x root filesystem, and the Android 14 kernel branch are still on Jenkins.

### Planned steps

1. Request the HTTP headers of the two URLs below. If either is 404, stop at this item. Do not switch to some other version and hope.
   - `https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%252Fporting%252Fcommunity-ports%252Fjenkins-ci%252Fgeneric_arm64/job/halium-14.0/lastSuccessfulBuild/artifact/halium_halium_arm64.tar.xz`
   - `https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%252F24.04-2.x/lastSuccessfulBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz`
2. Record the final redirected filename and `Content-Length`.
3. Confirm again that `14.0` of `android_kernel_xiaomi_sm6375` still points at `42e99ef7`.

### Implementation notes

2026-11-09: both URLs returned HTTP 200 directly, with no redirect.

- Halium 14: `halium_halium_arm64.tar.xz`, `Content-Length` 144311736, `Content-Type` `application/x-xz`.
- Ubuntu Touch 24.04-2.x: `ubuntu-touch-android9plus-rootfs-arm64.tar.gz`, `Content-Length` 971702706, `Content-Type` `application/gzip`.
- `14.0` of `android_kernel_xiaomi_sm6375` is still `42e99ef7fcd885b2e8c2ebbc7e0c700f1294c52d`.

### Events

- Requested the HTTP headers of both CI artifacts. Both were 200.
- Read the kernel remote branch again. The commit had not changed.

## 2. Download the Halium 14 system image and the Ubuntu Touch root filesystem

Goal: put both archives in `third_party/halium14/`, and confirm that one is an Android 14 system image and the other is an Ubuntu 24.04 root filesystem.

### Planned steps

1. Download the two files recorded in item 1. The directory is already in `.gitignore`.
2. Compute SHA256.
3. List the archive contents. From the system image, read `ro.build.version.sdk` and `ro.build.version.release`. From the root filesystem, read `/etc/os-release`.
4. Record the install layout: the filename of the system image and of the root filesystem. Item 6 writes the flash steps from this layout.

### Implementation notes

2026-11-09: both files were downloaded to `third_party/halium14/`, not into git.

- `halium_halium_arm64.tar.xz`, 144311736 bytes, SHA256 `1b1b42138618e34db740f324653b390dd69e067450f9fc453290fdf323c4915e`. The archive contains only `system/var/lib/lxc/android/android-rootfs.img` (453488640 bytes, ext4). `system/build.prop` inside the image is `lineage_halium_arm64-userdebug 14 AP2A.240905.003`, `ro.build.version.sdk=34`, `ro.build.version.release=14`.
- `ubuntu-touch-android9plus-rootfs-arm64.tar.gz`, 971702706 bytes, SHA256 `ec130c13231b5562e4ce360d555f1aee5769275b7c3b8eae9f89bfc03ec92562`. `/usr/lib/os-release` is Ubuntu 24.04.5 LTS, `VARIANT=Touch`, `VERSION_CODENAME=noble`. `/etc/os-release` points at that file. The archive comes from the 24.04-2.x CI job. The top of the root filesystem already has the `android/`, `userdata/`, and `system` mount points.

At install time, Halium's `android-rootfs.img` lands at `/system/var/lib/lxc/android/android-rootfs.img` in the root filesystem. The Ubuntu root filesystem is unpacked on its own. The concrete flash commands wait until item 6. This item writes no partitions.

### Events

- Downloaded the generic Halium 14 package and the Ubuntu Touch 24.04-2.x root filesystem.
- Read SDK 34 / Android 14 from the system image, and Ubuntu 24.04.5 Touch from the root filesystem.

## 3. Take the Android 14 kernel and check the panel

Goal: shallow-clone `14.0`, confirm it still uses `moonstone_defconfig`, and confirm the device tree contains this machine's m17 panel. Do not compile.

### Planned steps

1. Clone to `third_party/android_kernel_xiaomi_sm6375/`, `--depth 1 --branch 14.0`.
2. Confirm the defconfig path is `arch/arm64/configs/moonstone_defconfig`.
3. Search the device tree for `qcom,mdss_dsi_m17_38_0c_0a_fhdp_dsc_vid`. If it is not found, stop. Do not substitute another moonstone panel.
4. In this tree's `init/Kconfig`, check that `CONFIG_IPC_NS` still depends on `CONFIG_SYSVIPC` or `CONFIG_POSIX_MQUEUE`. The existing fragment `kernel/config/halium-sunstone.fragment` already enables `CONFIG_SYSVIPC` and can keep being used. If the dependency changed, stop.

### Implementation notes

2026-11-09: shallow-cloned to `third_party/android_kernel_xiaomi_sm6375/`, not into git. `HEAD` is `42e99ef7fcd885b2e8c2ebbc7e0c700f1294c52d`.

`arch/arm64/configs/moonstone_defconfig` is present. The panel node `qcom,mdss_dsi_m17_38_0c_0a_fhdp_dsc_vid` is in `arch/arm64/boot/dts/vendor/xiaomi/dsi-panel-m17-38-0c-0a-fhdp-dsc-video.dts`. In `arch/arm64/boot/dts/vendor/xiaomi/Makefile`, `moonstone.dtb` is the baseline DTB and `sunstone-overlay.dtbo` is the second entry, corresponding to `dtbo_idx=1`.

In `init/Kconfig`, `CONFIG_IPC_NS` depends on `SYSVIPC || POSIX_MQUEUE` and defaults to y. `kernel/config/halium-sunstone.fragment` enables `CONFIG_SYSVIPC`. The dependency matches the 16.0 tree, so the fragment can keep being used.

Nothing was compiled.

### Events

- Shallow-cloned `14.0` at `42e99ef7`.
- Checked the defconfig, the m17 panel, and the order of the sunstone overlay.
- Checked the `CONFIG_IPC_NS` dependency and kept the existing fragment.

## 4. Build the Halium kernel

Goal: with the tree from item 3 plus the existing Halium fragment, build an `Image` and a DTB that contains the m17 panel. Do not flash.

### Planned steps

1. Keep the toolchain that already built 5.4 in the previous document: Ubuntu clang, gcc 13.3.0 nolibc from `third_party/toolchain`, and `ld.lld`. If this machine does not have the AOSP clang from the Android 14 era, do not download an older clang separately. A compile error stops where it is.
2. Expand `moonstone_defconfig`, then merge `kernel/config/halium-sunstone.fragment`. The output directory is `kernel/build-14/`.
3. Build `Image` and `dtbs`. If qcacld reports `-Wimplicit-enum-enum-cast` again, resume with the previous document's `KCFLAGS=-Wno-implicit-enum-enum-cast` and say so in the notes. Any other error stops.
4. Confirm the DTB contains `m17_38_0c_0a`, and record the sunstone overlay's order in the Makefile.
5. Record the size and path of `Image` and the DTB.

### Implementation notes

2026-11-09: the build finished and nothing was flashed. Output is in `kernel/build-14/`, not in git, and it did not overwrite the 16.0 products in `kernel/build/` from the previous document.

Source differences and config differences are recorded separately. The kernel tree stays in gitignore. The config is `kernel/config/halium-sunstone.fragment`. The source is relative to `crdroidandroid/android_kernel_xiaomi_sm6375` branch `14.0`, commit `42e99ef7fcd885b2e8c2ebbc7e0c700f1294c52d`. Patches are in `kernel/patches/`. After the shallow clone, and before expanding the defconfig, run `git apply` in the kernel directory. Replace the paths with this repository's `kernel/patches/*.patch` according to where the tree was cloned. `git apply` accepts these files directly.

The toolchain is Ubuntu clang 21.1.8, gcc 13.3.0 nolibc from `third_party/toolchain`, and `ld.lld`. In `moonstone_defconfig`, `CONFIG_SYSVIPC`, `CONFIG_PID_NS`, `CONFIG_USER_NS`, `CONFIG_VT`, `CONFIG_DEVTMPFS`, and `CONFIG_FHANDLE` were originally off. After merging `kernel/config/halium-sunstone.fragment`, those plus `CONFIG_IPC_NS`, `CONFIG_VT_CONSOLE`, and `CONFIG_DEVTMPFS_MOUNT` are all y. The first time `merge_config.sh` was run from the repository root, it looked for `alldefconfig` in the wrong directory. After it was rerun inside the kernel tree, the result was written into `.config`.

clang 21 treats an enum conversion in qcacld as an error on the 16.0 tree. This build added `KCFLAGS=-Wno-implicit-enum-enum-cast` from the start. The link had only stack-frame-size warnings, plus two static `EXPORT_SYMBOL` warnings for `embms_tm_multicast_recv` and `ope_soc_info`. `Image` was produced.

Products:

- `kernel/build-14/arch/arm64/boot/Image`, 47860224 bytes, SHA256 `49df6f26aa062243737a1b593618135823f302af3b4392000eedc29c89e12cb2`
- `moonstone.dtb`, 441131 bytes, containing `qcom,mdss_dsi_m17_38_0c_0a_fhdp_dsc_vid`. The model is `Blair QRD NOPMI`, `qcom,msm-id` is `<0x1fb 0x10000 0x242 0x10000>`, and `qcom,board-id` is `<0x1000b 0x00>`
- `sunstone-overlay.dtbo`, 461 bytes, the second entry in the Makefile

### Events

- Merged the Halium fragment. The first `merge_config.sh` was not in the kernel directory. After it failed, it was rerun inside the kernel tree.
- Built `Image` and the DTB with the qcacld warning suppression.
- Confirmed the new DTB contains the m17 panel. Nothing was flashed.

## 5. Extract the boot partitions from the Android 14 package and build images that are not flashed

Goal: boot and vendor_boot use the ramdisk and command line from this Android 14 package. The kernel and DTB are replaced with the products from item 4. DTBO uses the one from the package. Do not run fastboot.

### Planned steps

1. Unpack `payload.bin` from the zip, read-only, and extract `boot`, `vendor_boot`, `dtbo`, and `vbmeta` to `out/halium14/stock/`.
2. Check magic and header version. Check whether the vendor command line and DTB still select the m17 panel, and whether the `dtbo` entry order still puts sunstone at index 1.
3. Use AOSP `mkbootimg.py` to build a new header v3 image into `out/halium14/`. boot reuses the package ramdisk. vendor_boot reuses the package vendor ramdisk and vendor command line, and replaces the DTB with the newly built one. Page size 4096. Addresses follow the in-package image: kernel `0x8000`, ramdisk `0x01000000`, tags `0x100`, dtb `0x01f00000`. If the in-package addresses differ, the in-package ones win, and that is written into the notes.
4. Unpack the new images and check magic, version, and size (boot under 128 MiB, vendor_boot under 96 MiB).
5. Compute SHA256. Do not write partitions.

### Implementation notes

2026-11-09: extracted `boot`, `vendor_boot`, `dtbo`, and `vbmeta` from `payload.bin` to `out/halium14/stock/`. `payload.bin` was deleted after it was unpacked. Nothing was flashed.

The in-package boot is header v3, OS 14.0.0, patch level 2024-12, empty command line. The kernel is 44558848 bytes, the ramdisk 17159058 bytes. vendor_boot page size is 4096, kernel `0x8000`, ramdisk `0x01000000`, tags `0x100`, dtb `0x01f00000`. The vendor command line is:

`androidboot.hardware=qcom androidboot.memcg=1 androidboot.usbcontroller=4e00000.dwc3 cgroup.memory=nokmem,nosocket loop.max_part=7 msm_rtb.filter=0x237 service_locator.enable=1 swiotlb=0 pcie_ports=compat iptable_raw.raw_before_defrag=1 ip6table_raw.raw_before_defrag=1 androidboot.init_fatal_reboot_target=recovery`

The DTB inside vendor_boot is three pieces concatenated: the SoC DTBs for Blair, Blairp, and Holi. All three board ids are 0. The panel is not in those three pieces. `dtbo.img` has 28 entries. The bootloader selects by `msm-id` and `board-id`, not by a fixed index 1. Index 1 is Blairp ATP. The entry that matches this machine's new DTB is 03: `Blair QRD NOPMI`, `board-id <0x1000b 0x00>`, `msm-id <0x1fb 0x10000 0x242 0x10000>`. So vendor_boot keeps the DTB, vendor ramdisk, and command line from the package, and `dtbo` and `vbmeta` also use the ones from the package. The new `boot.img` replaces only the kernel. Its ramdisk is byte-for-byte the same as the one in the package.

New images:

- `out/halium14/boot.img`, 65028096 bytes, under 128 MiB. Header v3, OS 14.0.0 / 2024-12, kernel 47860224 bytes. SHA256 `cbade73955c22ad1a2c0eef1ae98a9621d93aebf9260d8a06cd26a25cb3ae565`
- `out/halium14/vendor_boot.img`, 1687552 bytes, under 96 MiB. DTB and vendor ramdisk are byte-for-byte the same as in the package. SHA256 `e60da5a06edebee4e6f3ba9cc35826537e8ea11c9cf1e74ad1ef835ea338650f`
- In-package `dtbo.img` SHA256 `dd48023792fe91dbc1feded3f52bd97be0bf733dd733d4accbbed23c689ae6d4`
- In-package `vbmeta.img` SHA256 `3b0ac2e7d8d82b586ab86390f893a41212a2ac963eebd6901b4010bcbdd18f2c`

The payload also has `odm`, `product`, `system`, `system_ext`, `vendor`, and `vbmeta_system`. There is no separate `super`, and no userdata.

### Events

- Extracted boot, vendor_boot, dtbo, and vbmeta.
- Unpacked the vendor DTB and the 28 dtbo entries. Confirmed sunstone is not index 1. The board-id match is entry 03.
- The new boot replaces only the kernel. vendor_boot keeps the device tree from the package. fastboot was not run.

## 6. Manual test: flash Android 14, then switch to the Halium boot image

Goal: first get this sunstone running a vendor of the same generation as Halium 14, then switch to the boot image from item 5. Stop before executing, and wait until a person puts the phone into flash mode and confirms that `super` may be replaced.

### Planned steps

1. Turn the system-image and root-filesystem layout seen in item 2 into concrete flash commands, and write them into the implementation notes. Write the commands. Do not run them.
2. Tell the user: this step replaces `super`. The workspace cannot put crDroid 16 back. The Droidian root filesystem currently on userdata will also be replaced when Ubuntu Touch is installed. The user has confirmed userdata has no personal files to keep.
3. Wait until the user puts the phone into fastboot or recovery and explicitly says it may be flashed.
4. After the flash, the user looks at the screen. If it does not enter the system, sticks on the logo, or stops in fastboot, read logs first. Do not reflash in a loop.

### Implementation notes

2026-11-09: stopped here. The commands below were not executed.

This step replaces crDroid 16 inside `super`. The workspace has no complete 12.9 install package. `backups/2026-11-09-crdroid-12.9/` can only write boot partitions back. The payload does not contain userdata. The Droidian root filesystem currently on userdata stays for now. The Ubuntu Touch root filesystem is installed after this boot has a result.

Do the following only after the user puts the phone into fastboot and explicitly says it may be flashed:

1. Unpack `odm`, `product`, `system`, `system_ext`, `vendor`, and `vbmeta_system`, which are still in the payload and have not been extracted, into `out/halium14/stock/`.
2. Enter fastbootd. Keep the slot at `_b`.
3. Write those five logical partitions and `vbmeta_system` to the current slot from the in-package images.
4. `dtbo_b` and `vbmeta_b` use the in-package images. `boot_b` uses `out/halium14/boot.img`. `vendor_boot_b` uses `out/halium14/vendor_boot.img`.
5. Reboot. The user looks at the screen. If it does not enter the system, sticks on the logo, or returns to fastboot, read logs first. Do not reflash in a loop.

### Events

- Wrote the flash order. The phone was not put into fastboot, and no partitions were written.
- After the user entered bootloader fastboot, `fastboot reboot fastboot` was run first. The phone did not enter fastbootd. It booted the current Droidian. The current `boot_b` is the Droidian image, and its ramdisk has no `fastbootd`. The in-package Android 14 boot ramdisk is gzip and contains `system/bin/fastbootd`. No partitions were written. The next step was changed: from the bootloader, write boot, vendor_boot, dtbo, and vbmeta first, then enter fastbootd and write the logical partitions.
- 2026-11-09: in that order, wrote `boot_b` (`out/halium14/boot.img`), `vendor_boot_b`, `dtbo_b`, and `vbmeta_b`. The slot stayed `_b`. `fastboot reboot fastboot` then entered fastbootd. `fastboot getvar unlocked` was no, and resizing `odm_b` was rejected. In the bootloader, `unlocked: yes` and `Device unlocked: true`. fastbootd decides locked by whether `ro.boot.verifiedbootstate` equals `green`. Adding `androidboot.verifiedbootstate=orange` to the vendor command line still left it at no. After the comparison string `green` inside the ramdisk's `system/bin/fastbootd` was changed to `xxxxx`, fastbootd reported unlocked: yes.
- Logical partitions: `system_b`, `system_ext_b`, `product_b`, and `vendor_b` were written successfully. `odm_b` failed the first time. `super` still held the previous virtual A/B `*-cow` set. After deleting `system_b-cow`, `system_ext_b-cow`, `product_b-cow`, `vendor_b-cow`, and `odm_b-cow`, `odm_b` and `vbmeta_system_b` were written successfully. userdata was not touched. Then `fastboot reboot`.
- After the reboot it entered Android recovery: Can't load Android system. Your data may be corrupt. On the computer, adb could see the device but it was unauthorized, so a wipe command could not be sent. userdata was still the previous Android 16 encrypted filesystem, which Android 14 cannot mount. The user confirmed the data did not matter and did a Factory reset on that screen.
- After the wipe, the system could boot. The boot animation was normal. After the lock screen, the screen went fully black. The lock-screen sound and the charging chime were both present, and touch worked. The partition flash succeeded. The black screen happened after the boot animation handed the display to the lock screen.
- After comparing `IKCONFIG` from the in-package `boot.img` with `kernel/build-14/.config`, the original in-package `boot.img` was written back to `boot_b` first. The UI was normal this time, which confirmed the black screen came from the kernel we built, not from the system partitions. This machine's fingerprint reader is on the power key, not under the display. Treating `FINGERPRINT_GOODIX_FOD` as the cause of the black screen was wrong.
- The running stock kernel is `5.4.259-qgki-g3ad529ef5970`, built 2024-08-09 by Xiaomi pangu with clang 11. `ro.crdroid.build.version` is `crDroidAndroid-14.0-20241212-stone-v10.11`. Our `Image` is `5.4.283~positron/42e99ef7`, clang 21. Commit `3ad529ef5970` is not on `14.0` of `crdroidandroid/android_kernel_xiaomi_sm6375`. The command line has `androidboot.dtbo_idx=3`. The panel is `qcom,mdss_dsi_m17_38_0c_0a_fhdp_dsc_vid`. The user has enabled root adb.
- The kernel log of the first black screen reported `esd check failed report PANEL_DEAD` after the boot animation ended. The source is a crDroid patch inside `sde_encoder_kickoff()` that deliberately calls `_sde_connector_report_panel_dead()` on the first frame. After that stretch was removed and the kernel rebuilt (`#2`, SHA256 `0177473a38c6f201c5857239f27cccba234289d10e191a9ea69de547212ee87e`) and written back to `boot_b`, a screenshot could see the lock screen, and `PANEL_DEAD` no longer appeared.
- The screen then lit and went black again. That was power management turning the panel on and off, not a composition failure. `blank:3` is the 120/60 refresh-rate switch. The real panel-off is `blank:1`. In logcat, `Going to sleep due to power_button` was immediately followed by `WAKE_REASON_POWER_BUTTON`, and the kernel side was `PMIC input: KPDPWR`. There was also a 30-second timeout into Doze, and lift-to-wake. `svc power stayon true` was run so the timeout would not turn the screen off again.
- The user added: when nothing is touched, the screen stays lit. As soon as it is touched, it flickers within a second or two and then goes black. The current `#3` kernel does the same. In the log, 15 milliseconds after a finger press, `dsi_display_set_mode fps=120` runs. Before that it was sitting at 60. A software-injected tap also switches the refresh rate, but the panel can still draw the UI. After both `settings system peak_refresh_rate` and `min_refresh_rate` were written as `60.0`, the display mode stayed at 60Hz and stopped switching back and forth.
- Kernel `#3` (SHA256 `35f5278fb781709296dee99187bc885b04b4af56d600bc38bc14428e5daa3b49`) removed `dsi_set_backlight_control()` from `sde_encoder_kickoff()`. After locking 60Hz, the user still saw flicker and then black as soon as they touched. Neither the refresh-rate switch nor this command is the cause.
- Between 15:36 and 15:51 Android had no screen-off, Doze, or power event. `mState=ON`, and the user still saw a black screen after touch. So the black screen happens on the panel, not in Android power management. Around the touch the kernel has only the touch report. There is no `PANEL_DEAD`, `blank`, or modeset. `sde_encoder_underrun` in tracefs did not fire either. Separately, one screen-off at 15:52:02 was `Going to sleep due to application (uid 10418)`, the Launcher3 double-tap to lock the screen. That is normal behavior. Do not mix it with this fault.
- What lines up in time is brightness: at 15:45:32.123 `DisplayPowerController` rose from a dimmed 0.05 back to 0.26, and the touch gesture was 34 milliseconds later. Touch only brought the screen back from the dimmed state. The brightness ramp over the next second or two is the flicker.
- The root cause is in the device tree. In crDroid 16's `vendor_boot` dtb, this panel has `qcom,mdss-dsi-bl-inverted-dbv`. Entry 3 of the stock Android 14 `dtbo` does not have that property. It only has Xiaomi's own `qcom,mdss-dsi-bl-dcs-type-ss-ea`. The crDroid kernel (both the `sm6375` and `stone` trees) recognizes only the former. Without it, `mipi_dsi_dcs_set_display_brightness()` sends the low byte first, and the panel reads it as high byte first. 544 (0x0220) arrives at the panel as 0x2002, which as 11 bits is 2, nearly full black. The dimmed 111 (0x006F) becomes 0x6F00, which is bright instead. That is why it is bright when untouched, and flickers then goes black as soon as it is touched.
- Verified without a rebuild: wrote 514 (0x0202, both bytes the same, so byte order does not matter) to `/sys/class/backlight/panel0-backlight/brightness`. The user confirmed the screen was normal, stable, and at a moderate brightness.
- In the crDroid 16 dtb, exactly the two m17 panels that carry `ss-ea` also have `inverted-dbv`. The other panels already had it. So in `dsi_panel_parse_bl_config()`, `qcom,mdss-dsi-bl-dcs-type-ss-ea` is also treated as `bl_inverted_dbv`. At the same time `dsi_set_backlight_control()` was put back into `sde_encoder_kickoff()`. Both the stock kernel and the crDroid 16 kernel send the bc command according to the refresh rate. The first-frame `PANEL_DEAD` stretch stayed removed.
- Kernel `#4`, SHA256 `7fcc1d7a0e5661972ff5c702fb79c69d271b2b7bc5fe995c4e1a620a34820bfe`, was written to `boot_b`. `peak_refresh_rate` and `min_refresh_rate` were deleted, and `screen_off_timeout` was restored to 30000. The user unlocked, swiped, opened apps, dragged the brightness slider, and turned the screen on and off with the power key. The screen stayed stable, and the brightness slider was smooth. The display problem is solved.
- Then the earlier attempts were cleaned up. Removing the first-frame `PANEL_DEAD` in `#2` was a misdiagnosis: the black screen after the boot animation was the same brightness byte order. Android writes 544 at exactly that moment. The crDroid 16 kernel keeps that stretch, so `sde_encoder.c` was restored to upstream with `git checkout`. Relative to `42e99ef7`, the kernel tree has only the `ss-ea` fix in `dsi_panel.c` left. On the phone, `svc power stayon false` was run (`stay_on_while_plugged_in` back to 0), and `screen_off_timeout` went back to 30000. `peak_refresh_rate` is crDroid's default `Infinity`.
- Kernel `#5`, SHA256 `756be6253b146699794ef892762426107b502aca570c5003611e7c66c8c6fb98`, was written to `boot_b`. At 11.9 seconds of boot it reported `PANEL_DEAD` once, which is the expected behavior of that patch, and then `mState=ON`. The user confirmed the display is as stable as `#4`.
- The brightness byte-order change does not stay only inside the ignored kernel tree. It was exported as `kernel/patches/0001-dsi-treat-xiaomi-ss-ea-as-inverted-dbv.patch`. The baseline is the `42e99ef7` above. `git apply` was checked on a clean tree. After it applies, it matches `dsi_panel.c` in the current `third_party/android_kernel_xiaomi_sm6375/`.

## 7. Prepare Ubuntu Touch userdata and the boot image

Goal: the Android 14 from item 6 is already running on this sunstone, and the display works. This item prepares an Ubuntu Touch 24.04 ext4 and a matching boot on the host. Do not write partitions and do not reboot. Writing to the phone and looking at the screen are the next manual test.

### Planned steps

1. Check the path of `android-rootfs.img` against the mount scripts in the root filesystem. If it disagrees with the location item 2 read from the archive path, the script wins.
2. Unpack the Ubuntu root filesystem into an ext4. The image is smaller than userdata and covers only the start of the partition. Put Halium's `android-rootfs.img` where the script looks for it.
3. Build an initramfs with the existing aarch64 static busybox. Find the partition by `PARTNAME=userdata`, mount it as ext4, and `switch_root` into `/sbin/init`.
4. Pack a header v3 boot with the `#5` kernel that already contains the brightness patch. Do not rebuild `vendor_boot`. The DTB stays the one already in the slot.
5. Check the image contents. Do not run fastboot.

### Implementation notes

2026-11-09: both images are in `out/halium14/`, not in git. Nothing was flashed.

The path `/system/var/lib/lxc/android/android-rootfs.img` written in item 2 is the path inside the Halium package. In the Ubuntu root filesystem, `/system` is a symlink to `/android/system`. `usr/libexec/lxc-android-config/mount-android-system` actually looks, in order, at `/var/lib/lxc/android/android-rootfs.img`, `system.img`, and the same names under `/userdata/`. When it finds `android-rootfs.img` it loop-mounts it at `/android`. That image has its own `/system` directory inside. So what goes in the image is `/var/lib/lxc/android/android-rootfs.img`, 453488640 bytes.

The root filesystem's `/init` is jumpercable. It wants to mount a partition named userdata a second time, for writable data, and by default that is not the same partition as the root. This time the userdata partition itself is the Ubuntu root filesystem, so the initramfs does not run that `/init`. It enters `/sbin/init` directly. `vendor` and `odm` are logical partitions in `super`. This initramfs does not create device-mapper nodes. `mount-android-partitions` only looks by partition name and under `/dev/mapper/`. On the first boot the container is likely still unable to see vendor.

The unpack used fakeroot and did not need host root. `mke2fs` is `/usr/sbin/mke2fs`, not the one in the SDK. Owners and permissions from the archive were kept in the image. File capabilities were not preserved this time. The unpacked tree was left at `out/halium14/rootfs-tree/`.

Products:

- `out/halium14/userdata-ut.img`, 8 GiB, ext4, label `userdata`, UUID `20175c14-63c9-49f3-a991-dc8abb53545c`. About 4.6 GiB free. About 70,000 inodes used, out of 1048576. `/usr/lib/os-release` is Ubuntu 24.04.5 LTS, `VARIANT=Touch`. SHA256 `5e105a81f5459d83fbcd7779a2295c91d000386e87f6050676a3f4d48f9b645b`.
- `out/halium14/boot-ut.img`, header v3, OS 14.0.0 / 2024-12. The kernel is `#5` (SHA256 `756be6253b146699794ef892762426107b502aca570c5003611e7c66c8c6fb98`), ramdisk 745443 bytes, lz4. The whole boot is 47 MiB, under 128 MiB. SHA256 `d7f4a8ec27235166b1e05dd3b916fb17004853a630fb99fefa8e4adf5c95a9ab`.

The phone is still the Android 14 from item 6, slot `_b`. `boot_b` is the `#5` kernel plus the Android ramdisk. `vendor_boot_b`, `dtbo_b`, `vbmeta`, and `super` stay as they are. They are written only at the next manual test. After the user puts the phone into fastboot and confirms userdata may be overwritten:

1. `fastboot flash userdata out/halium14/userdata-ut.img`
2. `fastboot flash boot_b out/halium14/boot-ut.img`
3. `fastboot reboot`, and the user looks at the screen.

If it does not enter the system, sticks on the logo, or returns to fastboot, read logs first. Do not reflash in a loop. To return to Android 14, write `out/halium14/boot.img` back to `boot_b`, and userdata still has to be reformatted as encrypted f2fs in recovery.

### Events

- Moved where `android-rootfs.img` lands, following the mount script, and no longer using `/system/var/...`.
- Built an 8 GiB ext4 and a 47 MiB boot. fastboot was not run, and the phone was not rebooted.
- 2026-11-09: the user put the phone into fastboot. `current-slot` was `b`, `unlocked: yes`. `fastboot flash userdata` first reported `Invalid sparse file format at header magic`, then sent the raw ext4 in 5 chunks. Every Writing was OKAY. Total time 90.9 seconds. Writing `out/halium14/boot-ut.img` to `boot_b` was also OKAY. The slot was still `_b`. `vendor_boot`, `dtbo`, `vbmeta`, and `super` were not touched. Then `fastboot reboot`. The user looks at the screen.
- The phone stuck on the Redmi first splash. There was no USB device. The user returned to fastboot by hand. The `boot-ut-logs.img` written next (mount ext4 first, then open an ACM serial port) also stuck on the first splash, and the host kernel log (`journalctl -k` is readable) had no enumeration either.
- The root cause is the ramdisk directory skeleton, not the kernel. On a header v3 boot the bootloader concatenates the vendor ramdisk and the boot ramdisk and unpacks them together. The Droidian attempt used crDroid 16's `vendor_boot`, whose vendor ramdisk already has a full Android root (`proc`, `sys`, `dev`, `tmp`, and so on). The Android 14 `vendor_boot` now in the slot has only `first_stage_ramdisk/` and `lib/`. Our busybox cpio also had only `bin/` and `init`. So the `/proc`, `/sys`, and `/dev` mount points did not exist, every mount failed, and there was no `/dev/console`. Without `/sys/class/block`, userdata could not be found, and init entered an invisible `sh`. Without `/sys/class/udc`, the log image could not bring USB up either. Android 14's own boot ramdisk has these directories, so the same kernel plus the same `vendor_boot` can enter Android. Droidian could reach the second splash because it happened to borrow the directories from the crDroid 16 vendor ramdisk. The kernel drivers are not the cause: the UFS, clock, and pinctrl modules in the vendor ramdisk are built into `#5`.
- Fix: `build-boot-image.sh` puts `proc`, `sys`, `dev`, `tmp`, `config`, `newroot`, and similar directories into the cpio, and uses fakeroot to create `dev/console` and `dev/null`. Host root is not required. init also `mkdir -p`s before mounting. On failure, init no longer enters a silent shell. It opens a `0525:a4a7` serial port (product name `boot-fail`) and loops the report and dmesg. Before `switch_root` it writes the initramfs report and dmesg to `stone-initramfs-report.txt` and `stone-initramfs-dmesg.txt` at the userdata root.
- The new `boot-ut.img` (ramdisk 746261 bytes, lz4, SHA256 `76fcd43d0d52bb51968e8bf36ab7a5dcc8e8a87542f6df10e81b4a5c880a701b`) was written to `boot_b` and the phone rebooted. Slot `_b`. The other partitions were not touched. For 90 seconds after leaving fastboot the host saw no USB device and no `boot-fail` serial port. UT's `usb-moded` default mode may not open a gadget at all, so this still cannot tell "systemd is already up" from "init is still failing."
- Separately built `out/halium14/boot-ut-disk.img` (SHA256 `151292b6fc31de170b487da1936b6a3656773eec30d444c05750a606027406df`), not yet written: mount userdata read-write so ext4 can replay, write `journalctl -b -1`, the whole journal, the boot list, and dmesg to `/stone-logs/`, then export userdata read-only as a USB disk (`1d6b:0104`, `stone-userdata`). The root filesystem's journal is persistent (there is `/var/log/journal`, and no volatile override).
- The user confirmed it was still stuck on the Redmi first splash and returned to fastboot. `boot-ut-disk.img` was written. Eight seconds after leaving fastboot, a `1d6b:0104` USB disk appeared. The host `udisksctl` mounted `/dev/sdb` read-only (103.5G, label userdata). That shows the corrected ramdisk runs on the `#5` kernel, and the USB gadget works.
- `stone-initramfs-report.txt` exists: at kernel time 2.0 seconds, init found `/dev/sda19`, mounted ext4, and `switch_root`ed. `journalctl --list-boots` listed only the boot from when the image was packed on October 12, because the phone clock is in 1970 and the new journal sorts in front and is ignored. The journal file written by this boot was found by its 1970 modification time and read with the host's `journalctl --file`: systemd was running normally, the journal hit disk at 2.5 seconds, and `local-fs.target` was reached. `mount-android-partitions` reported `Hmm... can't guess a partition for /android/vendor`. The start-post of `lxc-android-config.service` then waited until a 93-second timeout, and only after that did `systemd-udev-trigger` begin. Without vendor there is no Android container and no hwcomposer, so Lomiri cannot draw. The kernel has no fbcon, the command line has no `splash`, and Plymouth does not start. So the screen stays on the bootloader's Redmi picture.
- This is the known gap recorded earlier: `vendor` and `odm` are logical partitions in `super`. `find_partition_path` in `common.sh` looks first for `/dev/mapper/<name>` and `/dev/mapper/<name>_b`. Added `boot/ut-init/stone-dynparts.py`: it reads `super`'s geometry and metadata slot 1 (`_b`) in liblp format, skips `_a` and `-cow`, and uses `dmsetup create --readonly --noudevsync` (`DM_DISABLE_UDEV=1`) to create `/dev/mapper/vendor_b`, `odm_b`, and the rest. After init has moved `/proc`, `/sys`, and `/dev` into the new root, and before `switch_root`, it `chroot`s into the Ubuntu root filesystem and runs this with the python3 and dmsetup that rootfs already has. The result is written to `stone-dynparts.txt` at the userdata root. Parsing of the table was checked on the host with a fake `super` and a fake `dmsetup` built in the same format.
- The vendor command line ends with `ro`. When `/` has no fstab entry, systemd remounts it read-only from that. The boot image header command line gained `rw splash`.
- `boot-ut-trace.img` (command line also adds `printk.devkmsg=on`, SHA256 `a5b9b86e658deaf4461caf868c216071227e136a18d9c7521fe18c3503c51773`): `switch_root` into `/stone/init-wrapper`. In the background, every 3 seconds, it writes dmesg, the process table, systemd jobs, failed units, and this boot's journal to `/stone-logs/live/` and syncs, then `exec`s systemd. After about 3 minutes it reboots into the bootloader by itself. The new `boot-ut-disk.img` (SHA256 `ba5880a379d4d7c2e776be91c82f028fd8480498607c596519e88339418f6109`) also returns to the bootloader by itself after the host ejects the USB disk. Both carry `reboot-bootloader` (no libc, `reboot(..., "bootloader")`). The `boot-ut.img` used for a normal boot also carries dynparts and `rw splash`, SHA256 `012d829f9ccacd7c2e3ff8e8a1312d175b0d4406486cc19ec8a83fac8ad871f4`. None of them had been written yet.
- First trace: `stone-dynparts.py` correctly read `super` (`/dev/sda8`, LP metadata 10.2, 3 slots), but `PATH` inside the chroot was still the initramfs `/bin`, so it could not find `/usr/sbin/dmsetup`. Changed to an absolute path and set `PATH` explicitly. `chmod 644 stone-logs/*` in `init-disk` removed the execute bit from the `live/` directory. Changed to `chmod -R a+rX`, and also copied out the lightdm log, which only root could read.
- Lesson: ejecting the phone's USB disk on the host with `udisksctl power-off` powers off host USB port 1-9. Recovering that needs root and means replugging the cable. From then on, only udisks `Drive.Eject` (a gdbus call).
- After the vendor mapping succeeded, the container entered RUNNING. Kernel `#5` has no `SECURITY_SELINUX_BOOTPARAM`, so the command line cannot turn SELinux off. It also has no AppArmor, so UT's application confinement has nothing to load. `kernel/config/halium-sunstone.fragment` gained `SECURITY_SELINUX_BOOTPARAM`, `SECURITY_APPARMOR`, and `USB_CONFIGFS_RNDIS`, and `#6` was built (saved as `out/halium14/Image-6`; `#5` saved as `Image-5`). The boot command line became `rw splash selinux=0 security=apparmor apparmor=1`. The trace image also adds `printk.devkmsg=on`. On the phone, SELinux was confirmed off and AppArmor initialized. Neither `#6` nor `#7` has been tested on Android 14 yet.
- The vendor `vndservicemanager` `CHECK(selinux_status_open)` fails inside `Access::Access()` and aborts. Using the system servicemanager does not work: the system libbinder parcel header is `SYST` (0x53595354), vendor clients send `VNDR` (0x564e4452), and the system one cannot serve `/dev/vndbinder`. Added `boot/ut-init/stone-vendor-fixups.py`: on every boot, inside the chroot, it mounts `/dev/mapper/vendor_b` read-only, checks the SHA256 of `bin/vndservicemanager` (`bf6653db5e1384920732aa2f64a0de2abc297341d4b7775f950d0556b21b4a4f`, crDroid 10.11) and the original bytes, and replaces the `tbnz` at file offset 0x6128 (`8001f837`, the `selinux_status_open` failure branch) and the `cbnz` at 0x6134 (`c0030035`, the `getcon` failure branch) with NOP `1f2003d5`, written into the halium overlay. The remaining SELinux calls return "allow" when SELinux is off, and `getpidcon` works by borrowing AppArmor's label. The phone printed `bin/vndservicemanager: patched 2 sites`.
- Halium overlay: `mount-halium-overlay.service` runs after `mount-android-partitions` and before lxc. It bind-mounts every file under `/android/system/halium`, `/android/system/ubuntu`, `/opt/halium-overlay/`, and `/usr/share/halium-overlay/` onto the same path under `/` (the target must exist). The UT image itself has no `/usr/share/halium-overlay`. Added `boot/ut-init/rootfs-overlay/`. On every boot, init deletes the old `/usr/share/halium-overlay` and copies the whole tree into the root filesystem.
- After the vendor `vndservicemanager` was opened, every vndbinder transaction failed (`transaction failed 29201/-22`, binder.c line 3324). The vendor servicemanager sets `FLAT_BINDER_FLAG_TXN_SECURITY_CTX`. On 5.4 with only AppArmor, the secid is 0, `security_secid_to_secctx` returns -EINVAL, and binder fails the transaction outright. `kernel/patches/0002-binder-send-without-secctx-when-lsm-has-none.patch`: when the return is -EINVAL or -EOPNOTSUPP, keep sending without a security context. The receiver gets no SID and falls back to `getpidcon()`. Built `#7`: `kernel/build-14/arch/arm64/boot/Image`, 47999488 bytes, SHA256 `0ac98a87c24ad8dc64219de411bd7f1c8bd2f286906600eafd031ff5fd0a2c40`, `#7 SMP PREEMPT Mon Nov 9 18:22:33 EST 2026`. After that, the composer registered `display.qservice` and stayed running.
- USB: `CONFIG_USB_DUMMY_HCD=y` makes `dummy_udc.0` register before `4e00000.dwc3`. usb-moded picks the wrong controller, and the host sees no device. The overlay adds `etc/default/usb-moded.d/stone-sunstone.conf` (`CONTROLLER=4e00000.dwc3`) and `etc/usb-moded/91-stone-sunstone.ini` (`gadget_udc_device = 4e00000.dwc3`). The vendor `init.qcom.usb.rc` creates `g1/configs/b.1`, which conflicts with usb-moded's `c.1` (EBUSY). The overlay replaces it with an empty file that contains only a comment. When usb-moded runs with `-r` it enters developer_mode: RNDIS address 10.15.19.82, udhcpd hands out addresses, and `usb-moded-ssh` listens on 10.15.19.82:8022. At build time the host's `~/.ssh/id_ed25519.pub` (overridable with `SSH_PUBKEY`) is placed in the overlay's `home/phablet/.ssh/authorized_keys`. The public key does not go into the repository. The kernel has no f_mtp, so `mtp.mtp` does not exist. The `ethaddr` and `wceis` errors are only Mer property names and do not affect RNDIS.
- The trace image also carries `/etc/sudoers.d/stone-trace` (passwordless sudo for phablet). A normal-image boot deletes that file. `stone-init-wrapper` now snapshots every 3 seconds for the first 3 minutes, then every 30 seconds, and returns to the bootloader after 20 minutes. `sudo /stone/reboot-bootloader` returns immediately. The phablet user is in `/var/lib/extrausers`, is in the sudo group, and the password is unknown.
- Debugging: on the phone, USC (Mir 1.8.2, graphics-android2) initialized EGL on the Adreno 619, recognized the 1080x2400 screen, the spinner animation could be drawn, and lightdm also started the greeter. But `lomiri --mode=full-greeter` (phablet's user service `lomiri-full-greeter.service`) segfaulted about 0.5 seconds after `mirserver: Starting`. noble's arm64 gdb was downloaded from ports.ubuntu.com to `/tmp/gdb`. After core dumps were enabled, the backtrace was `strchr` ← `strstr` ← `egl_display_t::initialize` in Android `/system/lib64/libEGL.so` (+0x18d14, `ldr x0,[x20,#0x30]`, reading the extension string). Restricting glvnd to hybris only still crashed. This is unrelated to Mesa.
- Root cause: compared with the `egl_display_t` of a USC that was running normally, `+0x00` is the `_dpy` magic, `+0x08` is the handle, `+0x10` is state 1 (initialized), and `+0x18` through `+0x30` point at "Qualcomm Inc.", "1.5", "OpenGL_ES", and the extension string. Lomiri's copy had state 0, and those slots were uninitialized heap data: Adreno's own `eglInitialize` had failed, and Android libEGL then called `strstr` on an extension pointer that was never assigned. USC runs as root. Lomiri runs as phablet. `/dev/kgsl-3d0` and `/dev/ion` are both `crw------- root root`. UT ports usually generate udev rules from Android's `ueventd.rc`. That had not been done here.
- Fix: added `tools/ueventd-to-udev.py`, which turns the `/dev` entries of `/system/etc/ueventd.rc` and `/vendor/etc/ueventd.rc` into udev rules. Users and groups are written as numeric AIDs (in UT those groups are named `android_*`, and Android's names do not resolve). `oem_NNNN` takes the number directly. `ENV{DEVNAME}` matches the full path, and later files override earlier ones. The result is `boot/ut-init/rootfs-overlay/etc/udev/rules.d/70-sunstone.rules`, 249 rules. Installed on the phone and `udevadm trigger --action=add` was run. `/dev/kgsl-3d0` became 0666, and `/dev/ion` became 0664 (owner system). After restarting lightdm, `lomiri --mode=full-greeter` stayed running, there was no new core, the log had `Last frame took 66 ms to render`, and lomiri-polkit-agent registered.
- Still unsolved, and not blocking: apparmor.service fails to load profiles on 5.4; mediaextractor and qcrilNrd crash repeatedly; bluebinder fails; a host-side libgbinder client reports parcel header 0x6e0061; lomiri-push-service cannot start `com.ubports.SystemImage` (Permission denied); there is no f_mtp.
- Current images (all kernel `#7`, carrying every fix above; the image SHA256s in the earlier bullets are stale): `boot-ut.img` `40050592a624254a98b59bb52c3d60225237349ed70cda45b60647461ba79d71`, `boot-ut-trace.img` `c1edcee521aa0220382bdff3fa4581969153bf8f9949a15d78811ca059caebc1`, `boot-ut-disk.img` `13102777c80e72f8e134b135bb666f26d99b184c627ff88208494d640deeed81`. The phone was running the previous trace image at that moment. The udev rules had been installed live into `/etc/udev/rules.d/`. The user looks at the screen next.
- After the user returned to fastboot, the trace image that includes the udev rules was written. Fifteen seconds after a cold boot, SSH was up, `/dev/kgsl-3d0` was already 0666, Lomiri was running normally, and there was no core. `mirscreencast -m /run/mir_socket -n 1` can capture one 1080x2400 RGBA frame (it needs `GLIBC_TUNABLES=glibc.rtld.optional_static_tls=4194304`, otherwise hybris `q.so` reports that static TLS is not enough; the phablet user can capture too). The picture is the "Language" page of the Lomiri first-start wizard. The status bar has Wi-Fi, battery, and the clock. The touchscreen `fts_ts` (`event3`), the power key, and the volume keys are all opened by USC. The Lomiri log has `Input device added: "fts_ts" ... TouchScreen`.
- Why `apparmor.service` failed: `ExecStartPre`'s `wipe-aa-cache-on-channel-switch.py` (lxc-android-config) returns 1 on a system that is not a system-image install. A manual `apparmor.systemd reload` can load 159 profiles. The overlay adds `etc/systemd/system/apparmor.service.d/stone-no-system-image.conf`, which prefixes `ExecStartPre` with `-` so the failure is ignored, and the service becomes active.
- When the root filesystem was unpacked, tar mapped owners by name and used the host's IDs: `messagebus` 106→995 (`dbus-daemon-launch-helper` lost the messagebus group, so every system-bus activation is Permission denied, and lomiri-push-service cannot start), `clickpkg` 107→102 (5847 preinstalled entries under `/usr/share/click` became the crontab group), `syslog` 103→992 (`/var/log`), `systemd-journal` 105→109 (`/var/log/journal` became the rtkit group), `/var/lib/usermetrics` 104→991. Also, the file capabilities of `ping` (`cap_net_raw`) and `gst-ptp-helper` (`cap_net_bind_service,cap_net_admin,cap_sys_nice`) were lost. On the phone, 5850 entries were corrected to the numeric IDs from the archive (setuid bits kept) and the two capabilities were restored. `com.ubports.SystemImage` can activate, lomiri-push-service became active, and phablet can ping. `build-userdata-image.sh` was changed to `tar --numeric-owner`, and after mke2fs, `debugfs ea_set` writes the archive's `security.capability`. The rebuilt `userdata-ut.img` SHA256 is `382c9ff049bae13168a6dca8d42600446bba9fae15e8861df0f06b487a3ae551`. Owners and capabilities were checked with debugfs. It was not written (userdata on the phone had already been repaired in place).
- The user service `audiosystem-passthrough-qti` (IQcRilAudio, call audio) exits with status 2 after it finds the hwbinder service manager. Left for the call-audio stage.
- Current images: `boot-ut.img` `7817dbfd45d4fa86b8a977f6504ba11ceb66aabc64b0b7b1c3884ea4596ef264`, `boot-ut-trace.img` `5da875e07435848fb10dc3213a949eb4c4856c1849a7e792d14582fdce580365`, `boot-ut-disk.img` `3c1123f228b93116dbe94f325fa731ac3e34ef9826299535985601d01faebd02`. `boot_b` has been written with the normal `boot-ut.img` (no passwordless sudo, and it does not reboot itself after 20 minutes). At 73 seconds of boot, Lomiri was running, AppArmor was active, there were no failed system units, and the screenshot was still the first page of the wizard. usb-moded's `-r` comes from the root filesystem configuration. Under the normal image, phablet can still SSH with a public key to 10.15.19.82:8022. Next, the user operates the wizard on the screen and tests touch. The phone clock is still in 1970.
- 2026-11-09: the user confirmed Ubuntu Touch had reached the desktop. Display, touch, GPU, brightness, charge detection, and vibration are normal, and adb is connected. Wi-Fi, Bluetooth, SIM, camera, sound, and internal storage capacity are not done. The Halium 14 line stops here. What remains is in `docs/roadmap-hardware.md`.
