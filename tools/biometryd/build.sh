#!/bin/sh
# Builds the biometryd daemon shipped in the rootfs overlay
# (boot/ut-init/rootfs-overlay/usr/lib/stone/biometryd/), replacing the
# packaged 0.4.0 daemon through a systemd drop-in. See
# docs/roadmap-hardware-2.md, item 8.
#
#   sh tools/biometryd/build.sh
#
# biometryd main (0.4.1+, libgbinder HIDL/AIDL fingerprint backend and the
# GetConnectionCredentials fix) at a pinned commit, plus
# biometryd-0001-dbus-fall-back-to-apparmor-label-by-pid.patch, cross-built
# for Ubuntu 24.04 arm64 against the UBports 24.04-2.x libraries in Docker
# (no root, no qemu).
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
REPO=https://gitlab.com/ubports/development/core/biometryd.git
COMMIT=1005154be01ed2d01f50f8f99fdaaf02cc62077b
WORK=${WORK:-$ROOT/out/biometryd-build}
OUT=$ROOT/boot/ut-init/rootfs-overlay/usr/lib/stone/biometryd
IMAGE=stone-biometryd-cross

rm -rf "$WORK"
mkdir -p "$WORK"
git clone -q "$REPO" "$WORK/src"
git -C "$WORK/src" checkout -q "$COMMIT"
git -C "$WORK/src" -c user.name=stone -c user.email=stone@localhost am -q "$HERE"/biometryd-0001-*.patch

docker build -q -t "$IMAGE" "$HERE" >/dev/null
mkdir -p "$WORK/build"
cp "$HERE/aarch64.cmake" "$WORK/"
docker run --rm -u "$(id -u):$(id -g)" -v "$WORK:/w" "$IMAGE" sh -c '
    set -e
    cd /w/build
    cmake /w/src -DCMAKE_TOOLCHAIN_FILE=/w/aarch64.cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib/aarch64-linux-gnu \
        -DWITH_GBINDER=ON -DENABLE_QT6=OFF -DENABLE_WERROR=OFF -DUSE_SYSTEMD=OFF >/dev/null
    make -j"$(nproc)" biometry biometryd >/dev/null
    aarch64-linux-gnu-strip -o /w/biometryd src/biometry/biometryd
    aarch64-linux-gnu-strip -o /w/libbiometry.so.2 src/biometry/libbiometry.so.2.0.0
'
mkdir -p "$OUT"
install -m 755 "$WORK/biometryd" "$OUT/biometryd"
install -m 644 "$WORK/libbiometry.so.2" "$OUT/libbiometry.so.2"
sha256sum "$OUT/biometryd" "$OUT/libbiometry.so.2"
