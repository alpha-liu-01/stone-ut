#!/usr/bin/env python3
"""Produce the media-hub-server that tolerates an empty AppArmor label.

This kernel's AppArmor cannot fill in a unix socket's peer label
(SO_PEERSEC -> ENOPROTOOPT), so the session bus answers
AppArmorSecurityContextUnknown and media-hub gets an empty profile name and
aborts; ringtone preview in Settings then fails (roadmap-hardware.md item 3).
The patch makes an empty label the static QString "unconfined" and lets
parsing continue.

Applies only to the exact media-hub 4.7~20260611100903.31~3b69471 binary
(input and output SHA256 are checked).

usage: patch-media-hub.py IN OUT
"""
import hashlib
import sys

IN_SHA256 = "fa86280b61e5044ebc34fd4ccac58baaab92444e7a4ae419795470f99ba85198"
OUT_SHA256 = "c75069d101a67e42303d6cbf78a25dc8d4e2a35e899d649e4f5e21cc24c21d5e"
OFFSET = 0x33ed4
OLD = bytes.fromhex(
    "000280d23676ff97010100d0f40300aa21800e91de71ff9775020090b5ea47f9"
    "e04f40f9a10240f9000001eb010080d241f8ff546202009042d447f9e00314aa6102")
NEW = bytes.fromhex(
    "010000140000009000a03b91e00300f9fbfdff17ffffffff0a0000000b000000"
    "00000000180000000000000075006e0063006f006e00660069006e00650064000000")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    data = bytearray(open(sys.argv[1], "rb").read())
    if hashlib.sha256(data).hexdigest() != IN_SHA256:
        sys.exit("%s: unexpected media-hub-server build, not patching" % sys.argv[1])
    assert data[OFFSET:OFFSET + len(OLD)] == OLD
    data[OFFSET:OFFSET + len(NEW)] = NEW
    if hashlib.sha256(data).hexdigest() != OUT_SHA256:
        sys.exit("patched result does not match the tested binary")
    with open(sys.argv[2], "wb") as f:
        f.write(data)
    print("media-hub-server patched at 0x%x (%d bytes)" % (OFFSET, len(NEW)))


if __name__ == "__main__":
    main()
