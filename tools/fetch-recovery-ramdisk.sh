#!/bin/sh
# Download UBports' unified recovery ramdisk (Halium 14, generic arm64) that
# boot/ut-init/build-boot-image.sh merges into the boot image, pinned by CI
# build number and SHA256. See docs/roadmap-release.md, item 1.
#
#   sh tools/fetch-recovery-ramdisk.sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BUILD=596
SHA256=c9c32a413b9e23a9b4ec1e0daba4e009ec485404590b74ef93059db22efaca40
URL="https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%2Fporting%2Fcommunity-ports%2Fjenkins-ci%2Fgeneric_arm64/job/halium-14.0/$BUILD/artifact/ramdisk-recovery.img"
OUT="$ROOT/out/recovery/ramdisk-recovery.img"
mkdir -p "$(dirname "$OUT")"
if [ -f "$OUT" ] && [ "$(sha256sum < "$OUT" | cut -d' ' -f1)" = "$SHA256" ]; then
    echo "already there: $OUT"
    exit 0
fi
curl -sfL -o "$OUT.part" "$URL"
[ "$(sha256sum < "$OUT.part" | cut -d' ' -f1)" = "$SHA256" ] || { echo "checksum mismatch"; rm -f "$OUT.part"; exit 1; }
mv "$OUT.part" "$OUT"
echo "fetched build $BUILD: $OUT"
