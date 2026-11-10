#!/bin/sh
# Header v3 boot image: Halium kernel plus the Ubuntu Touch initramfs.
# Does not build vendor_boot and does not flash.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
BUSYBOX=${BUSYBOX:-"$ROOT/third_party/busybox-aarch64/busybox"}
KERNEL=${KERNEL:-"$ROOT/kernel/build-14/arch/arm64/boot/Image"}
STAGE=$(mktemp -d)
OUT="$ROOT/out/halium14"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

[ -f "$BUSYBOX" ]
[ -f "$KERNEL" ]
mkdir -p "$STAGE/root/bin" "$OUT"
cp "$BUSYBOX" "$STAGE/root/bin/busybox"
chmod 755 "$STAGE/root/bin/busybox"
MODE=${1:-boot}
# The vendor_boot cmdline ends in "ro"; systemd would remount / read-only.
# Halium runs Android without SELinux policy; UT confines apps with AppArmor.
CMDLINE="rw splash selinux=0 security=apparmor apparmor=1"
case "$MODE" in
    boot) INIT_SRC="$ROOT/boot/ut-init/init"; BOOT_OUT="$OUT/boot-ut.img"; COMPRESS=lz4 ;;
    trace) INIT_SRC="$ROOT/boot/ut-init/init"; BOOT_OUT="$OUT/boot-ut-trace.img"; COMPRESS=lz4
        CMDLINE="$CMDLINE printk.devkmsg=on"
        cp "$ROOT/boot/ut-init/stone-init-wrapper" "$STAGE/root/stone-init-wrapper"
        echo 'phablet ALL=(ALL) NOPASSWD: ALL' > "$STAGE/root/stone-sudoers" ;;
    logs) INIT_SRC="$ROOT/boot/ut-init/init-logs"; BOOT_OUT="$OUT/boot-ut-logs.img"; COMPRESS=gzip ;;
    disk) INIT_SRC="$ROOT/boot/ut-init/init-disk"; BOOT_OUT="$OUT/boot-ut-disk.img"; COMPRESS=lz4 ;;
    *) echo "usage: $0 [boot|trace|logs|disk]" >&2; exit 1 ;;
esac

for app in sh mount umount switch_root sleep mkdir grep sed cat cp echo ls head ln dmesg chroot chmod sync rm; do
    ln -s busybox "$STAGE/root/bin/$app"
done
cp "$INIT_SRC" "$STAGE/root/init"
chmod 755 "$STAGE/root/init"
cp "$ROOT/boot/ut-init/stone-dynparts.py" "$STAGE/root/stone-dynparts.py"
cp "$ROOT/boot/ut-init/stone-vendor-fixups.py" "$STAGE/root/stone-vendor-fixups.py"
cp -R "$ROOT/boot/ut-init/rootfs-overlay" "$STAGE/root/stone-rootfs"
# Built against this kernel. The vendor copy's vermagic does not match.
VHCI="$ROOT/kernel/build-14/drivers/bluetooth/hci_vhci.ko"
if [ -f "$VHCI" ]; then
    # /lib on the rootfs is a symlink to usr/lib. Copying a lib/
    # directory onto that symlink does not create the module.
    mkdir -p "$STAGE/root/stone-rootfs/usr/lib/modules/stone"
    cp "$VHCI" "$STAGE/root/stone-rootfs/usr/lib/modules/stone/hci_vhci.ko"
fi
# Key for the usb-moded rescue sshd (10.15.19.82:8022); kept out of the repo.
SSH_PUBKEY=${SSH_PUBKEY:-"$HOME/.ssh/id_ed25519.pub"}
if [ -f "$SSH_PUBKEY" ]; then
    mkdir -p "$STAGE/root/stone-rootfs/home/phablet/.ssh"
    cp "$SSH_PUBKEY" "$STAGE/root/stone-rootfs/home/phablet/.ssh/authorized_keys"
fi
if [ "$MODE" = trace ] || [ "$MODE" = disk ]; then
    "$ROOT/third_party/toolchain/gcc-13.3.0-nolibc/aarch64-linux/bin/aarch64-linux-gcc" \
        -nostdlib -static -fno-builtin -O2 -o "$STAGE/root/reboot-bootloader" \
        "$ROOT/boot/droidian-init/reboot-bootloader.c"
    chmod 755 "$STAGE/root/reboot-bootloader"
fi
# The Android 14 vendor ramdisk only has first_stage_ramdisk/ and lib/.
mkdir -p "$STAGE/root/proc" "$STAGE/root/sys" "$STAGE/root/dev" \
    "$STAGE/root/tmp" "$STAGE/root/config" "$STAGE/root/newroot" \
    "$STAGE/root/userdata" "$STAGE/root/mnt/pstore"

fakeroot -- sh -c '
    set -e
    cd "$1/root"
    mknod -m 600 dev/console c 5 1
    mknod -m 666 dev/null c 1 3
    find . -print0 | sort -z | cpio --null -o -H newc -R 0:0
' sh "$STAGE" > "$STAGE/ramdisk.cpio"

if [ "$COMPRESS" = gzip ]; then
    gzip -9 < "$STAGE/ramdisk.cpio" > "$STAGE/ramdisk.gz"
    RAMDISK="$STAGE/ramdisk.gz"
else
    /usr/bin/lz4 -l -9 < "$STAGE/ramdisk.cpio" > "$STAGE/ramdisk.lz4"
    RAMDISK="$STAGE/ramdisk.lz4"
fi

python3 "$ROOT/tools/mkbootimg/mkbootimg.py" \
    --header_version 3 \
    --os_version 14.0.0 \
    --os_patch_level 2024-12 \
    --kernel "$KERNEL" \
    --ramdisk "$RAMDISK" \
    --cmdline "$CMDLINE" \
    --base 0 \
    --kernel_offset 0x8000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x100 \
    --pagesize 4096 \
    -o "$BOOT_OUT"

python3 "$ROOT/tools/mkbootimg/unpack_bootimg.py" --boot_img "$BOOT_OUT" --format info
ls -lh "$BOOT_OUT"
sha256sum "$BOOT_OUT"
