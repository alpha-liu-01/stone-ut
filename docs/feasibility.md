# Feasibility of Droidian / Ubuntu Touch on the Redmi Note 12 5G (sunstone)


Probe date: 2026-11-09. Read-only: nothing was flashed and the phone was not rebooted. ADB serial `stone`. The first half used an ordinary `shell`. Partition images and `lpdump` were taken later, after the user authorized Magisk root.

Reference: `docs/clue.md`. The text below follows it only where this probe and the public device tree agree. Where they disagree, this probe wins.

## Conclusion

This machine is worth porting, and the port should be Halium. Do not start from a mainline kernel or Freedreno.

Graphics is more favorable than `clue.md` feared. The running display HAL is still HIDL Composer 2.4, and the GPU userspace is a 2022 Adreno 619, not Android 16's AIDL HWC3. libhybris knows this interface set.

What actually constrains the install is the partition layout, not the GPU. `super` contains only slot B's dynamic partitions. The rest is filled by virtual A/B COW snapshots, and `system_a` does not exist. Slot A has a set of boot images, but switching to it has no matching system partitions. The first Linux install replaces crDroid's system, or consumes the encrypted userdata. Rollback means flashing the crDroid package and the boot images exported beforehand. It cannot rely on "the other slot is still good."

Keep a single repository for now: this one, `stone-ut`. Fork the kernel repository only when kernel changes start. Do not open a device-tree repository yet.

Suggested order: Droidian first (Debian + Phosh). Put an Ubuntu Touch rootfs on the same Halium boot only after that boot is stable. Phone, camera, fingerprint, and deep sleep stay out of the first stage.

## What this machine is

| Item | Measured |
| --- | --- |
| Model | Redmi Note 12 5G, SKU `sunstone_cn` |
| Product / device name | `sunstone`; the crDroid device id is the unified tree `stone` |
| SoC | SM4375, platform `holi`, QTI |
| CPU | 6× Cortex-A55 (0xd05) + 2× Cortex-A78 (0xd41), arm64 |
| GPU | Adreno 619v2, node `/dev/kgsl-3d0` |
| Memory | MemTotal 7,612,520 kB, about an 8 GB part |
| Storage | userdata about 104 GB, 31 GB used, 72 GB free; f2fs, file-based encryption |
| Battery | 5000 mAh design capacity, Li-poly |
| Screen | 1080×2400, 440 dpi, about 392 dpi physical density, OLED, 60/120 Hz, corner radius 102, punch-hole at the top |
| Panel | Kernel command line selects `qcom,mdss_dsi_m17_38_0c_0a_fhdp_dsc_vid`. Panel name "xiaomi m17 38 0c 0a fhd dsc video dsi panel" |
| System | crDroid 12.9, display version `v12.9-20260416`, Android 16 (SDK 36, `BP4A.251205.006`) |
| Security patch | system 2026-04-01, vendor 2026-02-01 |
| Kernel | `5.4.302-qgki-g06497b244a0e`, PREEMPT, built 2026-04-16 15:36 EEST, clang 21.0.0 |
| Baseband | `.4.c2-00029-MANNAR_GEN_PACK-1.34701.2.35423.3` |
| Current slot | `_b` |
| Root | Magisk 30.6. `adb shell` is still uid 2000; after `su` it is `u:r:magisk:s0` |
| SELinux | Enforcing |

Both `ro.product.first_api_level` and `ro.vendor.api_level` are 31, so the factory baseline is Android 12. The running vendor image was built by crDroid for SDK 36, and the fingerprint string still says `Redmi/sunstone/sunstone:14/UKQ1.240624.001/OS2.0.6.0.UMQCNXM`. Read HAL versions, not that fingerprint.

The public device tree `crdroidandroid/android_device_xiaomi_stone`, branch `16.0`, says `TARGET_KERNEL_CONFIG := moonstone_defconfig`, `TARGET_KERNEL_SOURCE := kernel/xiaomi/sm6375`, `BOARD_BOOT_HEADER_VERSION := 3`, and the OTA assertion devices are `moonstone,sunstone,stone`. This probe confirmed boot header v3 on the images of both slots. The defconfig name was not read out of the running kernel. When building, start from this BoardConfig and then diff against this machine's `/proc/config.gz`.

## Where this disagrees with clue.md

The broad direction in `clue.md` (Qualcomm, public source, Droidian first, Ubuntu Touch second) can stay. The following points follow this machine.

