#!/usr/bin/python3
# Restart Android's logd when it has deadlocked (docs/roadmap-release.md
# item 15).
#
# A log reader with a uid of 10000 or more (phablet running /system/bin/logcat,
# for example) makes logd ask Android's framework for the user's consent; on
# Halium nothing answers and logd deadlocks: it takes no more log lines, and
# every reader gets nothing. Every 30 s, ask logd its buffer size as root
# (exempt from the consent check, so the probe itself is safe); after two
# failed probes in a row, restart it.
import socket
import subprocess
import time

PERIOD = 30
TIMEOUT = 3


def log(msg):
    print(f"stone-logd-watchdog: {msg}", flush=True)


def probe():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(TIMEOUT)
    try:
        s.connect("/dev/socket/logd")
        s.sendall(b"getLogSize 0\0")
        return bool(s.recv(64))
    except OSError:
        return False
    finally:
        s.close()


def restart():
    r = subprocess.run(["lxc-attach", "-n", "android", "--",
                        "/system/bin/setprop", "ctl.restart", "logd"],
                       capture_output=True, text=True, timeout=30)
    return r.returncode == 0, (r.stderr or r.stdout).strip()


def main():
    failures = 0
    while True:
        time.sleep(PERIOD)
        if probe():
            failures = 0
            continue
        failures += 1
        if failures < 2:
            continue
        ok, out = restart()
        time.sleep(3)
        log("logd did not answer twice; restarted it: " +
            ("logd answers again" if ok and probe() else f"still not answering {out}"))
        failures = 0


main()
