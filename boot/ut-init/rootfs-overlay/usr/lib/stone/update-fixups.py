#!/usr/bin/python3
"""Keep the port's patched files in step with the installed packages
(docs/roadmap-release.md item 7).

  update-fixups.py apply         regenerate what is out of date, then report
  update-fixups.py apply --apt   the same, quiet unless something needs
                                 attention (run by dpkg after every apt run)
  update-fixups.py check         report only

Generated from what is installed, at boot (stone-update-fixups.service) and
after every dpkg run (/etc/apt/apt.conf.d/99stone-update-fixups):
- /usr/bin/lomiri-telephony-service-handler-stone: the handler with the UCM
  port names (patch-telephony-ports.py). Only for the exact build the patch
  was made for; for another build the copy is removed, and
  telephony-service-handler.sh runs the stock handler (calls work, but the
  earpiece/speaker/Bluetooth choice does not).
- /usr/share/stone/apns-conf.xml: the APN database ofono provisions from
  (ofono.service.d/zz-stone-apndb.conf), with the MVNO entries listed in
  /etc/stone/apndb-mvno.conf (else /usr/share/stone/apndb-mvno.conf) made
  the plain entries for their MCC/MNC (apndb-prefer-mvno.py; ofono-sailfish
  cannot match MVNOs by IMSI or GID1, ofono-apndb-plugin#2).

Reported only (they patch at boot and leave unknown builds alone):
display-setup.sh's Mir patch and Settings page. Also reports packages whose
version differs from the one the port was tested with
(/usr/share/stone/tested-versions.txt).
"""
import hashlib
import os
import re
import subprocess
import sys

LIB = os.environ.get("STONE_LIB", "/usr/lib/stone")  # overridable for tests
STOCK_HANDLER = "/usr/bin/lomiri-telephony-service-handler"
PATCHED_HANDLER = "/usr/bin/lomiri-telephony-service-handler-stone"
APNDB_SRC = "/usr/share/lineageos-apndb/apns-conf.xml"
APNDB_OUT = "/usr/share/stone/apns-conf.xml"
MVNO_CONF = ("/etc/stone/apndb-mvno.conf", "/usr/share/stone/apndb-mvno.conf")
STATE = "/var/lib/stone"
TESTED = "/usr/share/stone/tested-versions.txt"
DISPLAY_SETUP = f"{LIB}/display-setup.sh"


def sha256(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None


def module_constants(path, *names):
    """Read NAME = "value" constants from a script without importing it."""
    found = {}
    with open(path) as f:
        for line in f:
            m = re.match(r'\s*(\w+)\s*=\s*"([0-9a-f]{64})"', line)
            if m and m.group(1) in names:
                found[m.group(1)] = m.group(2)
    return found


def shell_constants(path, *names):
    found = {}
    with open(path) as f:
        for line in f:
            m = re.match(r"(\w+)=([0-9a-f]{64})\b", line)
            if m and m.group(1) in names:
                found[m.group(1)] = m.group(2)
    return found


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr).strip()


def replace_atomically(tmp, dest, mode):
    os.chmod(tmp, mode)
    os.replace(tmp, dest)


def telephony(apply):
    """Returns (ok, message)."""
    script = f"{LIB}/patch-telephony-ports.py"
    want = module_constants(script, "IN_SHA256", "OUT_SHA256")
    stock = sha256(STOCK_HANDLER)
    if stock is None:
        return False, "telephony handler: not installed"
    if stock != want["IN_SHA256"]:
        if apply and os.path.exists(PATCHED_HANDLER):
            os.remove(PATCHED_HANDLER)
        return False, ("telephony handler: installed build is not the one the "
                       "UCM port-name patch was made for; running it unpatched "
                       "(no earpiece/speaker/Bluetooth choice in calls)")
    if sha256(PATCHED_HANDLER) == want["OUT_SHA256"]:
        return True, "telephony handler: patched copy up to date"
    if not apply:
        return False, "telephony handler: patched copy missing or stale"
    tmp = PATCHED_HANDLER + ".new"
    rc, out = run([sys.executable, "-I", script, STOCK_HANDLER, tmp])
    if rc != 0:
        if os.path.exists(tmp):
            os.remove(tmp)
        return False, f"telephony handler: patching failed: {out}"
    replace_atomically(tmp, PATCHED_HANDLER, 0o755)
    return True, "telephony handler: patched copy regenerated"