1. What is running is crDroid 12.9 (2026-04-16) from the unified `stone` tree, not the newer `gemstone` branch the document mentions. The port baseline follows this build.
2. `ro.vendor.build.version.sdk` is 36, not a stock Android 12 vendor. The display HALs did not follow that into AIDL HWC3. See the next section.
3. `verifiedbootstate=green`, `flash.locked=1`, and `vbmeta.device_state=locked` in `getprop` are spoofed system properties. The kernel command line says `androidboot.verifiedbootstate=orange`. The vbmeta header flags equal 3, meaning both verity and verification are off. The bootloader is in the unlocked custom-ROM state.
4. `clue.md` treats Mesa Freedreno as a later graphics path. `CONFIG_DRM_MSM` is not enabled in the running kernel. `/dev/dri/card0` and `renderD128` both belong to the downstream `msm_drm` of `5e00000.qcom,mdss_mdp` (compatible `qcom,sde-kms`). That is the display controller, not a Freedreno GPU node. The GPU goes through KGSL only.
5. "Phosh in 15–25 hours" is plausible only if boot packaging and UBWC both go smoothly. The partition layout makes "try, then roll back" more expensive than that estimate assumed.

## Boot images and partitions

Both physical slots use Android boot header v3, page size 4096. The headers were read. The full images were not pulled.

| Image | Header | Kernel | Ramdisk | OS field inside the image |
| --- | --- | --- | --- | --- |
| `boot_b` (current) | v3, header 1580 bytes | 48,105,472 bytes | 1,576,326 bytes | Android 16.0.0, patch level 2026-04 |
| `boot_a` | v3 | 48,103,424 bytes | 1,573,252 bytes | Android 16.0.0, patch level 2026-03 |
| `vendor_boot_b` | v3, page 4096 | — | vendor ramdisk 23,809,557 bytes | Command line starts with `androidboot.hardware=qcom` |
| `vendor_boot_a` | v3, page 4096 | — | vendor ramdisk 23,788,247 bytes | Same, slightly smaller |

Partition sizes (512-byte sectors):

| Partition | Size |
| --- | --- |
| `boot_a` / `boot_b` | 128 MiB each |
| `vendor_boot_a` / `vendor_boot_b` | 96 MiB each |
| `dtbo_a` / `dtbo_b` | 24 MiB each |
| `vbmeta_a` / `vbmeta_b` | 64 KiB each |
| `super` | 9,126,805,504 bytes, matching `BOARD_SUPER_PARTITION_SIZE` in the device tree |
| `userdata` | 217,087,640 sectors, about 103.5 GiB |
| `modem_b` | 180 MiB |
| `dsp_b` | 32 MiB |
| `bluetooth_b` | 1 MiB |

`dtbo_b` has the standard DTBO magic. The table has only 2 entries, and the whole image is about 1018 bytes. The current `dtbo_idx=1` and `dtb_idx=0`. The baseline DTB lives in the boot image. DTBO is only a small overlay. The baseline DTB contains several panels (m17, m17 k6s, nt36672e, Visionox, and others), which is what the shared stone/moonstone tree does. At runtime, follow `msm_drm.dsi_display0` on the command line. Do not adapt to the first panel in the table.

`vbmeta_b` magic is `AVB0`, algorithm type 2 (SHA256_RSA2048), flags 3: hashtree off, verification off.

The dynamic partitions `lpdump` saw are only:

- `odm_b`, `product_b`, `system_b`, `system_ext_b`, `vendor_b`
- and the matching `*-cow` partitions

There is no `system_a` / `vendor_a`. The COW partitions run from the back of `super` through the last sector. `super` has no free range and no second system. Logical partition attributes are `readonly,updated`, so the virtual A/B update has landed on slot B and the other side is occupied by snapshots.

Mounted filesystems: `system`, `system_ext`, `product`, `vendor`, and `odm` are all ext4. fstab accepts both ext4 and erofs. About 9 MB of 742 MB remains on `vendor`, and `system` is about 93% full. Do not stuff files into the existing vendor.

userdata is f2fs, `fileencryption=aes-256-xts`, plus metadata encryption and inlinecrypt. fstab has vold entries for microSD (`4784000.sdhci`) and USB OTG. There was no `mmcblk` during the probe. The slot was empty.

