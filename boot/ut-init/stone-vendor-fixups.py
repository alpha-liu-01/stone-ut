#!/usr/bin/python3
"""Fixups for vendor_b, installed into the Halium overlay.

Runs chrooted in the Ubuntu Touch root after stone-dynparts.py has created
/dev/mapper/vendor_b. Every patch is pinned to the SHA256 of the original
file; a different vendor build is left alone.
"""
import hashlib
import os
import subprocess
import sys
import tempfile

OVERLAY = "/usr/share/halium-overlay/android/vendor"
NOP = bytes.fromhex("1f2003d5")

# crDroid 10.11 (Android 14) vndservicemanager. Access::Access() aborts on
# CHECK(selinux_status_open(true) >= 0) and CHECK(getcon(...) == 0) when the
# kernel runs with selinux=0. The rest of its SELinux calls return "allowed"
# with SELinux disabled. The Halium system servicemanager cannot stand in:
# its libbinder expects the 'SYST' parcel header, vendor clients send 'VNDR'.
PATCHES = {
    "bin/vndservicemanager": {
        "sha256": "bf6653db5e1384920732aa2f64a0de2abc297341d4b7775f950d0556b21b4a4f",
        "nops": [
            (0x6128, "8001f837"),  # tbnz w0, #31 -> CHECK(selinux_status_open)
            (0x6134, "c0030035"),  # cbnz w0      -> CHECK(getcon)
        ],
    },
}

# Text edits. CamX's logical multi-sensor cameras cannot work here: camera 0
# became wide + depth (real-time bokeh, Xiaomi AlgoControl aborts) or, with
# Xiaomi's role-ID mapping off, a wide + depth session whose preview showed
# the monochrome depth sensor. With MultiCameraEnable=FALSE the rear camera
# is the wide sensor alone. persist.vendor.camera.mapid=0 turns off Xiaomi's
# camera role-ID remapping (chxcameraidxiaomi.cpp, default "1"); tested
# together. build.prop only gives the default, a persisted value wins.
EDITS = {
    "etc/camera/camxoverridesettings.txt": {
        "sha256": "ee6e420d6aead61f34d9288d395bdbe92f041abdf487e7560cc58bf71bc5db6d",
        "replace": [("MultiCameraEnable=TRUE\n", "MultiCameraEnable=FALSE\n")],
    },
    "build.prop": {
        "append_if_missing": [("persist.vendor.camera.mapid=",
                               "persist.vendor.camera.mapid=0\n")],
    },
}


def write_overlay(rel, data, mode):
    out = os.path.join(OVERLAY, rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(data)
    os.chmod(out, mode)
    return out


def edit(rel, spec, vendor):
    src = os.path.join(vendor, rel)
    data = open(src, "rb").read()
    if "sha256" in spec:
        digest = hashlib.sha256(data).hexdigest()
        if digest != spec["sha256"]:
            print(f"{rel}: sha256 {digest} is not the known build, skipped")
            return
    text = data.decode()
    for old, new in spec.get("replace", []):
        if old not in text:
            print(f"{rel}: {old.strip()!r} not found, skipped")
            return
        text = text.replace(old, new)
    for key, line in spec.get("append_if_missing", []):
        if not any(l.startswith(key) for l in text.splitlines()):
            text += ("" if text.endswith("\n") else "\n") + line
    out = write_overlay(rel, text.encode(), os.stat(src).st_mode & 0o7777)
    print(f"{rel}: edited -> {out}")


def patch(rel, spec, vendor):
    data = bytearray(open(os.path.join(vendor, rel), "rb").read())
    digest = hashlib.sha256(data).hexdigest()
    if digest != spec["sha256"]:
        print(f"{rel}: sha256 {digest} is not the known build, skipped")
        return
    for off, orig in spec["nops"]:
        if data[off:off + 4] != bytes.fromhex(orig):
            print(f"{rel}: unexpected bytes at {off:#x}, skipped")
            return
        data[off:off + 4] = NOP
    out = os.path.join(OVERLAY, rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(data)
    os.chmod(out, 0o755)
    print(f"{rel}: patched {len(spec['nops'])} sites -> {out}")


def main():
    dev = "/dev/mapper/vendor_b"
    if not os.path.exists(dev):
        print(f"{dev} missing")
        return 1
    mnt = tempfile.mkdtemp(prefix="stone-vendor-")
    subprocess.run(["/usr/bin/mount", "-o", "ro", dev, mnt], check=True)
    try:
        for rel, spec in PATCHES.items():
            patch(rel, spec, mnt)
        for rel, spec in EDITS.items():
            edit(rel, spec, mnt)
    finally:
        subprocess.run(["/usr/bin/umount", mnt], check=False)
        os.rmdir(mnt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
