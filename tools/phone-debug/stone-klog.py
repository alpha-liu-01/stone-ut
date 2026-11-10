#!/usr/bin/python3 -I
"""Record the kernel log to a file with fsync after every write, so what the
kernel printed right before a hard reset survives it.

phablet cannot open /dev/kmsg (root:system 0620), so `dmesg -w` does not
work; but syslog(2) READ_ALL is allowed (dmesg_restrict=0). Poll it every
100 ms and append only records newer than the last one written."""
import ctypes
import os
import re
import sys
import time

out = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/stone-klog.txt")
libc = ctypes.CDLL(None, use_errno=True)
SYSLOG_ACTION_READ_ALL = 3
SYSLOG_ACTION_SIZE_BUFFER = 10
size = libc.klogctl(SYSLOG_ACTION_SIZE_BUFFER, None, 0)
buf = ctypes.create_string_buffer(size)
ts_re = re.compile(rb"^<\d+>\[\s*(\d+\.\d+)\]")

fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
os.write(fd, b"==== klog start (boot_id %s)\n" %
         open("/proc/sys/kernel/random/boot_id", "rb").read().strip())
os.fsync(fd)

last = -1.0
while True:
    n = libc.klogctl(SYSLOG_ACTION_READ_ALL, buf, size)
    if n > 0:
        new = []
        for line in buf.raw[:n].split(b"\n"):
            m = ts_re.match(line)
            if m and float(m.group(1)) > last:
                new.append(line)
                last = float(m.group(1))
        if new:
            os.write(fd, b"\n".join(new) + b"\n")
            os.fsync(fd)
    time.sleep(0.1)