The kernel is monolithic. `/proc/config.gz` has no `=m`, `lsmod` is empty, and `/vendor/lib/modules` does not exist. Wi-Fi, touch, KGSL, and Bluetooth are built in. The 23 MB in `vendor_boot` is the Android first-stage ramdisk, not an out-of-tree module package.

## Halium gaps in the kernel config

The running config is readable, 6680 lines. Already enabled, and useful for a port:

- `CONFIG_ANDROID`, binderfs, binder/hwbinder/vndbinder, ashmem, ION system heap
- `CONFIG_NAMESPACES`, `CONFIG_UTS_NS`, `CONFIG_NET_NS`
- `CONFIG_CGROUPS`, `CONFIG_BLK_DEV_INITRD`, `CONFIG_EFI_STUB`
- `CONFIG_USB_CONFIGFS` and FunctionFS
- `CONFIG_QCOM_KGSL`, `CONFIG_DRM`, `CONFIG_DRM_MIPI_DSI`; display goes through downstream msm_drm
- `CONFIG_CLD_LL_CORE` (Wi-Fi built in), `CONFIG_BT_QCA`, `CONFIG_BT_HCIUART_QCA`
- `CONFIG_TOUCHSCREEN_FT3519T`, `CONFIG_TOUCHSCREEN_SYNAPTICS_DSX`
- `CONFIG_BUILD_ARM64_DT_OVERLAY`

Still missing for Halium / LXC / systemd, and needing to be turned on in the kernel:

- `CONFIG_PID_NS` is off. Without it, a container cannot start.
- `CONFIG_USER_NS` is off.
- `CONFIG_VT` is off.
- `CONFIG_DEVTMPFS` is off.
- `CONFIG_FHANDLE` is off. Debian systemd wants it.
- This config has no `CONFIG_IPC_NS` line. Whether the Qualcomm tree removed the option, or it is folded into `CONFIG_NAMESPACES` by default, has to be checked in the source. Mount namespaces likewise have no separate switch.

These are ordinary Halium kernel changes, not a dead end unique to this machine. The changes should be a small delta against crDroid `android_kernel_xiaomi_stone`, not a copy of the whole kernel in this repository.

The compiler that built this kernel is clang 21. The Android clang listed in the Droidian porting docs stops at clang 14, for Android 13. The first build should keep the toolchain that already built crDroid's `5.4.302`. Do not switch to the older clang from the docs first.

## Hardware and HALs

### Graphics

The GLES string reported by SurfaceFlinger is:

`Qualcomm, Adreno (TM) 619, OpenGL ES 3.2 V@0530.0 (GIT@c263890aed, Ifb496a9c37, 1656315076) (Date:06/27/22)`

`ro.opengles.version` is 196610, which is GLES 3.2. The Vulkan property is `adreno`. KGSL `gpu_model` is `Adreno619v2`.

`/vendor/etc/vintf/manifest/vendor.qti.hardware.display.composer-service.xml`:

- `vendor.qti.hardware.display.composer` HIDL 3.0
- `android.hardware.graphics.composer` HIDL 2.4
- `vendor.display.config` HIDL 2.0
- `vendor.display.color` HIDL 1.5

The mapper is HIDL passthrough. It registers mapper 3.0 and 4.0, plus QTI mapper 3.0/4.0. The comment says the source is `hardware/qcom-caf/sm8350/display`.

The current HWC layer format is `RGBA_8888_UBWC`. After libhybris loads HWC 2.4, the usual cause of a black screen is UBWC, not "there is no GPU node."

This combination (KGSL + HIDL HWC 2.4 + 2022 Adreno userspace) is a type Halium has done many times. It does not support taking the existing kernel and running KWin/Freedreno on it.

### Touch, keys, fingerprint

| Input device | Location | Notes |
| --- | --- | --- |
| `fts_ts` | i2c-2, address 0x38 | Touchscreen. dmesg Device ID `0x54`, FocalTech |
| `qpnp_pon` | PM6125 power-on | Power key |
| `gpio-keys` | platform device | Side keys |
| `holi-qrdsku1-snd-card Headset/Button Jack` | ALSA, q6core APR | Headset jack |
| `uinput-fpc` | virtual input | Fingerprint userspace. The kernel log says `fpc1020` |
| `uinput-goodix` | virtual input | The tree also has Goodix. The active driver on this machine is FPC |

The touch driver is built into the kernel and is already wired to DRM blank notifications. Phosh touch has a chance of working without a driver change. Fingerprint waits until much later.

