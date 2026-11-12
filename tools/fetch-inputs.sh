#!/bin/sh
# Download and check every input of the build (docs/roadmap-release.md item 3).
#
#   sh tools/fetch-inputs.sh              everything
#   sh tools/fetch-inputs.sh NAME ...     only these (names below)
#   sh tools/fetch-inputs.sh --mirror-files DIR
#                                         copy the mirrored inputs into DIR under
#                                         their release asset names, for upload
#
# Each file is pinned by SHA256. It is taken from upstream first, then from
# this repository's input mirror (a GitHub release; STONE_MIRROR overrides the
# base URL), and kept only if the checksum matches. A file already in place
# with the right checksum is not downloaded again. UBports CI deletes old
# builds after a few days to weeks, and Alpine has dropped the busybox
# revision the image ships, so for those the mirror is the lasting source.
#
# The kernel source is a git checkout of a pinned commit; git checks it by its
# hash. kernel/patches/ are applied by build.sh, not here.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
MIRROR=${STONE_MIRROR:-https://github.com/alpha-liu-01/stone-ut/releases/download/inputs-2026-11}
CI=https://ci.ubports.com/job
HALIUM_JOB="$CI/UBportsCommunityPortsJenkinsCI/job/ubports%252Fporting%252Fcommunity-ports%252Fjenkins-ci%252Fgeneric_arm64/job/halium-14.0"
ROOTFS_JOB="$CI/ubuntu-touch-rootfs/job/ubports%252F24.04-2.x"

KERNEL_REPO=https://github.com/crdroidandroid/android_kernel_xiaomi_sm6375.git
KERNEL_COMMIT=42e99ef7fcd885b2e8c2ebbc7e0c700f1294c52d
KERNEL_DIR="$ROOT/third_party/android_kernel_xiaomi_sm6375"

# name | path in the repository | SHA256 | mirror asset name ("-": not mirrored)
#      | upstream URL ("-": none left)
# Upstream notes:
# - crdroid: crDroid 14 v10.11 for stone (vendor, firmware, vendor_boot, dtbo).
# - rootfs: Ubuntu Touch 24.04-2.x rootfs, CI build 154 (Jenkins fingerprint).
# - halium: generic Halium 14 arm64 system image; first built as CI 586,
#   identical through 596.
# - recovery: UBports unified recovery ramdisk (Halium 14 generic arm64);
#   first built as CI 595, identical in 596.
# - toolchain: kernel.org crosstool gcc 13.3.0 (binutils for the kernel's
#   CROSS_COMPILE; the compiler is the host's clang 21).
# - busybox: Alpine busybox-static 1.37.0-r31 (aarch64), static binary taken
#   out of the apk; that revision is no longer in Alpine's repositories.
INPUTS='
crdroid|third_party/crDroidAndroid-14.0-20241212-stone-v10.11.zip|16b0cdfcb5795d12361aa94d1ee244002ea671d0e0b8a4439d56e5773c5b2fd9|-|https://sourceforge.net/projects/crdroid/files/stone/10.x/crDroidAndroid-14.0-20241212-stone-v10.11.zip/download
rootfs|third_party/halium14/ubuntu-touch-android9plus-rootfs-arm64.tar.gz|ec130c13231b5562e4ce360d555f1aee5769275b7c3b8eae9f89bfc03ec92562|ubuntu-touch-android9plus-rootfs-arm64.tar.gz|'"$ROOTFS_JOB"'/154/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz
halium|third_party/halium14/halium_halium_arm64.tar.xz|1b1b42138618e34db740f324653b390dd69e067450f9fc453290fdf323c4915e|halium_halium_arm64.tar.xz|'"$HALIUM_JOB"'/594/artifact/halium_halium_arm64.tar.xz
recovery|out/recovery/ramdisk-recovery.img|c9c32a413b9e23a9b4ec1e0daba4e009ec485404590b74ef93059db22efaca40|ramdisk-recovery.img|'"$HALIUM_JOB"'/596/artifact/ramdisk-recovery.img
toolchain|third_party/toolchain/x86_64-gcc-13.3.0-nolibc-aarch64-linux.tar.xz|9fe3e59c190143a3569c1a2453c649be2cad6d936318469f619d6cb9b9a11f2b|-|https://mirrors.edge.kernel.org/pub/tools/crosstool/files/bin/x86_64/13.3.0/x86_64-gcc-13.3.0-nolibc-aarch64-linux.tar.xz
busybox|third_party/busybox-aarch64/busybox|999cb969d09093a71716cfc747bb53cdada3f332c05eb5046c56e0f66a4d6d22|busybox-1.37.0-r31-aarch64-static|-
'
# Unpacked from the halium archive; checked so a partial unpack is noticed.
ANDROID_IMG=third_party/halium14/system/var/lib/lxc/android/android-rootfs.img
ANDROID_IMG_SHA256=12d1606e96f161005d4c3df66a8870080639704eaf61221f7b4f2767b0681678

sha() { sha256sum < "$1" | cut -d' ' -f1; }

# download URL DEST: 0 if DEST.part now holds the file
download() {
    [ "$1" != - ] || return 1
    echo "  trying $1"
    curl -fL -# --retry 3 --connect-timeout 30 -o "$2.part" "$1" || { rm -f "$2.part"; return 1; }
}

fetch_file() { # name path sha256 asset url
    dest="$ROOT/$2"
    if [ -f "$dest" ] && [ "$(sha "$dest")" = "$3" ]; then
        echo "$1: ok ($2)"
        return 0
    fi
    [ ! -e "$dest" ] || { echo "$1: $2 exists but its SHA256 is not the pinned one; move it away first" >&2; return 1; }
    echo "$1: fetching $2"
    mkdir -p "$(dirname "$dest")"
    for url in "$5" "$([ "$4" = - ] && echo - || echo "$MIRROR/$4")"; do
        if download "$url" "$dest"; then
            if [ "$(sha "$dest.part")" = "$3" ]; then
                mv "$dest.part" "$dest"
                echo "$1: ok ($2)"
                return 0
            fi
            echo "  checksum mismatch, discarded"
            rm -f "$dest.part"
        fi
    done
    echo "$1: no source gave the pinned file (SHA256 $3)." >&2
    echo "  Put a copy with that checksum at $2 and run this again." >&2
    return 1
}

after() { # unpack or mark what a fetched file needs
    case "$1" in
    halium)
        if [ -f "$ROOT/$ANDROID_IMG" ] && [ "$(sha "$ROOT/$ANDROID_IMG")" = "$ANDROID_IMG_SHA256" ]; then
            return 0
        fi
        echo "halium: unpacking the Android system image"
        rm -rf "$ROOT/third_party/halium14/system" "$ROOT/third_party/halium14/partitions"
        tar -xJf "$ROOT/third_party/halium14/halium_halium_arm64.tar.xz" -C "$ROOT/third_party/halium14"
        [ "$(sha "$ROOT/$ANDROID_IMG")" = "$ANDROID_IMG_SHA256" ] || {
            echo "halium: unpacked $ANDROID_IMG has the wrong checksum" >&2; return 1; }
        ;;
    toolchain)
        [ -x "$ROOT/third_party/toolchain/gcc-13.3.0-nolibc/aarch64-linux/bin/aarch64-linux-ld" ] && return 0
        echo "toolchain: unpacking"
        tar -xJf "$ROOT/third_party/toolchain/x86_64-gcc-13.3.0-nolibc-aarch64-linux.tar.xz" -C "$ROOT/third_party/toolchain"
        ;;
    busybox)
        chmod 755 "$ROOT/third_party/busybox-aarch64/busybox"
        ;;
    esac
}

