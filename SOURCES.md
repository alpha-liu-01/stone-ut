# Sources of the distributed binaries

Every binary that goes into the boot image (`out/halium14/boot-ut.img`) or the root filesystem image (`out/halium14/userdata-ut.img`), with its upstream source, its exact version and its licence. The licence texts are in [LICENSE](LICENSE) (GPL-3.0) and [licenses/](licenses/). [NOTICE](NOTICE) covers this repository's own files.

Checked for boot image `ca678721…` (kernel `#20`, patches `0001`–`0015`), 2026-11-12. Update this file when an input changes.

## Boot image

### Linux kernel: `Image` and `hci_vhci.ko`

- **Licence:** GPL-2.0 ([licenses/GPL-2.0.txt](licenses/GPL-2.0.txt)).
- **Base:** crDroid's [android_kernel_xiaomi_sm6375](https://github.com/crdroidandroid/android_kernel_xiaomi_sm6375), branch `14.0`, commit `42e99ef7fcd885b2e8c2ebbc7e0c700f1294c52d`.
- **Changes:** [kernel/patches/](kernel/patches/) (`0001`–`0015`; `0011`–`0014` are Ubuntu's and UBports' AppArmor patches with their original authors), and [kernel/config/halium-sunstone.fragment](kernel/config/halium-sunstone.fragment) merged on top of `moonstone_defconfig`.
- **As a git branch:** `sh tools/make-kernel-fork.sh DIR boot-<image>` makes the branch `stone-ut`: the base, one commit per patch, and a commit adding the fragment. The hashes are reproducible. Tags: `boot-ca678721` (kernel `#20`, patches `0001`–`0015`) is `e0144c10e252262c32c66aac064f8345aa2f3ad4`; `boot-16bfa7b0` (kernel `#18`, `0001`–`0010`) is `4880119163f88ac5a62aa1a1a020fded1b870413`.
- **Build:** `sh build.sh kernel` (clang/lld 21, binutils from gcc 13.3.0).
- **Module:** `hci_vhci.ko` (`drivers/bluetooth/hci_vhci.c`, which no patch changes) comes from the same build directory.

### busybox (the initramfs's `/bin/busybox`)