def mvno_rules():
    for path in MVNO_CONF:
        if os.path.exists(path):
            rules = []
            with open(path) as f:
                for line in f:
                    fields = line.split("#", 1)[0].split()
                    if len(fields) == 4:
                        rules.append(fields)
            return path, rules
    return None, []


def apndb(apply):
    conf, rules = mvno_rules()
    src = sha256(APNDB_SRC)
    if src is None:
        return False, f"apndb: {APNDB_SRC} missing"
    stamp_path = f"{STATE}/apndb.stamp"
    stamp = f"{src} {sha256(conf) if conf else '-'}\n"
    try:
        with open(stamp_path) as f:
            current = f.read() == stamp
    except OSError:
        current = False
    if current and os.path.exists(APNDB_OUT):
        return True, "apndb: up to date"
    if not apply:
        return False, "apndb: out of date"
    os.makedirs(STATE, exist_ok=True)
    os.makedirs(os.path.dirname(APNDB_OUT), exist_ok=True)
    tmp = APNDB_OUT + ".new"
    with open(APNDB_SRC, "rb") as f_in, open(tmp, "wb") as f_out:
        f_out.write(f_in.read())
    notes = []
    for mcc, mnc, mtype, data in rules:
        step = tmp + ".step"
        rc, out = run([sys.executable, "-I", f"{LIB}/apndb-prefer-mvno.py",
                       tmp, step, mcc, mnc, mtype, data])
        if rc == 0:
            os.replace(step, tmp)
            notes.append(out)
        else:
            if os.path.exists(step):
                os.remove(step)
            notes.append(f"{mcc}/{mnc} {mtype}={data}: not applied ({out})")
    replace_atomically(tmp, APNDB_OUT, 0o644)
    with open(stamp_path, "w") as f:
        f.write(stamp)
    detail = "; ".join(notes) if notes else "no MVNO rules, stock database"
    return True, f"apndb: regenerated ({detail})"


def display_setup():
    results = []
    if not os.path.exists(DISPLAY_SETUP):
        return results
    c = shell_constants(DISPLAY_SETUP, "STOCK_SHA", "PAGE_STOCK_SHA")
    lib = "/usr/lib/aarch64-linux-gnu/mir1/server-platform/graphics-android2.so.16"
    page = "/usr/share/lomiri-system-settings/qml-plugins/brightness/PageComponent.qml"
    # display-setup bind-mounts its copies over these files. While mounted,
    # the installed file underneath cannot be read, but "display-setup.sh
    # mounts" (after every dpkg run and at boot) only mounts a copy over the
    # build it was made from, so a mount means the installed build is known.
    for name, path, known in (("Mir 120 Hz patch", lib, c.get("STOCK_SHA")),
                              ("Settings refresh-rate page", page,
                               c.get("PAGE_STOCK_SHA"))):
        mounted = run(["mountpoint", "-q", path])[0] == 0
        if mounted:
            results.append((True, f"{name}: active"))
        elif sha256(path) == known:
            results.append((True, f"{name}: known build, applied at next boot"))
        else:
            results.append((False, f"{name}: installed build is not the one "
                                   "the patch was made for; left alone"))
    return results


def package_versions():
    results = []
    try:
        with open(TESTED) as f:
            tested = dict(line.split(None, 1) for line in f
                          if line.strip() and not line.startswith("#"))
    except OSError:
        return results
    rc, out = run(["dpkg-query", "-W", "-f", "${Package} ${Version}\\n",
                   *tested.keys()])
    installed = dict(line.split(None, 1) for line in out.splitlines()
                     if len(line.split(None, 1)) == 2)
    changed = [p for p, v in tested.items()
               if installed.get(p, "").strip() != v.strip()]
    if changed:
        results.append((False, "changed since tested (re-check calls, data, "
                               "MMS, sensors, audio): " + ", ".join(sorted(changed))))
    else:
        results.append((True, "packages: as tested"))
    return results


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("apply", "check"):
        sys.exit(__doc__)
    apply = sys.argv[1] == "apply" and os.geteuid() == 0
    quiet = "--apt" in sys.argv
    results = [telephony(apply), apndb(apply)]
    results += display_setup()
    results += package_versions()
    for ok, msg in results:
        if not (quiet and ok and "regenerated" not in msg):
            print(f"stone: {msg}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
