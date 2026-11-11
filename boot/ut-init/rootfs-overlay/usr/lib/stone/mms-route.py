#!/usr/bin/env python3
"""Keep MMS traffic on the cellular data call while Wi-Fi is connected.

nuntium sends and fetches MMS through lomiri-upload-manager/download-manager,
which use the system resolver and routing table. With Wi-Fi up:
  - the MMS proxy and MMSC names (Fizz: mmsproxy.mobile.bm, mms.mobile.bm)
    only resolve through the carrier DNS, and NetworkManager's dnsmasq asks
    the Wi-Fi DNS, which answers NXDOMAIN;
  - the default route is wlan0, and ofono adds no host route for a proxy
    given as a hostname, so even a resolved address would go out over Wi-Fi.

For every active ofono context with a MessageCenter (or of type mms), this
service:
  1. adds host routes over the context's interface for its DNS servers,
  2. resolves the proxy and MMSC hosts through those servers,
  3. adds host routes over the context's interface for those addresses,
  4. writes "address name" lines to /run/stone-mms/mms-hosts, which dnsmasq
     reads through hostsdir= (etc/NetworkManager/dnsmasq.d/20-stone-mms.conf).
It re-checks on every ofono context change and every 10 minutes, and removes
its routes when a context goes away.

IPv4 only (the Fizz internet PDN is IPv4-only).
"""
import ipaddress
import os
import random
import re
import socket
import struct
import subprocess
import sys
import urllib.parse

import dbus
import dbus.mainloop.glib
from gi.repository import GLib

OFONO = "org.ofono"
HOSTS_DIR = "/run/stone-mms"
HOSTS_FILE = os.path.join(HOSTS_DIR, "mms-hosts")
REFRESH_S = 600
DNS_TIMEOUT_S = 2.0
HOSTNAME_RE = re.compile(
    r"^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$")

bus = None
installed_routes = {}   # "a.b.c.d" -> (gateway or "", interface)
resolved_cache = {}     # hostname -> [addresses], kept if a lookup fails
written_hosts = None
pending = None


def log(msg):
    print(msg, flush=True)


def ipv4(text):
    try:
        return str(ipaddress.IPv4Address(text))
    except ValueError:
        return None


def skip_name(data, i):
    while True:
        n = data[i]
        if n == 0:
            return i + 1
        if n & 0xC0 == 0xC0:
            return i + 2
        i += 1 + n


def resolve_a(name, servers):
    """A records for name, asked directly of the given DNS servers."""
    labels = name.rstrip(".").split(".")
    for server in servers:
        qid = random.getrandbits(16)
        query = struct.pack(">HHHHHH", qid, 0x0100, 1, 0, 0, 0)
        for label in labels:
            query += bytes([len(label)]) + label.encode("ascii")
        query += b"\0" + struct.pack(">HH", 1, 1)
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.settimeout(DNS_TIMEOUT_S)
                s.connect((server, 53))
                s.send(query)
                data = s.recv(4096)
            rid, flags, qd, an = struct.unpack(">HHHH", data[:8])
            if rid != qid or not flags & 0x8000 or flags & 0x000F:
                continue
            i = 12
            for _ in range(qd):
                i = skip_name(data, i) + 4
            addrs = []
            for _ in range(an):
                i = skip_name(data, i)
                rtype, rclass, _ttl, rdlen = struct.unpack(">HHIH", data[i:i + 10])
                i += 10
                if rtype == 1 and rclass == 1 and rdlen == 4:
                    addrs.append(socket.inet_ntoa(data[i:i + 4]))
                i += rdlen
            if addrs:
                return addrs
        except (OSError, IndexError, struct.error) as e:
            log("dns %s via %s: %s" % (name, server, e))
    return []


def mms_hosts(ctx):
    """Hostnames or addresses the MMS traffic of this context goes to."""
    hosts = []
    proxy = str(ctx.get("MessageProxy", "")).strip()
    if proxy:
        hosts.append(proxy.rsplit(":", 1)[0] if proxy.count(":") == 1 else proxy)
    mmsc = str(ctx.get("MessageCenter", "")).strip()
    if mmsc:
        if "://" not in mmsc:
            mmsc = "http://" + mmsc
        try:
            host = urllib.parse.urlsplit(mmsc).hostname
        except ValueError:
            host = None
        if host:
            hosts.append(host)
    return hosts


