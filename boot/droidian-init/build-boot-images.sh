#!/bin/sh
# Build header v3 boot and vendor_boot images for the Droidian experiment.
# Does not flash anything.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
BUSYBOX=${BUSYBOX:-"$ROOT/third_party/busybox-aarch64/busybox"}
KERNEL=${KERNEL:-"$ROOT/kernel/build/arch/arm64/boot/Image"}
DTB=${DTB:-"$ROOT/kernel/build/arch/arm64/boot/dts/vendor/xiaomi/moonstone.dtb"}
VENDOR_RAMDISK=${VENDOR_RAMDISK:-/tmp/vendor_boot_b_unpacked/vendor_ramdisk}
STAGE=$(mktemp -d)
OUT="$ROOT/out/halium-droidian"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

[ -f "$BUSYBOX" ]
[ -f "$KERNEL" ]
[ -f "$DTB" ]
[ -f "$VENDOR_RAMDISK" ]

MODE=${1:-boot}
case "$MODE" in
    boot) INIT_SRC="$ROOT/boot/droidian-init/init"; BOOT_OUT="$OUT/boot.img" ;;
    logs) INIT_SRC="$ROOT/boot/droidian-init/init-logs"; BOOT_OUT="$OUT/boot-logs.img" ;;
    disk) INIT_SRC="$ROOT/boot/droidian-init/init-disk"; BOOT_OUT="$OUT/boot-disk.img" ;;
    patch) INIT_SRC="$ROOT/boot/droidian-init/init-patch"; BOOT_OUT="$OUT/boot-patch.img" ;;
    *) echo "usage: $0 [boot|logs|disk|patch]" >&2; exit 1 ;;
esac

mkdir -p "$STAGE/root/bin" "$OUT"
cp "$BUSYBOX" "$STAGE/root/bin/busybox"
chmod 755 "$STAGE/root/bin/busybox"
for app in sh mount umount switch_root sleep mkdir grep sed cat ln mknod losetup echo cp chroot dd sync dmesg head ls strings chmod cmp rm mv; do
    ln -s busybox "$STAGE/root/bin/$app"
done
cp "$INIT_SRC" "$STAGE/root/init"
chmod 755 "$STAGE/root/init"
if [ "$MODE" = "patch" ]; then
    CC="$ROOT/third_party/toolchain/gcc-13.3.0-nolibc/aarch64-linux/bin/aarch64-linux-gcc"
    "$CC" -nostdlib -static -fno-builtin -O2 \
        -o "$STAGE/root/reboot-bootloader" \
        "$ROOT/boot/droidian-init/reboot-bootloader.c"
    chmod 755 "$STAGE/root/reboot-bootloader"
    "$CC" -nostdlib -static -fno-builtin -O2 \
        -o "$STAGE/root/stone-binder-nodes" \
        "$ROOT/boot/droidian-init/stone-binder-nodes.c"
    chmod 755 "$STAGE/root/stone-binder-nodes"
    cp "$ROOT/boot/droidian-init/stone-wrap-hals.sh" "$STAGE/root/stone-wrap-hals.sh"
    chmod 755 "$STAGE/root/stone-wrap-hals.sh"
    cp "$ROOT/boot/droidian-init/stone-lxc-start.sh" "$STAGE/root/stone-lxc-start.sh"
    chmod 755 "$STAGE/root/stone-lxc-start.sh"
    cp "$ROOT/out/halium-droidian/vendor-libc++.so" "$STAGE/root/stone-libc++.so"
    chmod 644 "$STAGE/root/stone-libc++.so"
    "$CC" -shared -fPIC -nostdlib -O2 \
        -Wl,-soname,libapexsupport.so -Wl,--hash-style=both \
        -Wl,-z,max-page-size=4096 \
        -o "$STAGE/root/stone-libapexsupport.so" \
        "$ROOT/boot/droidian-init/libapexsupport.c"
    chmod 644 "$STAGE/root/stone-libapexsupport.so"
    # openssh-server and its missing trixie dependencies, plus host keys made
    # on the PC so the phone does not wait for entropy during early boot.
    mkdir -p "$STAGE/root/stone-ssh/debs" "$STAGE/root/stone-ssh/hostkeys"
    cp "$OUT"/debs/*.deb "$STAGE/root/stone-ssh/debs/"
    cp "$OUT"/ssh/hostkeys/ssh_host_* "$STAGE/root/stone-ssh/hostkeys/"
    cp "$OUT/ssh/id_ed25519.pub" "$STAGE/root/stone-ssh/authorized_keys"
fi

# Match the legacy LZ4 frame already used by this device's boot ramdisk.
(cd "$STAGE/root" && find . -print0 | sort -z | cpio --null -o -H newc) \
    | lz4 -l -9 > "$STAGE/ramdisk.lz4"

python3 "$ROOT/tools/mkbootimg/mkbootimg.py" \
    --header_version 3 \
    --os_version 16.0.0 \
    --os_patch_level 2026-04 \
    --kernel "$KERNEL" \
    --ramdisk "$STAGE/ramdisk.lz4" \
    --base 0 \
    --kernel_offset 0x8000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x100 \
    --pagesize 4096 \
    -o "$BOOT_OUT"

CMDLINE="androidboot.hardware=qcom androidboot.memcg=1 lpm_levels.sleep_disabled=1 msm_rtb.filter=0x237 service_locator.enable=1 androidboot.usbcontroller=4e00000.dwc3 swiotlb=0 loop.max_part=7 cgroup.memory=nokmem,nosocket iptable_raw.raw_before_defrag=1 ip6table_raw.raw_before_defrag=1 firmware_class.path=/vendor/firmware datapart=/dev/block/by-name/userdata"

python3 "$ROOT/tools/mkbootimg/mkbootimg.py" \
    --header_version 3 \
    --base 0 \
    --kernel_offset 0x8000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x100 \
    --pagesize 4096 \
    --dtb "$DTB" \
    --dtb_offset 0x01f00000 \
    --vendor_ramdisk "$VENDOR_RAMDISK" \
    --vendor_cmdline "$CMDLINE" \
    --vendor_boot "$OUT/vendor_boot.img"

python3 "$ROOT/tools/mkbootimg/unpack_bootimg.py" --boot_img "$BOOT_OUT" --format info
ls -lh "$BOOT_OUT"
sha256sum "$BOOT_OUT"