fetch_kernel() {
    if [ -d "$KERNEL_DIR/.git" ]; then
        head=$(git -C "$KERNEL_DIR" rev-parse HEAD)
        [ "$head" = "$KERNEL_COMMIT" ] || {
            echo "kernel: $KERNEL_DIR is at $head, not $KERNEL_COMMIT" >&2; return 1; }
        echo "kernel: ok (third_party/android_kernel_xiaomi_sm6375 at ${KERNEL_COMMIT%"${KERNEL_COMMIT#????????}"})"
        return 0
    fi
    [ ! -e "$KERNEL_DIR" ] || { echo "kernel: $KERNEL_DIR exists but is not a git checkout" >&2; return 1; }
    echo "kernel: fetching $KERNEL_COMMIT"
    git init -q "$KERNEL_DIR"
    git -C "$KERNEL_DIR" remote add origin "$KERNEL_REPO"
    git -C "$KERNEL_DIR" fetch -q --depth 1 origin "$KERNEL_COMMIT"
    git -C "$KERNEL_DIR" checkout -q FETCH_HEAD
    [ "$(git -C "$KERNEL_DIR" rev-parse HEAD)" = "$KERNEL_COMMIT" ]
    echo "kernel: ok"
}

each_input() { # callback name...
    cb=$1; shift
    echo "$INPUTS" | while IFS='|' read -r name path sum asset url; do
        [ -n "$name" ] || continue
        if [ $# -gt 0 ]; then
            want=
            for n in "$@"; do [ "$n" = "$name" ] && want=y; done
            [ -n "$want" ] || continue
        fi
        "$cb" "$name" "$path" "$sum" "$asset" "$url" || exit 1
    done
}

one() { fetch_file "$@" && after "$1"; }

copy_for_mirror() { # name path sha256 asset url
    [ "$4" != - ] || return 0
    [ -f "$ROOT/$2" ] && [ "$(sha "$ROOT/$2")" = "$3" ] || {
        echo "$1: $2 missing or wrong checksum; fetch it first" >&2; return 1; }
    cp "$ROOT/$2" "$MIRROR_DIR/$4"
    echo "$3  $4" >> "$MIRROR_DIR/SHA256SUMS"
    echo "$4"
}

if [ "${1:-}" = --mirror-files ]; then
    MIRROR_DIR=${2:?usage: $0 --mirror-files DIR}
    mkdir -p "$MIRROR_DIR"
    rm -f "$MIRROR_DIR/SHA256SUMS"
    each_input copy_for_mirror
    echo "Publish them as the assets of the release ${MIRROR##*/}, for example:"
    echo "  gh release create ${MIRROR##*/} --title 'Build inputs' --notes-file $MIRROR_DIR/SHA256SUMS $MIRROR_DIR/*"
    exit 0
fi

names=$*
for n in $names; do
    case "$n" in
    kernel|crdroid|rootfs|halium|recovery|toolchain|busybox) ;;
    *) echo "unknown input '$n' (kernel crdroid rootfs halium recovery toolchain busybox)" >&2; exit 1 ;;
    esac
done
fail=
if [ -z "$names" ]; then
    each_input one || fail=y
    fetch_kernel || fail=y
else
    files=
    for n in $names; do [ "$n" = kernel ] || files="$files $n"; done
    # shellcheck disable=SC2086
    [ -z "$files" ] || each_input one $files || fail=y
    case " $names " in *" kernel "*) fetch_kernel || fail=y ;; esac
fi
[ -z "$fail" ] || { echo "Some inputs are missing; see above." >&2; exit 1; }
echo "All requested inputs are in place."
