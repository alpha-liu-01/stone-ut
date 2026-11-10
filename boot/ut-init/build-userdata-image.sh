#!/bin/sh
# Build an ext4 image of the Ubuntu Touch rootfs. Does not flash.
# fakeroot keeps the archive's owners without a real root user.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TREE="$ROOT/out/halium14/rootfs-tree"
IMG="$ROOT/out/halium14/userdata-ut.img"
TAR="$ROOT/third_party/halium14/ubuntu-touch-android9plus-rootfs-arm64.tar.gz"
ANDROID="$ROOT/third_party/halium14/system/var/lib/lxc/android/android-rootfs.img"

[ -f "$TAR" ]
[ -f "$ANDROID" ]
mkdir -p "$ROOT/out/halium14"
rm -rf "$TREE"
mkdir -p "$TREE"

# --numeric-owner: by name, tar would map messagebus, clickpkg, syslog and
# others to the host's group IDs.
fakeroot sh -eu -c '
    tar --numeric-owner -xzf "$1" -C "$2"
    cp "$3" "$2/var/lib/lxc/android/android-rootfs.img"
    chmod 644 "$2/var/lib/lxc/android/android-rootfs.img"
    /usr/sbin/mke2fs -t ext4 -b 4096 -i 8192 -L userdata -d "$2" -F "$4" 8G
' sh "$TAR" "$TREE" "$ANDROID" "$IMG"

# fakeroot does not carry file capabilities into mke2fs; set the archive's
# security.capability values directly in the image.
python3 - "$TAR" <<'EOF' | while read -r path hex; do
import sys, tarfile
for m in tarfile.open(sys.argv[1]):
    v = m.pax_headers.get("SCHILY.xattr.security.capability")
    if v is not None:
        print(m.name.lstrip("."), v.encode("utf-8", "surrogateescape").hex())
EOF
    printf '%s' "$hex" | xxd -r -p > "$TREE.cap"
    /usr/sbin/debugfs -w -R "ea_set -f $TREE.cap $path security.capability" "$IMG"
    echo "capability $path"
done
rm -f "$TREE.cap"

echo "image $IMG"
ls -lh "$IMG"
sha256sum "$IMG"
