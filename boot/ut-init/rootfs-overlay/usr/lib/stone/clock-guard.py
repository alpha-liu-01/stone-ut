#!/usr/bin/python3
# Keep the wall clock from being set back to 1970 (docs/roadmap-release.md
# item 14).
#
# The Qualcomm RTC cannot be set and counts from 1970. UBports' timekeeper
# stores the offset to real time in /data/time/timekeep at shutdown and
# restores it at boot (the initramfs does that even earlier). But the vendor's
# time_daemon, which the Android container starts at about 14 s, sets the clock
# from the RTC plus its own offsets (ats_* in /data/vendor/time), which nobody
# updates on Ubuntu Touch: the clock goes back to January 1970 until NTP, and
# the journal entries of that time end up in files that look 56 years old and
# are deleted first.
#
# Wait for any clock change (timerfd with TFD_TIMER_CANCEL_ON_SET, no polling).
# When the clock is before 2020, set RTC + stored offset again and rotate the
# journal, so the few entries stamped with the wrong time stay in a file of
# their own. Nothing legitimate sets a phone's clock before 2020.
import ctypes
import errno
import os
import subprocess
import time

RTC = "/sys/class/rtc/rtc0/since_epoch"
OFFSET = "/var/lib/android-data/time/timekeep"
PLAUSIBLE = 1577836800  # 2020-01-01

CLOCK_REALTIME = 0
TFD_TIMER_ABSTIME = 1
TFD_TIMER_CANCEL_ON_SET = 2


class timespec(ctypes.Structure):
    _fields_ = [("tv_sec", ctypes.c_long), ("tv_nsec", ctypes.c_long)]


class itimerspec(ctypes.Structure):
    _fields_ = [("it_interval", timespec), ("it_value", timespec)]


libc = ctypes.CDLL(None, use_errno=True)


def log(msg):
    print(f"stone-clock-guard: {msg}", flush=True)


def read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def check(why):
    now = time.time()
    if now >= PLAUSIBLE:
        return
    rtc, off = read_int(RTC), read_int(OFFSET)
    if rtc is None or off is None or rtc + off < PLAUSIBLE:
        log(f"{why}: clock at {time.ctime(now)}, but no usable RTC offset (RTC {rtc}, offset {off})")
        return
    want = rtc + off
    try:
        time.clock_settime(time.CLOCK_REALTIME, float(want))
    except OSError as e:
        log(f"{why}: cannot set the clock: {e}")
        return
    log(f"{why}: clock was {time.ctime(now)}; set back to RTC + offset, {time.ctime(want)}")
    # Close the journal file that now starts with the wrong time.
    subprocess.run(["journalctl", "--rotate"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    fd = libc.timerfd_create(CLOCK_REALTIME, 0)
    if fd < 0:
        log(f"timerfd_create failed: {os.strerror(ctypes.get_errno())}")
        return 1
    # An absolute expiry far in the future: the timer never fires, it is only
    # cancelled (read() gives ECANCELED) when someone sets the clock.
    spec = itimerspec(timespec(0, 0), timespec(1 << 33, 0))
    why = "start"
    while True:
        # Arm first, then look: a change in between still cancels the timer.
        if libc.timerfd_settime(fd, TFD_TIMER_ABSTIME | TFD_TIMER_CANCEL_ON_SET,
                                ctypes.byref(spec), None) < 0:
            log(f"timerfd_settime failed: {os.strerror(ctypes.get_errno())}")
            return 1
        check(why)
        try:
            os.read(fd, 8)
        except OSError as e:
            if e.errno != errno.ECANCELED:
                raise
        why = "clock changed"


raise SystemExit(main())
