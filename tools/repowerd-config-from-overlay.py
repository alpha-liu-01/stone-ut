#!/usr/bin/env python3
"""Make repowerd's device config for stone from the vendor's framework overlay.

repowerd (screen brightness, proximity during calls) reads
/usr/share/repowerd/device-configs/config-<deviceinfo name>.xml on top of
config-default.xml. The default has config_automatic_brightness_available
false and no curve, so Settings shows no "Adjust automatically".

The vendor's /vendor/overlay/FrameworksResOverlayStone.apk has Android's
values: config_autoBrightnessLevels (lux) and
config_autoBrightnessDisplayValuesNits (one more entry than the levels),
plus config_screenBrightnessNits / config_screenBrightnessBacklight, which map
nits to Android's 1..255 backlight scale. repowerd wants
autoBrightnessLcdBacklightValues in its own units (out of
screenBrightnessSettingMaximum, 255 by default), as integers, so the nits are
converted piecewise-linearly through those two arrays.

The overlay's resources.arsc is written by Android 14's aapt2 (16-bit entry
offsets), which androguard 4.1 cannot read, hence the small parser below.

usage: repowerd-config-from-overlay.py FrameworksResOverlayStone.apk OUT.xml
"""
import struct
import sys
import zipfile



def u16(b, o): return struct.unpack_from("<H", b, o)[0]
def u32(b, o): return struct.unpack_from("<I", b, o)[0]


def string_pool(b, o):
    hsz, size = u16(b, o + 2), u32(b, o + 4)
    count, _styles, flags, sstart = u32(b, o + 8), u32(b, o + 12), u32(b, o + 16), u32(b, o + 20)
    utf8 = flags & 0x100
    offs = [u32(b, o + hsz + 4 * i) for i in range(count)]
    out = []
    for so in offs:
        p = o + sstart + so
        if utf8:
            n = b[p]; p += 2 if n & 0x80 else 1
            n = b[p]
            if n & 0x80:
                n = ((n & 0x7F) << 8) | b[p + 1]; p += 2
            else:
                p += 1
            out.append(b[p:p + n].decode("utf-8", "replace"))
        else:
            n = u16(b, p); p += 2
            if n & 0x8000:
                n = ((n & 0x7FFF) << 16) | u16(b, p); p += 2
            out.append(b[p:p + 2 * n].decode("utf-16-le", "replace"))
    return out, o + size


def value(dtype, data, strings):
    if dtype == 0x03:
        return repr(strings[data]) if data < len(strings) else "str#%d" % data
    if dtype == 0x12:
        return "true" if data else "false"
    if dtype in (0x10, 0x11):
        return str(struct.unpack("<i", struct.pack("<I", data))[0]) if dtype == 0x10 else hex(data)
    if dtype == 0x04:
        return repr(struct.unpack("<f", struct.pack("<I", data))[0])
    if dtype == 0x01:
        return "@0x%08x" % data
    if dtype == 0x05:
        return "dimen(0x%x)" % data
    return "type%d:0x%x" % (dtype, data)


