#!/bin/sh
# Build the port from the inputs that tools/fetch-inputs.sh put in place:
# kernel -> root filesystem tree (and userdata image) -> boot image.
#
#   sh build.sh            all three; the rootfs step only when
#                          out/halium14/rootfs-tree does not exist yet
#   sh build.sh kernel     kernel/build-14/arch/arm64/boot/Image (+ hci_vhci.ko)
#   sh build.sh rootfs     out/halium14/rootfs-tree and userdata-ut.img (8 GiB),
#                          rebuilt from scratch
#   sh build.sh boot       out/halium14/boot-ut.img
#
# Environment: JOBS (make -j, default nproc), LLVM_BIN (default
# /usr/lib/llvm-21/bin: clang and ld.lld 21 built the tested kernels),
# KBUILD_BUILD_USER / KBUILD_BUILD_HOST (the kernel banner's user@host,
# default stone@stone-ut).
# Nothing here flashes the phone. See README.md and docs/install.md.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
KSRC="$ROOT/third_party/android_kernel_xiaomi_sm6375"
KOUT="$ROOT/kernel/build-14"
KERNEL_COMMIT=42e99ef7fcd885b2e8c2ebbc7e0c700f1294c52d
LLVM_BIN=${LLVM_BIN:-/usr/lib/llvm-21/bin}
GCC_BIN="$ROOT/third_party/toolchain/gcc-13.3.0-nolibc/aarch64-linux/bin"
JOBS=${JOBS:-$(nproc)}
KBUILD_BUILD_USER=${KBUILD_BUILD_USER:-stone}
KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-stone-ut}

die() { echo "error: $*" >&2; exit 1; }

need() {
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || die "'$c' not found; see README.md, Building"
    done
}

# 0 if the kernel tree is exactly KERNEL_COMMIT plus kernel/patches/*.patch,
# 1 if it is the clean commit, 2 for anything else. Compares git trees in
# temporary indexes; the work tree is not touched.
kernel_tree_state() {
    tmp=$(mktemp -d)
    (
        cd "$KSRC"
        GIT_INDEX_FILE="$tmp/patched" git read-tree "$KERNEL_COMMIT"
        for p in "$ROOT"/kernel/patches/*.patch; do
            GIT_INDEX_FILE="$tmp/patched" git apply --cached "$p" || exit 3
        done
        want=$(GIT_INDEX_FILE="$tmp/patched" git write-tree)
        GIT_INDEX_FILE="$tmp/now" git read-tree "$KERNEL_COMMIT"
        GIT_INDEX_FILE="$tmp/now" git add -A .
        now=$(GIT_INDEX_FILE="$tmp/now" git write-tree)
        clean=$(git rev-parse "$KERNEL_COMMIT^{tree}")
        [ "$now" = "$want" ] && exit 0
        [ "$now" = "$clean" ] && exit 1
        exit 2
    ) && rc=0 || rc=$?
    rm -rf "$tmp"
    return "$rc"
}

kmake() { # output-dir make-args...
    o=$1
    shift
    # The version banner records user@host; keep the builder's names out.
    KBUILD_BUILD_USER=$KBUILD_BUILD_USER KBUILD_BUILD_HOST=$KBUILD_BUILD_HOST \
    PATH="$LLVM_BIN:$GCC_BIN:$PATH" make -C "$KSRC" O="$o" ARCH=arm64 LLVM=1 \
        CROSS_COMPILE=aarch64-linux- KCFLAGS=-Wno-implicit-enum-enum-cast "$@"
}

build_kernel() {
    need make bc flex bison perl git
    [ -x "$LLVM_BIN/clang" ] && [ -x "$LLVM_BIN/ld.lld" ] || die "no clang/ld.lld in $LLVM_BIN (set LLVM_BIN)"
    [ -x "$GCC_BIN/aarch64-linux-ld" ] || die "toolchain missing; run sh tools/fetch-inputs.sh toolchain"
    [ -d "$KSRC/.git" ] || die "kernel source missing; run sh tools/fetch-inputs.sh kernel"
    [ "$(git -C "$KSRC" rev-parse HEAD)" = "$KERNEL_COMMIT" ] || die "$KSRC is not at $KERNEL_COMMIT"

    kernel_tree_state && st=0 || st=$?
    case "$st" in
    0) echo "kernel: patches already applied" ;;
    1)
        echo "kernel: applying kernel/patches"
        for p in "$ROOT"/kernel/patches/*.patch; do
            git -C "$KSRC" apply "$p"
            echo "  ${p##*/}"
        done
        ;;
    3) die "kernel/patches do not apply to $KERNEL_COMMIT" ;;
    *) die "$KSRC has changes that are not kernel/patches; stash or remove them" ;;
    esac

    # moonstone_defconfig plus the Halium fragment, generated in a scratch
    # directory and copied only when it differs, so a rebuild stays incremental.
    # merge_config.sh must run inside the kernel tree.
    cfg=$(mktemp -d)
    kmake "$cfg" moonstone_defconfig >/dev/null
    (cd "$KSRC" && PATH="$LLVM_BIN:$GCC_BIN:$PATH" ARCH=arm64 LLVM=1 CROSS_COMPILE=aarch64-linux- \
        scripts/kconfig/merge_config.sh -O "$cfg" "$cfg/.config" \
        "$ROOT/kernel/config/halium-sunstone.fragment" >"$cfg/merge.log" 2>&1) \
        || { cat "$cfg/merge.log" >&2; die "merge_config.sh failed"; }
    mkdir -p "$KOUT"
    if ! cmp -s "$cfg/.config" "$KOUT/.config"; then
        cp "$cfg/.config" "$KOUT/.config"
        echo "kernel: config updated"
    fi
    rm -rf "$cfg"

    kmake "$KOUT" -j"$JOBS" Image modules
    ls -l "$KOUT/arch/arm64/boot/Image" "$KOUT/drivers/bluetooth/hci_vhci.ko"
    sha256sum "$KOUT/arch/arm64/boot/Image"
}

build_rootfs() {
    need fakeroot tar python3 xxd
    [ -x /usr/sbin/mke2fs ] && [ -x /usr/sbin/debugfs ] || die "e2fsprogs (/usr/sbin/mke2fs, debugfs) missing"
    sh "$ROOT/boot/ut-init/build-userdata-image.sh"
}

build_boot() {
    need fakeroot cpio gzip python3 /usr/bin/lz4
    [ -x /usr/sbin/debugfs ] || die "e2fsprogs (/usr/sbin/debugfs) missing"
    sh "$ROOT/boot/ut-init/build-boot-image.sh"
}

case "${1:-all}" in
kernel) build_kernel ;;
rootfs) build_rootfs ;;
boot) build_boot ;;
all)
    build_kernel
    if [ -d "$ROOT/out/halium14/rootfs-tree" ]; then
        echo "rootfs: out/halium14/rootfs-tree exists, kept (sh build.sh rootfs rebuilds it)"
    else
        build_rootfs
    fi
    build_boot
    ;;
*) echo "usage: sh build.sh [all|kernel|rootfs|boot]" >&2; exit 1 ;;
esac
