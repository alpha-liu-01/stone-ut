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
# snd_usb_audio.index: -2 is a slot mask without slot 0, so a USB audio card
# present at boot never takes card 0 from the built-in card (that one
# registers later, around 14 s).
CMDLINE="rw splash selinux=0 security=apparmor apparmor=1 snd_usb_audio.index=-2,-2,-2,-2,-2,-2,-2,-2"
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

for app in sh mount umount switch_root sleep mkdir grep sed cat cp echo ls head ln dmesg chroot chmod sync rm gzip cpio; do
    ln -s busybox "$STAGE/root/bin/$app"
done
cp "$INIT_SRC" "$STAGE/root/init"
chmod 755 "$STAGE/root/init"
cp "$ROOT/boot/ut-init/stone-dynparts.py" "$STAGE/root/stone-dynparts.py"
# Recovery (docs/roadmap-release.md item 1): UBports' unified recovery ramdisk
# with boot/ut-recovery merged in, stored as /ramdisk-recovery.img. init
# switches to it when the bootloader leaves out androidboot.force_normal_boot=1.
REC_IN=${RECOVERY_RAMDISK:-"$ROOT/out/recovery/ramdisk-recovery.img"}
REC_SHA256=c9c32a413b9e23a9b4ec1e0daba4e009ec485404590b74ef93059db22efaca40
if [ "$MODE" = boot ]; then
    [ -f "$REC_IN" ] || { echo "error: $REC_IN missing; run tools/fetch-recovery-ramdisk.sh" >&2; exit 1; }
    [ "$(sha256sum < "$REC_IN" | cut -d' ' -f1)" = "$REC_SHA256" ] || {
        echo "error: $REC_IN is not the pinned recovery build" >&2; exit 1; }
    # Every entry in it is root-owned and there are no device nodes, so it
    # is unpacked as the build user and repacked with -R 0:0.
    mkdir -p "$STAGE/recovery"
    (cd "$STAGE/recovery" && gzip -dc "$REC_IN" | cpio -i -d -m --quiet)
    cp -R "$ROOT/boot/ut-recovery/system/." "$STAGE/recovery/system/"
    cp "$ROOT/boot/ut-recovery/res/images/"* "$STAGE/recovery/res/images/"
    cp "$ROOT/boot/ut-recovery/init.recovery.qcom.rc" "$STAGE/recovery/init.recovery.qcom.rc"
    grep -v '^#' "$ROOT/boot/ut-recovery/prop.append" >> "$STAGE/recovery/prop.default"
    (cd "$STAGE/recovery" && find . -print0 | sort -z | cpio --null -o -H newc -R 0:0 --quiet) \
        | gzip -9n > "$STAGE/root/ramdisk-recovery.img"
    rm -rf "$STAGE/recovery"
fi
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
# ofono's apndb provisioning ignores mvno_type, so a Fizz SIM (302/500,
# GID1 55) gets Videotron's APNs. Ship a copy of the rootfs apndb where the
# Fizz entries are the plain 302/500 entries; ofono.service.d/zz-stone-apndb
# points OFONO_SYSTEM_APNDB_PATH at it. Generated, not committed.
APNDB_SRC=${APNDB_SRC:-"$OUT/rootfs-tree/usr/share/lineageos-apndb/apns-conf.xml"}
if [ -f "$APNDB_SRC" ]; then
    mkdir -p "$STAGE/root/stone-rootfs/usr/share/stone"
    python3 -I "$ROOT/tools/apndb-prefer-mvno.py" "$APNDB_SRC" \
        "$STAGE/root/stone-rootfs/usr/share/stone/apns-conf.xml" 302 500 gid 55
else
    echo "warning: $APNDB_SRC missing; Fizz SIMs will be provisioned as Videotron" >&2
fi
# media-hub aborts on the empty AppArmor label this kernel produces; ship the
# patched copy that etc/systemd/user/media-hub.service.d runs instead.
MEDIA_HUB_SRC=${MEDIA_HUB_SRC:-"$OUT/rootfs-tree/usr/bin/media-hub-server"}
if [ -f "$MEDIA_HUB_SRC" ]; then
    python3 -I "$ROOT/tools/patch-media-hub.py" "$MEDIA_HUB_SRC" \
        "$STAGE/root/stone-rootfs/usr/lib/stone/media-hub-server"
    chmod 755 "$STAGE/root/stone-rootfs/usr/lib/stone/media-hub-server"
else
    echo "error: $MEDIA_HUB_SRC missing; media-hub drop-in would point at nothing" >&2
    exit 1
fi
# telephony-service only knows the droid card's port names; ship the copy
# that matches the UCM ports, started by usr/lib/stone/telephony-service-handler.sh.
TELEPHONY_SRC=${TELEPHONY_SRC:-"$OUT/rootfs-tree/usr/bin/lomiri-telephony-service-handler"}
if [ -f "$TELEPHONY_SRC" ]; then
    # Must be in /usr/bin (see usr/lib/stone/telephony-service-handler.sh).
    mkdir -p "$STAGE/root/stone-rootfs/usr/bin"
    python3 -I "$ROOT/tools/patch-telephony-ports.py" "$TELEPHONY_SRC" \
        "$STAGE/root/stone-rootfs/usr/bin/lomiri-telephony-service-handler-stone"
    chmod 755 "$STAGE/root/stone-rootfs/usr/bin/lomiri-telephony-service-handler-stone"
else
    echo "error: $TELEPHONY_SRC missing; telephony handler drop-in would point at nothing" >&2
    exit 1
fi
# camera_service hangs releasing a video recorder (AudioSystem waits forever
# for an AudioFlinger this system does not have); the patched libaudioclient
# is bind-mounted over the Android system's copy by mount-halium-overlay.
ANDROID_IMG=${ANDROID_IMG:-"$OUT/rootfs-tree/var/lib/lxc/android/android-rootfs.img"}
if [ -f "$ANDROID_IMG" ]; then
    LAC_DIR="$STAGE/root/stone-rootfs/usr/share/halium-overlay/android/system/lib64"
    mkdir -p "$LAC_DIR"
    debugfs -R "dump /system/lib64/libaudioclient.so $STAGE/libaudioclient.so" \
        "$ANDROID_IMG" 2>/dev/null
    python3 -I "$ROOT/tools/patch-libaudioclient.py" "$STAGE/libaudioclient.so" \
        "$LAC_DIR/libaudioclient.so"
    chmod 644 "$LAC_DIR/libaudioclient.so"
    rm -f "$STAGE/libaudioclient.so"
else
    echo "error: $ANDROID_IMG missing; video recordings would hang the camera app" >&2
    exit 1
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