- **Licence:** GPL-2.0.
- **Binary:** Alpine `busybox-static` 1.37.0-r31, aarch64. SHA256 `999cb969d09093a71716cfc747bb53cdada3f332c05eb5046c56e0f66a4d6d22`; its banner says "BusyBox v1.37.0 (2026-01-10 15:38:28 UTC)".
- **Source:**
  - [busybox-1.37.0.tar.bz2](https://busybox.net/downloads/busybox-1.37.0.tar.bz2), SHA512 `ad8fd06f082699774f990a53d7a73b189ed404fe0a2166aff13eae4d9d8ee5c9239493befe949c98801fe7897520dbff3ed0224faa7205854ce4fa975e18467e`;
  - Alpine's build recipe and patches: [aports `main/busybox`](https://gitlab.alpinelinux.org/alpine/aports/-/tree/c3ef5d10e6ef6528852c51f0564963e2f8c1be19/main/busybox) at commit `c3ef5d10e6ef6528852c51f0564963e2f8c1be19` (pkgrel 31).
- Alpine no longer serves this revision. A copy of the binary is in this repository's `inputs-2026-11` release; the tarball and the recipe should go with it (item 4 of [docs/roadmap-release.md](docs/roadmap-release.md)).

### UBports recovery (`/ramdisk-recovery.img` in the initramfs)

- **Licence:** various (Android: mostly Apache-2.0; Linux userspace tools: GPL).
- **Binary:** UBports CI, [halium-14.0 generic_arm64](https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%252Fporting%252Fcommunity-ports%252Fjenkins-ci%252Fgeneric_arm64/job/halium-14.0/), artifact `ramdisk-recovery.img`, builds 595 and 596 (identical), SHA256 `c9c32a413b9e23a9b4ec1e0daba4e009ec485404590b74ef93059db22efaca40`.
- **Built from:**
  - `generic_arm64` branch `halium-14.0` at `9a95607a2ffbde7e4cea665936abd0ad6f831477`;
  - `halium-build-tools` at `96088c8f5e6c51e9a460ceafe86d014ac2ef01e5`;
  - both under [gitlab.com/ubports/porting/community-ports/jenkins-ci](https://gitlab.com/ubports/porting/community-ports/jenkins-ci).
- **This repository adds:** [boot/ut-recovery/](boot/ut-recovery/) (fstab, init script, images, properties).

### Patched UBports binaries (in the initramfs's overlay)

Made at build time from the exact binaries of the root filesystem below. Each patch script checks the input's and the output's SHA256.

| Shipped as | Upstream package and version | Licence | Patch |
|---|---|---|---|
| `/usr/bin/lomiri-telephony-service-handler-stone` | `lomiri-telephony-service` 0.6.2+0~20260728091107.2+ubports24.04.2~1.gbp0e2982 | GPL-3.0 | [tools/patch-telephony-ports.py](tools/patch-telephony-ports.py) |
| `/usr/share/halium-overlay/android/system/lib64/libaudioclient.so` | Halium 14 system image below (`/system/lib64/libaudioclient.so`) | Apache-2.0 | [tools/patch-libaudioclient.py](tools/patch-libaudioclient.py) |

Sources:
- the UBports packages: `apt-get source <package>=<version>` from `repo.ubports.com` (24.04-2.x);
- Halium: the Android tree named below.

### Patched at boot on the phone

`/usr/lib/stone/display-setup.sh` writes a patched copy of `graphics-android2.so.16` to `/run/stone-display` (tmpfs) and bind-mounts it over the original:
- **Package:** `mir1-platform-graphics-android2-16`, source [mir-android2-platform](https://gitlab.com/ubports/development/core/hybris-support/mir-android2-platform), 1.8.0~20260320103600.20~72f96d2+ubports24.04.2.
- **Licence:** the project is GPL-3.0 and LGPL-3.0; the patched file, `real_hwc2_wrapper.cpp`, is LGPL-3.0.
- **Hashes:** stock SHA256 `146cf674…`, patched `bc58bdfd…`.
- **The change as a source patch:** [tools/upstream/mir-android2-platform-0001-server-dont-block-on-the-previous-frames-present-fence.patch](tools/upstream/).

### Committed binaries: biometryd

`boot/ut-init/rootfs-overlay/usr/lib/stone/biometryd/`:
- `biometryd`, SHA256 `55975e1ccaa9a68d5eb4206aac9132e8065f13893ec4ca543dd54b9675bd91f8`, GPL-3.0;
- `libbiometry.so.2`, SHA256 `7792ee8ed987bbd5bfb9996543968002e69a50fab9950d9f18045def57e3d879`, LGPL-3.0 ([licenses/LGPL-3.0.txt](licenses/LGPL-3.0.txt)).

Built by [tools/biometryd/build.sh](tools/biometryd/build.sh):
- from [biometryd](https://gitlab.com/ubports/development/core/biometryd) at commit `1005154be01ed2d01f50f8f99fdaaf02cc62077b`;
- plus [tools/biometryd/biometryd-0001-dbus-fall-back-to-apparmor-label-by-pid.patch](tools/biometryd/);
- in `ubuntu:24.04` with the UBports 24.04-2.x libraries.

### Copied upstream data files in the overlay

`boot/ut-init/rootfs-overlay/usr/share/stone/`:
- `audio_policy_configuration.xml`, `r_submix.xml`, `tables.xml`, `volumes.xml` (and `bluetooth.xml`, which they include):
  - edited copies of the crDroid 14 vendor's audio policy files (`/vendor/etc/audio/`), for the `module-droid-card` route of `docs/roadmap-hardware.md` item 3;
  - AOSP and The Linux Foundation, Apache-2.0 ([licenses/Apache-2.0.txt](licenses/Apache-2.0.txt)); each file keeps its header;
  - **no longer used:** the only reference is the commented-out `module-droid-card-28` line in `etc/pulse/stone-touch.pa`. They can be removed.
- `settings/brightness-PageComponent.qml`: Lomiri System Settings' brightness page (`lomiri-system-settings`, GPL-3.0) with a section added.

## Root filesystem image (unmodified upstream images)

- **Ubuntu Touch 24.04-2.x rootfs:**
  - `ubuntu-touch-android9plus-rootfs-arm64.tar.gz`, SHA256 `ec130c13…`;
  - from UBports CI [ubuntu-touch-rootfs/ubports/24.04-2.x](https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%252F24.04-2.x/) build 154 (2026-11-07);
  - made by [rootfs-builder-debos](https://gitlab.com/ubports/development/core/rootfs-builder-debos) at `608c8ff0ad11cb8c1d7ac291f58289b83a7ad29a` with [build-tools](https://gitlab.com/ubports/infrastructure/build-tools) at `6347090769fbb3a9ea28d1fb92c43a1dc499a8a0`;
  - the packages come from Ubuntu 24.04 (noble) and `repo.ubports.com` 24.04-2.x. `apt-get source` gives each package's source; the package list is `/var/lib/dpkg/status` in the image.
- **Halium 14 system image** (`/var/lib/lxc/android/android-rootfs.img`):
  - `halium_halium_arm64.tar.xz`, SHA256 `1b1b4213…`;
  - UBports CI halium-14.0 `generic_arm64`, first built as 586, identical through 596, from the same `generic_arm64`/`halium-build-tools` revisions as the recovery;
  - the image is `lineage_halium_arm64-userdebug 14 AP2A.240905.003`, built from Halium's Android 14 tree (LineageOS 21 based). Apache-2.0 and GPL-2.0 parts.

All the hashes above are also pinned in [tools/fetch-inputs.sh](tools/fetch-inputs.sh).

## Not distributed

crDroid 14 (`crDroidAndroid-14.0-20241212-stone-v10.11.zip`: vendor, odm, vendor_boot, dtbo) is installed by the user from crDroid's download page; it is not repackaged here.