def wanted_state():
    routes = {}
    hosts = {}
    manager = dbus.Interface(bus.get_object(OFONO, "/"), "org.ofono.Manager")
    for modem, mprops in manager.GetModems():
        if "org.ofono.ConnectionManager" not in mprops.get("Interfaces", []):
            continue
        cm = dbus.Interface(bus.get_object(OFONO, modem),
                            "org.ofono.ConnectionManager")
        for path, ctx in cm.GetContexts():
            if not bool(ctx.get("Active", False)):
                continue
            if not str(ctx.get("MessageCenter", "")) and str(ctx.get("Type", "")) != "mms":
                continue
            settings = ctx.get("Settings", {})
            iface = str(settings.get("Interface", ""))
            if not iface:
                continue
            gw = ipv4(str(settings.get("Gateway", ""))) or ""
            servers = [a for a in (ipv4(str(x)) for x in
                       settings.get("DomainNameServers", [])) if a]
            for a in servers:
                routes[a] = (gw, iface)
            for host in mms_hosts(ctx):
                addr = ipv4(host)
                if addr:
                    routes[addr] = (gw, iface)
                    continue
                if not HOSTNAME_RE.match(host):
                    log("%s: ignoring odd MMS host %r" % (path, host))
                    continue
                # The DNS server routes must exist before asking them.
                apply_routes({**installed_routes, **routes}, remove=False)
                addrs = resolve_a(host, servers)
                if addrs:
                    resolved_cache[host] = addrs
                else:
                    addrs = resolved_cache.get(host, [])
                    log("%s: could not resolve %s, using %s" % (path, host, addrs))
                for a in addrs:
                    routes[a] = (gw, iface)
                    hosts.setdefault(host.lower(), set()).add(a)
    return routes, hosts


def ip(*args):
    r = subprocess.run(["/usr/sbin/ip", *args], capture_output=True, text=True)
    if r.returncode:
        log("ip %s: %s" % (" ".join(args), r.stderr.strip()))
    return r.returncode == 0


def route_present(dst, gw, iface):
    r = subprocess.run(["/usr/sbin/ip", "-4", "route", "show", "exact", dst + "/32"],
                       capture_output=True, text=True)
    want = "dev %s" % iface
    return any(want in line and (not gw or ("via %s" % gw) in line)
               for line in r.stdout.splitlines())


def apply_routes(routes, remove=True):
    if remove:
        for dst, (gw, iface) in list(installed_routes.items()):
            if routes.get(dst) != (gw, iface):
                ip("-4", "route", "del", dst + "/32", "dev", iface)
                del installed_routes[dst]
                log("route %s via %s removed" % (dst, iface))
    for dst, (gw, iface) in routes.items():
        # NetworkManager or the kernel (interface gone) can drop them.
        if installed_routes.get(dst) == (gw, iface) and route_present(dst, gw, iface):
            continue
        args = ["-4", "route", "replace", dst + "/32"]
        if gw:
            args += ["via", gw]
        args += ["dev", iface]
        if ip(*args):
            installed_routes[dst] = (gw, iface)
            log("route %s via %s %s" % (dst, iface, gw))


def write_hosts(hosts):
    global written_hosts
    text = "".join("%s %s\n" % (a, name)
                   for name in sorted(hosts) for a in sorted(hosts[name]))
    if text == written_hosts:
        return
    os.makedirs(HOSTS_DIR, mode=0o755, exist_ok=True)
    tmp = HOSTS_FILE + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, HOSTS_FILE)
    written_hosts = text
    log("hosts: %s" % (text.strip().replace("\n", ", ") or "(none)"))


def resync():
    global pending
    pending = None
    try:
        routes, hosts = wanted_state()
    except dbus.exceptions.DBusException as e:
        log("ofono not available: %s" % e.get_dbus_name())
        routes, hosts = {}, {}
    apply_routes(routes)
    write_hosts(hosts)
    return False


def schedule(*_args, **_kwargs):
    global pending
    if pending is None:
        pending = GLib.timeout_add(700, resync)


def periodic():
    resync()
    return True


def stop():
    apply_routes({})
    write_hosts({})
    loop.quit()
    return False


if __name__ == "__main__":
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    for iface, member in (("org.ofono.ConnectionContext", "PropertyChanged"),
                          ("org.ofono.ConnectionManager", "ContextAdded"),
                          ("org.ofono.ConnectionManager", "ContextRemoved"),
                          ("org.ofono.Manager", "ModemAdded"),
                          ("org.ofono.Manager", "ModemRemoved")):
        bus.add_signal_receiver(schedule, signal_name=member, dbus_interface=iface)
    bus.add_signal_receiver(schedule, signal_name="NameOwnerChanged",
                            dbus_interface="org.freedesktop.DBus", arg0=OFONO)
    loop = GLib.MainLoop()
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, 15, stop)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, 2, stop)
    GLib.timeout_add_seconds(REFRESH_S, periodic)
    resync()
    loop.run()
    sys.exit(0)