def resources(arsc):
    res = {}
    b = arsc
    hsz = u16(b, 2)
    o = hsz
    strings, o = string_pool(b, o)
    while o < len(b):
        ctype, chsz, csize = u16(b, o), u16(b, o + 2), u32(b, o + 4)
        if ctype == 0x0200:  # package
            pkg_id = u32(b, o + 8)
            type_strings_off, key_strings_off = u32(b, o + 268), u32(b, o + 276)
            types, _ = string_pool(b, o + type_strings_off)
            keys, _ = string_pool(b, o + key_strings_off)
            p = o + chsz
            end = o + csize
            while p < end:
                t, thsz, tsize = u16(b, p), u16(b, p + 2), u32(b, p + 4)
                if t == 0x0201:
                    tid, flags = b[p + 8], b[p + 9]
                    count, estart = u32(b, p + 12), u32(b, p + 16)
                    cfg = b[p + 20:p + thsz]
                    cfg_default = not any(cfg[4:])
                    idx_base = p + thsz
                    entries = []
                    if flags & 0x01:  # sparse
                        for i in range(count):
                            entries.append((u16(b, idx_base + 4 * i), u16(b, idx_base + 4 * i + 2) * 4))
                    elif flags & 0x02:  # offset16
                        for i in range(count):
                            off = u16(b, idx_base + 2 * i)
                            if off != 0xFFFF:
                                entries.append((i, off * 4))
                    else:
                        for i in range(count):
                            off = u32(b, idx_base + 4 * i)
                            if off != 0xFFFFFFFF:
                                entries.append((i, off))
                    tname = types[tid - 1]
                    for idx, off in entries:
                        e = p + estart + off
                        esize, eflags = u16(b, e), u16(b, e + 2)
                        if eflags & 0x08:  # compact
                            key = keys[esize]
                            out = value(eflags >> 8, u32(b, e + 4), strings)
                        else:
                            key = keys[u32(b, e + 4)]
                            if eflags & 0x01:  # complex
                                n = u32(b, e + 12)
                                items = []
                                q = e + esize
                                for _ in range(n):
                                    items.append(value(b[q + 7], u32(b, q + 8), strings))
                                    q += 12
                                out = "[" + ", ".join(items) + "]"
                            else:
                                v = e + esize
                                out = value(b[v + 3], u32(b, v + 4), strings)
                        if cfg_default:
                            res["%s/%s" % (tname, key)] = out
                p += tsize
        o += csize
    return res



def floats(v):
    return [float(x) for x in v.strip("[]").split(", ")]


def interp(x, xs, ys):
    if x <= xs[0]:
        return ys[0]
    for (x0, y0), (x1, y1) in zip(zip(xs, ys), zip(xs[1:], ys[1:])):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return ys[-1]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    res = resources(zipfile.ZipFile(sys.argv[1]).read("resources.arsc"))
    if res.get("bool/config_automatic_brightness_available") != "true":
        sys.exit("overlay does not enable automatic brightness")
    lux = [int(x) for x in floats(res["array/config_autoBrightnessLevels"])]
    nits = floats(res["array/config_autoBrightnessDisplayValuesNits"])
    map_nits = floats(res["array/config_screenBrightnessNits"])
    map_bl = floats(res["array/config_screenBrightnessBacklight"])
    if len(nits) != len(lux) + 1 or len(map_nits) != len(map_bl) or len(nits) > 255:
        sys.exit("unexpected array sizes")
    bl = [max(1, min(255, round(interp(n, map_nits, map_bl)))) for n in nits]
    for a, b in zip(bl, bl[1:]):
        if b < a:
            sys.exit("backlight curve is not monotone")
    dim = res.get("integer/config_screenBrightnessDim")
    with open(sys.argv[2], "w") as f:
        f.write("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
        f.write("<!-- Generated by tools/repowerd-config-from-overlay.py from the vendor's\n"
                "     FrameworksResOverlayStone.apk. Do not edit by hand. -->\n")
        f.write("<resources>\n")
        f.write("    <bool name=\"config_automatic_brightness_available\">true</bool>\n")
        if dim:
            f.write("    <integer name=\"config_screenBrightnessDim\">%s</integer>\n" % dim)
        f.write("    <integer-array name=\"config_autoBrightnessLevels\">\n")
        f.writelines("        <item>%d</item>\n" % x for x in lux)
        f.write("    </integer-array>\n")
        f.write("    <integer-array name=\"config_autoBrightnessLcdBacklightValues\">\n")
        f.writelines("        <item>%d</item>\n" % x for x in bl)
        f.write("    </integer-array>\n")
        f.write("</resources>\n")
    print("%d lux levels, backlight %d..%d, dim %s" % (len(lux), bl[0], bl[-1], dim))


if __name__ == "__main__":
    main()