### Wireless

`wlan0` and `wlan1` exist. The driver is `icnss2` on the platform device `c800000.qcom,icnss`. Firmware is in the `modem` partition at `/vendor/firmware_mnt/image`, dated 2023-10-18, including the board-data set `bdwlan.102` through `bdwlan.10e` and the ADSP/modem split images. Bluetooth firmware is in its own `bluetooth` partition, with `apbtfw11.tlv` and a set of `crbtfw*.tlv`.

The Wi-Fi HAL itself is already AIDL `android.hardware.wifi` version 3. Droidian does not have to go through that HAL. The kernel interface is already there. The first choice is wpa_supplicant on `wlan0` directly, with firmware still read from the modem partition.

### Audio, sensors, other

The sound card is `holi-qrdsku1-snd-card`, under `qcom,msm-audio-apr` / q6core. `/dev/snd` is a full set of Qualcomm compressed and PCM devices. This is the Android Audio HAL path, not an ordinary ALSA card. Audio will be slower than display.

Sensors: TDK icm4x6xx (accelerometer, gyroscope), QST qmc630x (magnetometer), ams tmd2755 (light and proximity). The remaining orientation and step counting come from Qualcomm SSC. There are also Xiaomi AOD and pickup sensors.

The manifest also has Lineage's infrared HAL, the default NFC service, and Xiaomi's fingerprint biometric HAL. fstab says there is a microSD slot. All of these are recorded only as "the hardware is present." Function was not checked item by item.

The health HAL is AIDL version 4. Charging and battery level can most likely still be read from the kernel power supply. Seeing a percentage does not depend on this HAL.

## Feasibility

Halium upstream still had `halium-11.0` through `halium-14.0` branches in May 2026. The public comparison table in the UBports porting introduction goes up to Halium 13 (LineageOS 20). The Droidian docs say devices from Android 9 onward can be done, and an Ubuntu Touch port that already has a Halium 9 or newer kernel can usually run Droidian.

This machine has no existing Droidian or Ubuntu Touch port. This is a new port, not an install of a finished image.

| Stage | Judgment | Basis |
| --- | --- | --- |
| Export boot / vendor_boot / dtbo / vbmeta, and keep the crDroid install package | Doable | Root can already read these partitions; both slots' boot images are still there |
| Build a bootable Halium kernel after enabling namespaces and the other switches | Fairly confident | 5.4, header v3, a monolithic kernel, and public source are all present; the toolchain must be able to build this qgki tree |
| Reach a Droidian shell / SSH | Fairly confident | An ordinary Halium target. The risk is that boot and vendor_boot must be a pair, and there is no system_a after a slot switch |
| Phosh, touch, GPU acceleration | Possible, but the first technical hurdle | HWC 2.4 + KGSL + the 2022 driver are favorable; UBWC and mapper 4.0 can still black-screen |
| Wi-Fi | Possible, after display | `wlan0` and the icnss2 firmware are both present; the regulatory domain and firmware path need separate handling |
| Audio, charge display, basic suspend | Audio is clearly harder | q6core / APR, not a simple sound card |
| Phone, camera, fingerprint, NFC, infrared | Not in the first stage | Qualcomm modem, FPC, and SSC all depend on Android HALs. The unit of work is weeks |
| Mainline kernel or Freedreno | Do not do | `CONFIG_DRM_MSM` is off. The GPU node is KGSL |

"Phosh in 15–25 hours" in `clue.md` covers only the smooth path: Halium accepts this vendor, no new HWC has to be written, and UBWC passes on the first try. If the kernel changes and boot packaging go well, SSH is a few days of work. If Phosh is blocked by UBWC or the mapper, it is weeks. An Ubuntu Touch that can be a daily phone is not in that budget.

Droidian and Ubuntu Touch share the kernel, vendor blobs, and Halium boot. Ubuntu Touch also needs Lomiri, a device configuration, and an OTA layout, so it is a second stage. It is not finished by swapping a rootfs.

## Repositories

Use only this repository for now.

`stone-ut` holds the documents, the Halium kernel config fragment, flash and backup scripts, the Droidian adaptation, and later the Ubuntu Touch device configuration. Userspace for the two systems lives in separate directories. Do not split them into two projects. Do not commit proprietary blobs or whole boot images.

