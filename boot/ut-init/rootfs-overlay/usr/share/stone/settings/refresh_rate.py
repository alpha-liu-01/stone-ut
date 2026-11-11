"""Backend of the refresh rate section in System Settings (pyotherside).

Runs inside lomiri-system-settings as phablet. Saving the rate and
restarting the display need root, so a request is written to
/run/stone-refresh-rate/request (directory 0770 root:phablet, from
tmpfiles); stone-refresh-rate.path starts stone-refresh-rate-request.service,
which runs /usr/lib/stone/refresh-rate-request.sh as root.
"""
import os
import subprocess

RATE_FILE = "/etc/stone/refresh-rate"
REQUEST_DIR = "/run/stone-refresh-rate"
REQUEST = REQUEST_DIR + "/request"


def _saved():
    try:
        with open(RATE_FILE) as f:
            rate = int(f.read().strip())
        return rate if rate in (60, 120) else 120
    except (OSError, ValueError):
        return 120


def _current():
    """The panel's active mode, from the composer ("#0 120.00 Hz")."""
    try:
        out = subprocess.run(["python3", "-I", "/usr/lib/stone/display-mode.py", "get"],
                             capture_output=True, text=True, timeout=5).stdout
        return int(round(float(out.split()[1])))
    except (OSError, subprocess.SubprocessError, IndexError, ValueError):
        return 0


def state():
    return {"saved": _saved(), "current": _current(),
            "available": os.access(REQUEST_DIR, os.W_OK)}


def request(rate, restart):
    rate = int(rate)
    if rate not in (60, 120):
        raise ValueError("rate must be 60 or 120")
    with open(REQUEST, "w") as f:
        f.write("%d %s\n" % (rate, "restart" if restart else "save"))
    return True
