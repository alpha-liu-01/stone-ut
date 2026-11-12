# Ubuntu Touch for the Redmi Note 12 5G (stone)

A port of [Ubuntu Touch](https://ubports.com) 24.04-2.x to the Xiaomi Redmi Note 12 5G and POCO X5 5G (device tree `stone`).

- Android side: Halium 14 (UBports' generic arm64 system image) running in a container on the crDroid 14 vendor.
- Kernel: crDroid's 5.4 kernel for sm6375 (`crdroidandroid/android_kernel_xiaomi_sm6375`, branch `14.0`) plus the patches in `kernel/patches/`.
- Boot: a small busybox initramfs. It mounts the userdata partition, which holds the Ubuntu Touch root filesystem, and copies `boot/ut-init/rootfs-overlay` (the device adaptation) into it on every boot. The same boot image carries UBports' recovery.

This is a community port in development and is not affiliated with UBports, Xiaomi or crDroid.

## Status

Tested on one `sunstone_cn` unit (Redmi Note 12 5G, China) in November 2026.

**Works:**
- display at 120 Hz (60/120 Hz switch), GPU, touch, display cutout;
- calls and SMS on both SIM slots, mobile data, VoLTE, MMS (also over Wi-Fi);
- Wi-Fi; Bluetooth, including audio, wideband calls and auto-reconnect;
- wired headsets (3.5 mm and USB), in-call volume;
- cameras, hardware video decoding;
- sensors, GNSS, fingerprint unlock;
- USB (MTP, adb), microSD, IR emitter;
- offline charging, recovery (Volume Up + Power).

**Not checked yet:** battery life and deep sleep, hotspot, flight mode, torch, double tap to wake, Waydroid, both SIMs in calls at once, Bluetooth headsets other than the one tested. See [docs/roadmap-release.md](docs/roadmap-release.md), item 11.

**Known issues:**
- No over-the-air updates yet. Some fixes patch specific binaries of the root filesystem and check their hash first; an `apt` upgrade of those packages has not been tested (roadmap item 7).
- `adbd` sometimes crashes during `adb push` of directories or many files in a row; it restarts by itself after about 40 s.
- The Android Bluetooth HAL died once while Bluetooth was off; not reproduced.
- Mobile data APNs for MVNOs that are recognised by IMSI or GID1 are not chosen automatically: ofono's APN provisioning cannot see those SIM fields on this ofono variant ([ofono-apndb-plugin#2](https://gitlab.com/ubports/development/core/ofono-apndb-plugin/-/work_items/2)). The port works around it for one carrier by default (Fizz, 302/500, GID1 55). For another MVNO, put a line `MCC MNC gid|imsi|spn MATCH_DATA` in `/etc/stone/apndb-mvno.conf` (see `/usr/share/stone/apndb-mvno.conf`) and let ofono provision the SIM anew, or set the APN in Settings → Mobile network.

### Variants

| Model | Codename | Status |
|---|---|---|
| Redmi Note 12 5G (China) | `sunstone_cn` | tested |
| Redmi Note 12 5G (global) | `sunstone_global` | untested; has NFC |
| POCO X5 5G | `moonstone` | untested; different SoC (SM6375), NFC |

The display, audio and camera configuration was made on `sunstone_cn`; other variants may differ (roadmap item 10). Reports from testers are welcome.

## Install

See [docs/install.md](docs/install.md). Installing wipes the phone, and needs an unlocked bootloader.

## Build

The build runs on an x86_64 Linux host (tested on Ubuntu 26.04) and needs no root.

Host packages (Ubuntu names): `clang-21 lld-21 llvm-21 make bc flex bison perl libssl-dev libelf-dev git curl xz-utils fakeroot lz4 e2fsprogs cpio xxd python3`. About 25 GB of free disk space.

```sh
sh tools/fetch-inputs.sh   # downloads and checks every input (about 4 GB)
sh build.sh                # kernel -> root filesystem -> boot image
```

Results:
- `out/halium14/boot-ut.img`: the boot image (kernel, initramfs, overlay, recovery);
- `out/halium14/userdata-ut.img`: the root filesystem image (8 GiB, ext4).

`sh build.sh kernel|rootfs|boot` runs one step. `build.sh` applies `kernel/patches/` to the kernel checkout itself, and refuses a kernel tree with other changes.

**Inputs.** `tools/fetch-inputs.sh` pins each one by SHA256 (the kernel by its git commit):
- the crDroid 14.0 v10.11 zip (SourceForge);
- the Ubuntu Touch 24.04-2.x root filesystem and the Halium 14 system image (UBports CI);
- UBports' recovery ramdisk (UBports CI);
- gcc 13.3.0 binutils from kernel.org;
- busybox 1.37.0 (Alpine `busybox-static`);
- the kernel source.

UBports CI deletes old builds, and Alpine no longer has that busybox revision. So the script falls back to this repository's `inputs-2026-11` release, and accepts a file only if its checksum matches. `STONE_MIRROR` sets another mirror.

**Optional:**
- `SSH_PUBKEY` (default `~/.ssh/id_ed25519.pub`, if it exists) is installed as `phablet`'s authorized key, for the USB rescue ssh.
- `tools/biometryd/build.sh` rebuilds the fingerprint daemon that is committed in the overlay. It needs Docker.
- `sh boot/ut-init/build-boot-image.sh trace|logs|disk` builds debug boot images:
  - `trace`: log snapshots every few seconds and passwordless sudo, then a reboot to the bootloader after 20 minutes;
  - `logs`: one-shot; sends the boot result and the previous boot's pstore over a USB serial port;
  - `disk`: one-shot; dumps the journal as text and exports userdata read-only as a USB disk.

## Repository layout

| Path | What |
|---|---|
| `boot/ut-init/` | initramfs (`init`), the rootfs overlay, and the image build scripts |
| `boot/ut-recovery/` | additions to UBports' recovery ramdisk |
| `kernel/` | kernel patches and config fragment |
| `tools/` | input fetching, build-time patchers, biometryd build, `phone-debug/` diagnostics |
| `docs/` | the development log: [roadmap-halium14](docs/roadmap-halium14.md), [hardware](docs/roadmap-hardware.md), [hardware 2](docs/roadmap-hardware-2.md), [release](docs/roadmap-release.md) |
| `archive/` | the abandoned Droidian route and one-off test scripts |

## Licence

GPL-3.0 for this repository's own files; see [LICENSE](LICENSE). Kernel patches are GPL-2.0, and other parts keep their own licences; see [NOTICE](NOTICE). [SOURCES.md](SOURCES.md) lists every binary the images ship, with its source.