Create the second repository when the kernel is first modified: a fork of `crdroidandroid/android_kernel_xiaomi_stone`, on a branch dedicated to Halium 5.4. The kernel is GPL, large, and tracks crDroid upstream. Putting it in this repository would distort clones and review. This repository only records its remote, branch, and config delta.

Do not create the third repository yet. That would be a fork of `android_device_xiaomi_stone`, needed only if this vendor's HIDL graphics stack cannot drive libhybris and an older vendor has to be rebuilt. The first stage uses this machine's vendor partition and modem firmware directly. crDroid's `proprietary_vendor_xiaomi-stone` is only a reference. Do not copy it into git.

## Roadmap

1. Back up, still without flashing. With root, export `boot`, `vendor_boot`, `dtbo`, and `vbmeta` for slots A and B. Also keep this crDroid 12.9 install package. Back up personal data separately. Confirm that you know how to fastboot the slot B boot image back and switch back to `_b`.
2. Store the running `/proc/config.gz` in this repository and write it up as a delta against `moonstone_defconfig`. Enable PID/USER namespaces, VT, DEVTMPFS, and FHANDLE, and check IPC and mount namespaces. Build the kernel with a clang that can already build crDroid 5.4.
3. Produce a header v3 boot and a paired vendor_boot. The DTB still goes in boot. Keep the current DTBO index 1, unless the kernel device tree changes the panel-selection logic.
4. An experimental boot replaces only boot-class partitions. Do not touch `super` or userdata. Slot A's old boot can be overwritten, but export it first. It is not a bootable old system. Once the new kernel can reach Halium init, decide where the rootfs goes.
5. The rootfs is Droidian. `super` has no room for a side-by-side install. userdata is encrypted f2fs. If Halium takes it, Android data is wiped. Before this step the backup must already have been shown to flash back. A microSD card is only a later candidate for the root filesystem. The slot was empty during this probe.
6. Connect HWC 2.4 and KGSL through libhybris, confirm `fts_ts`, then start Phosh. Wi-Fi uses `wlan0`. Charge state uses the kernel interface.
7. Swap in an Ubuntu Touch rootfs on the same boot, and add Lomiri and the device configuration.
8. Audio, phone, camera, fingerprint, and suspend are separate items. If one of them requires changing vendor or rebuilding the device tree, decide then whether to open the third repository.

## Risks

1. Switching to slot A does not produce a working crDroid. `super` has no slot A logical partitions. A mistaken slot switch looks like a failed boot. The fix is to write slot B's boot back and switch back to `_b`, provided those images were exported.
2. Installing a Linux rootfs destroys the current system or user data. `super` is full, so this cannot be a dual boot. COW still occupies the back half of `super`. Before changing dynamic partitions, understand the snapshot. Do not delete partitions as if this were ordinary A/B.
3. Vendor is almost full, and the system partitions are full too. Adaptation files belong in the rootfs. Do not remount vendor and copy them in.
4. A UBWC framebuffer can leave HWC loaded while the screen stays black. This is the main technical risk of the display stage.
5. The kernel was built with clang 21. An older Halium clang may fail to build, or build and then disagree with the existing vendor module interface. This machine also has no out-of-tree modules. An interface mismatch shows up first in display and Wi-Fi firmware loading.
6. The shared device tree covers sunstone and moonstone. The defconfig is named moonstone, and the panel table has several screens. The DTB that gets built must still select the m17 38 0c 0a panel, and `dtbo_idx` must still be 1.
7. The command line and vbmeta say verification is off, but properties are spoofed as locked/green. Later fastboot scripts must read the command line and vbmeta flags, not `getprop ro.boot.flash.locked`. Do not relock.
8. Any one of audio, modem, fingerprint, and camera can become weeks of work on its own. Their failure does not affect the first goal, "Phosh can light up," but it decides whether this machine can be used as a phone.
9. There is no official port. After it is done, maintenance follows crDroid's 5.4 kernel. If the stone tree stops, security fixes have to be carried locally.

## What this probe did not do

- No flashing, no slot switch, and no export of complete image files.
- Personal files in userdata were not read. The dmesg ring buffer had already wrapped, so early-boot panel and Wi-Fi probe logs were gone.
- The vendor_boot ramdisk was not unpacked to inspect its init and fstab copy. The header size already says it is a v3 vendor ramdisk of about 23 MB.
- The reason `CONFIG_IPC_NS` disappeared was not confirmed in the source.
- Infrared, NFC, camera count, and the card slot's behavior after a card is inserted were not verified.
