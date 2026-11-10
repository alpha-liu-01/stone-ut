#!/usr/bin/python3
# Map the logical partitions of one slot in the Android "super" partition
# to read-only /dev/mapper/<name> devices, using liblp's on-disk format.
# Runs before udev, so dmsetup creates the nodes itself.
import glob
import os
import struct
import subprocess
import sys

LP_PARTITION_RESERVED_BYTES = 4096
LP_METADATA_GEOMETRY_SIZE = 4096
GEOMETRY_MAGIC = 0x616C4467
HEADER_MAGIC = 0x414C5030
TARGET_LINEAR = 0
TARGET_ZERO = 1
DMSETUP = "/usr/sbin/dmsetup"


def part_dev(name):
    for ue in glob.glob("/sys/class/block/*/uevent"):
        fields = dict(
            line.split("=", 1) for line in open(ue).read().splitlines() if "=" in line
        )
        if fields.get("PARTNAME") == name:
            return "/dev/" + fields["DEVNAME"]
    return None


def slot_suffix():
    for arg in open("/proc/cmdline").read().split():
        if arg.startswith("androidboot.slot_suffix="):
            return arg.split("=", 1)[1]
    return ""


def main():
    suffix = sys.argv[1] if len(sys.argv) > 1 else slot_suffix()
    super_dev = part_dev("super")
    if not super_dev:
        print("super partition not found")
        return 1
    print(f"super is {super_dev}, slot suffix {suffix!r}")

    with open(super_dev, "rb") as f:
        f.seek(LP_PARTITION_RESERVED_BYTES)
        geo = f.read(52)
        magic, _, _, max_size, slot_count, block_size = struct.unpack("<II32sIII", geo)
        if magic != GEOMETRY_MAGIC:
            print(f"bad geometry magic {magic:#x}")
            return 1
        slot = {"_a": 0, "_b": 1}.get(suffix, 0)
        slot = min(slot, slot_count - 1)
        print(f"metadata max {max_size}, slots {slot_count}, block {block_size}, using slot {slot}")

        f.seek(LP_PARTITION_RESERVED_BYTES + 2 * LP_METADATA_GEOMETRY_SIZE + slot * max_size)
        meta = f.read(max_size)

    magic, major, minor, header_size = struct.unpack_from("<IHHI", meta, 0)
    if magic != HEADER_MAGIC:
        print(f"bad header magic {magic:#x}")
        return 1
    descs = struct.unpack_from("<12I", meta, 80)
    tables = meta[header_size:]
    print(f"metadata v{major}.{minor}, header {header_size}")

    def table(i):
        off, num, size = descs[i * 3 : i * 3 + 3]
        return [tables[off + n * size : off + (n + 1) * size] for n in range(num)]

    extents = [struct.unpack("<QIQI", e[:24]) for e in table(1)]
    devices = table(3)
    if len(devices) != 1:
        print(f"{len(devices)} block devices; only a single super is handled")
        return 1

    env = dict(os.environ, DM_DISABLE_UDEV="1", PATH="/usr/sbin:/usr/bin:/sbin:/bin")
    for p in table(0):
        name = p[:36].split(b"\0", 1)[0].decode()
        attrs, first, count, _ = struct.unpack_from("<IIII", p, 36)
        if count == 0 or name.endswith("-cow"):
            continue
        if suffix and name[-2:] in ("_a", "_b") and not name.endswith(suffix):
            continue
        lines = []
        start = 0
        for num, ttype, data, source in extents[first : first + count]:
            if ttype == TARGET_LINEAR and source == 0:
                lines.append(f"{start} {num} linear {super_dev} {data}")
            elif ttype == TARGET_ZERO:
                lines.append(f"{start} {num} zero")
            else:
                lines = None
                break
            start += num
        if not lines:
            print(f"{name}: unsupported extent, skipped")
            continue
        if os.path.exists(f"/dev/mapper/{name}"):
            print(f"{name}: already mapped")
            continue
        r = subprocess.run(
            [DMSETUP, "create", name, "--readonly", "--noudevsync"],
            input="\n".join(lines) + "\n",
            text=True,
            env=env,
            capture_output=True,
        )
        status = "ok" if r.returncode == 0 else f"failed: {r.stderr.strip()}"
        print(f"{name}: {start} sectors, {len(lines)} extents, {status}")
    subprocess.run([DMSETUP, "mknodes"], env=env)
    return 0


if __name__ == "__main__":
    sys.exit(main())
