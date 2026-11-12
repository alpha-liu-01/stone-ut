#!/bin/sh
# Cross-build graphics-android2.so.16 (mir-android2-platform's server
# platform module) for Ubuntu Touch 24.04-2.x arm64, with or without
# mir-android2-platform-0001-*.patch, to test the upstream fix from source
# (docs/roadmap-release.md item 5).
#
#   sh tools/upstream/build-mir-android2-platform.sh [--stock] [COMMIT]
#
# COMMIT: default 72f96d2 (the build in the 24.04-2.x archive,
# 1.8.0~20260320103600.20~72f96d2). Output: out/upstream/mir-build/
# graphics-android2.so.16 (patched) or graphics-android2.so.16.stock.
# Needs Docker; no root, no qemu.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
REPO=https://gitlab.com/ubports/development/core/hybris-support/mir-android2-platform.git
STOCK=
[ "${1:-}" = --stock ] && { STOCK=y; shift; }
COMMIT=${1:-72f96d2}
WORK=$ROOT/out/upstream/mir-build
IMAGE=stone-mir-android2-cross

rm -rf "$WORK/src" "$WORK/build"
mkdir -p "$WORK"
git clone -q "$REPO" "$WORK/src"
git -C "$WORK/src" checkout -q "$COMMIT"
[ -n "$STOCK" ] || git -C "$WORK/src" apply "$HERE"/mir-android2-platform-0001-*.patch

docker build -q -t "$IMAGE" "$HERE/mir-android2-platform" >/dev/null
mkdir -p "$WORK/build"
cp "$ROOT/tools/biometryd/aarch64.cmake" "$WORK/"
docker run --rm -u "$(id -u):$(id -g)" -v "$WORK:/w" "$IMAGE" sh -c '
    set -e
    cd /w/build
    cmake /w/src -DCMAKE_TOOLCHAIN_FILE=/w/aarch64.cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib/aarch64-linux-gnu \
        -DPKG_CONFIG_EXECUTABLE=/usr/bin/aarch64-linux-gnu-pkg-config -DMIR_ENABLE_TESTS=OFF >/w/cmake.log
    make -j"$(nproc)" mirplatformgraphicsandroid >/w/make.log 2>&1 || { tail -40 /w/make.log; exit 1; }
    so=$(find . -name "graphics-android2.so.*" -type f | head -n 1)
    aarch64-linux-gnu-strip -o /w/out.so "$so"
'
name=graphics-android2.so.16
[ -z "$STOCK" ] || name=$name.stock
mv "$WORK/out.so" "$WORK/$name"
sha256sum "$WORK/$name"
