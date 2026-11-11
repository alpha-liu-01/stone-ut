#!/usr/bin/python3
"""Run the voice call audio session and follow the route PulseAudio picked.

Who decides what:
- lomiri-telephony-service picks the call output (earpiece by default,
  speaker or Bluetooth from the dialer's audio button, the 3.5 mm headset or
  Bluetooth on their own when connected) and switches the
  sink.primary/source.primary ports.
- PulseAudio applies that port's routing from the UCM profile
  /usr/share/stone/ucm2/stone/HiFi.conf.
- This daemon does what the vendor audio HAL would do on top of that:
  * while ofono has a call that needs audio, hold the voice session open
    (call-audio.sh on), and restart it when the port changes so the DSP
    picks up the new devices;
  * mirror the source.primary mute (the dialer's mute button) into the DSP;
  * while the Bluetooth port is active, keep source.fake.sco open: the
    PulseAudio bluez module only opens the SCO link to the headset while
    the fake SCO sink or source is in use ("SCO over PCM"; the audio itself
    runs over SLIMbus). The BT chip only appears on SLIMbus while that link
    is up, so the link has to exist before the voice session starts;
  * while sink.primary is on the USB port (calls played by the DSP through
    USB audio offload), keep PulseAudio's own USB sink and source suspended
    so the DSP can take the device; outside calls move sink.primary off that
    port
    (telephony-service leaves it there after a call), and make a USB card
    present at PulseAudio startup the default, see prefer_usb_defaults();
  * if the 3.5 mm jack state is missing (no StoneJack card), keep calls and
    media off the Headphones port, see no_jack().

Event driven (ofono D-Bus signals, pactl subscribe), so it costs nothing
while idle. Debug: STONE_CALL_REC_UL=1 records 8 s of the uplink per call.
"""
import json
import os
import signal
import subprocess
import time

import dbus
import dbus.mainloop.glib
from gi.repository import GLib

import call_volume

CTL = os.environ.get("STONE_CALL_AUDIO", "/usr/lib/stone/call-audio.sh")
SINK = "sink.primary"
SOURCE = "source.primary"
BT_PORT = "[Out] Bluetooth"
HP_PORT = "[Out] Headphones"
USB_PORT = "[Out] USB"
USB_MIC_PORT = "[In] USBMic"
# PulseAudio's own sinks/sources on USB audio cards (module-udev-detect).
USB_SINK_PREFIX = "alsa_output.usb-"
USB_SOURCE_PREFIX = "alsa_input.usb-"
FAKE_SCO_SOURCE = "source.fake.sco"
MODEMS = ("/ril_0", "/ril_1")
# The voice path is needed for ringback (alerting) and the call itself. An
# incoming call that has not been answered does not need it.
VOICE_STATES = {"dialing", "alerting", "active", "held"}
# telephony-service switches the port right after the call appears; wait for
# it to settle instead of starting the session twice.
SETTLE = 0.6
# Safety net in case a signal is missed (ofono restart and the like).
RESYNC_S = 30
GAIN_FILE = os.path.expanduser("~/.config/stone/call-mic-gain")
# If sink.primary is still missing this long after PulseAudio answered, the
# UCM card failed to load; see speaker_fallback().
FALLBACK_AFTER_S = 10
FALLBACK_SINK = "sink.speaker"
# The built-in card, by id: a USB audio card present at boot can take any
# slot (the kernel command line keeps USB off slot 0, but do not rely on it).
MAIN_CARD = "hw:holiqrdsku1sndc"
UCM_ENV = dict(os.environ, ALSA_CONFIG_UCM2=os.environ.get(
    "ALSA_CONFIG_UCM2", "/usr/share/stone/ucm2"))
# Wideband (mSBC) Bluetooth calls: with enable_msbc=true ofono negotiates mSBC
# with headsets that support it, and the kernel (patch 0009) sets the link up
# with the controller encoding mSBC from 16 kHz PCM on the SLIMbus path. It
# counts those links here; SLIMBUS_7 then has to run at 16 kHz instead of the
# UCM default of 8 kHz (CVSD). The link comes up once source.fake.sco is open.
MSBC_ACTIVE = "/sys/module/bluetooth/parameters/sco_offload_msbc_active"
BT_RATE_CONTROLS = ("BT SampleRate", "BT SampleRate RX", "BT SampleRate TX")
SCO_LINK_WAIT_S = 3.0


def log(*args):
    print(*args, flush=True)


def pactl_json(*args):
    out = subprocess.run(["pactl", "-f", "json", *args], capture_output=True,
                         timeout=5).stdout
    return json.loads(out or b"[]")


class Router:
    def __init__(self, loop):
        self.loop = loop
        self.bus = dbus.SystemBus()
        self.calls = {}           # ofono call path -> state
        self.port = None          # sink.primary active port, None if no sink
        self.port_since = 0.0
        self.src_mute = False
        self.call_since = None
        self.session = False      # voice session running
        self.session_port = None  # port it was started on
        self.session_sub = None   # subscription (1 = SIM 1, 2 = SIM 2) it runs for
        self.muted = False
        self.recorded = False
        self.sco = None           # process holding source.fake.sco open
        self.sub = None           # pactl subscribe
        self.pa_timer = None
        self.eval_timer = None
        self.fallback_timer = None
        self.fallback = False
        self.jack_warned = False
        self.usb_devs = set()     # ("sink"|"source", name) of PA's USB card
        self.usb_held = set()     # those suspended by us
        self.sink_avail = {}      # sink.primary port -> availability
        self.src_port = None      # source.primary active port
        self.src_avail = {}
        self.defaults_checked = False
        self.had_calls = False
        self.post_call_until = 0.0  # see prefer_usb_defaults()
        # In-call volume: phone role stream -> codec gain (call_volume.py).
        try:
            self.call_volume = call_volume.CallVolume(log)
        except OSError as e:
            log("call volume unavailable: %s" % e)
            self.call_volume = None

        self.bus.add_signal_receiver(
            self.on_call_added, "CallAdded", "org.ofono.VoiceCallManager",
            "org.ofono")
        self.bus.add_signal_receiver(
            self.on_call_removed, "CallRemoved", "org.ofono.VoiceCallManager",
            "org.ofono")
        self.bus.add_signal_receiver(
            self.on_call_property, "PropertyChanged", "org.ofono.VoiceCall",
            "org.ofono", path_keyword="path")
        self.bus.add_signal_receiver(
            lambda *_: self.resync(), "NameOwnerChanged",
            "org.freedesktop.DBus", arg0="org.ofono")
        GLib.timeout_add_seconds(RESYNC_S, self.resync)
        self.resync()
        self.subscribe()

    # --- ofono ------------------------------------------------------------
    def resync(self):
        calls = {}
        for path in MODEMS:
            try:
                mgr = dbus.Interface(self.bus.get_object("org.ofono", path),
                                     "org.ofono.VoiceCallManager")
                for call, props in mgr.GetCalls(timeout=2):
                    calls[str(call)] = str(props.get("State", ""))
            except dbus.DBusException:
                pass
        if calls != self.calls:
            self.calls = calls
            self.evaluate()
        return True

    def on_call_added(self, path, props):
        self.calls[str(path)] = str(props.get("State", ""))
        self.evaluate()

    def on_call_removed(self, path):
        self.calls.pop(str(path), None)
        self.evaluate()

    def on_call_property(self, name, value, path=None):
        if name == "State" and path is not None:
            self.calls[str(path)] = str(value)
            self.evaluate()

    # --- PulseAudio -------------------------------------------------------
    def subscribe(self):
        try:
            self.sub = subprocess.Popen(["pactl", "subscribe"],
                                        stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL)
        except OSError:
            self.sub = None
            GLib.timeout_add_seconds(2, lambda: self.subscribe() and False)
            return
        GLib.io_add_watch(self.sub.stdout.fileno(), GLib.PRIORITY_DEFAULT,
                          GLib.IO_IN | GLib.IO_HUP, self.on_pa_event)
        self.defaults_checked = False
        self.schedule_read_pa()

    def on_pa_event(self, fd, cond):
        # Unbuffered: a buffered readline() could keep lines GLib never
        # reports again.
        data = os.read(fd, 65536) if cond & GLib.IO_IN else b""
        if not data:
            # PulseAudio went away; reconnect once it is back.
            self.sub.wait()
            self.sub = None
            GLib.timeout_add_seconds(2, lambda: self.subscribe() and False)
            return False
        if any(k in data for k in (b" on sink ", b" on source ", b" on card ",
                                   b" on server")):
            self.schedule_read_pa()
        return True

    def schedule_read_pa(self):
        # Port switches come in bursts; read once they are done.
        if self.pa_timer is None:
            self.pa_timer = GLib.timeout_add(100, self.read_pa)

    def read_pa(self):
        self.pa_timer = None
        port, mute = None, False
        try:
            sinks = pactl_json("list", "sinks")
            sources = pactl_json("list", "sources")
            self.usb_devs = \
                {("sink", s.get("name")) for s in sinks
                 if s.get("name", "").startswith(USB_SINK_PREFIX)} | \
                {("source", s.get("name")) for s in sources
                 if s.get("name", "").startswith(USB_SOURCE_PREFIX)}
            for s in sinks:
                if s.get("name") == SINK:
                    port = s.get("active_port")
                    self.sink_avail = {p.get("name"): p.get("availability")
                                       for p in s.get("ports", [])}
            for s in sources:
                if s.get("name") == SOURCE:
                    mute = bool(s.get("mute"))
                    self.src_port = s.get("active_port")
                    self.src_avail = {p.get("name"): p.get("availability")
                                      for p in s.get("ports", [])}
        except (OSError, ValueError, subprocess.SubprocessError) as e:
            log("pulseaudio not readable: %s" % e)
            return False
        hp_avail = self.sink_avail.get(HP_PORT)
        if port != self.port:
            log("route: %s -> %s" % (self.port, port))
            self.port, self.port_since = port, time.monotonic()
        self.src_mute = mute
        if hp_avail == "availability unknown" and self.no_jack(port):
            return False  # port switch requested; its event brings us back
        if port is None and self.fallback_timer is None and not self.fallback:
            self.fallback_timer = GLib.timeout_add_seconds(
                FALLBACK_AFTER_S, self.speaker_fallback)
        if not self.defaults_checked and port is not None:
            self.defaults_checked = True
            self.prefer_usb_defaults("present at startup")
        elif not self.calls and time.monotonic() < self.post_call_until:
            self.prefer_usb_defaults("after the call")
        self.evaluate()
        return False

    def prefer_usb_defaults(self, why):
        """Make a USB card the default where switch-on-connect cannot.

        - At PulseAudio startup: stone-touch.pa sets sink.primary/
          source.primary as defaults after module-udev-detect has added any
          USB card, and module-switch-on-connect does nothing during startup.
        - Shortly after a call: telephony-service restores the defaults it
          saved when the call began, which were the built-in ones if the
          USB headset was plugged in during the call.
        A USB card plugged in at other times becomes the default through
        switch-on-connect as usual. Not during calls (telephony-service
        manages the defaults then)."""
        if self.calls:
            return
        for kind, ours in (("sink", SINK), ("source", SOURCE)):
            usb = sorted(n for k, n in self.usb_devs if k == kind)
            if not usb:
                continue
            cur = subprocess.run(["pactl", "get-default-" + kind],
                                 capture_output=True, text=True).stdout.strip()
            if cur == ours:
                log("default %s: %s -> %s (%s)" % (kind, cur, usb[0], why))
                subprocess.run(["pactl", "set-default-" + kind, usb[0]])

    def leave_usb_port(self):
        """Move sink.primary/source.primary off the USB ports outside calls.

        telephony-service selects the "wired" output when a call ends and at
        startup, which here is the DSP's USB route. Outside calls media for
        the USB device goes through PulseAudio's own USB card, and an idle
        DSP USB route must not compete with it for the device. Back to the
        best other port (3.5 mm if plugged, else the built-in ones).
        Returns True if a switch was requested."""
        moved = False
        if self.port == USB_PORT:
            out = HP_PORT if self.sink_avail.get(HP_PORT) == "available" \
                else "[Out] Speaker"
            log("route: no call, leaving %s for %s" % (USB_PORT, out))
            subprocess.run(["pactl", "set-sink-port", SINK, out])
            moved = True
        if self.src_port == USB_MIC_PORT:
            mic = "[In] Headset" \
                if self.src_avail.get("[In] Headset") == "available" \
                else "[In] Mic"
            subprocess.run(["pactl", "set-source-port", SOURCE, mic])
            moved = True
        return moved

    def no_jack(self, port):
        """The 3.5 mm jack state is missing (no "StoneJack" card).

        PulseAudio then treats the Headphones port as possibly connected:
        being the highest priority it picks it at startup (the speaker goes
        silent) and telephony-service routes every call to it. Move off it
        whenever it gets selected. Returns True if a switch was requested."""
        if not self.jack_warned:
            self.jack_warned = True
            log("ERROR: no 3.5 mm jack detection (%s availability unknown; "
                "is the StoneJack card missing?); keeping calls and media "
                "off the headphones" % HP_PORT)
        if port != HP_PORT:
            return False
        in_call = any(s in VOICE_STATES for s in self.calls.values())
        out = "[Out] Earpiece" if in_call else "[Out] Speaker"
        log("route: leaving %s for %s" % (HP_PORT, out))
        subprocess.run(["pactl", "set-sink-port", SINK, out])
        subprocess.run(["pactl", "set-source-port", SOURCE, "[In] Mic"])
        return True

    def speaker_fallback(self):
        """Last resort if PulseAudio could not load the UCM card.

        Without sink.primary there is no speaker at all (only the fake SCO
        sink) and no call routes. Apply the UCM Speaker routing directly and
        give PulseAudio a plain sink on the same no-rewind PCM, like before
        the UCM profile existed. Calls still get audio from start()."""
        self.fallback_timer = None
        if self.port is not None or self.fallback:
            return False
        try:
            names = [s.get("name") for s in pactl_json("list", "sinks")]
        except (OSError, ValueError, subprocess.SubprocessError):
            return False  # PulseAudio not up; checked again on its next event
        if SINK in names or FALLBACK_SINK in names:
            return False
        log("ERROR: no %s (UCM card failed to load, see the pulseaudio log); "
            "falling back to %s without call routes" % (SINK, FALLBACK_SINK))
        self.fallback = True
        subprocess.run(["alsaucm", "-c", MAIN_CARD, "set", "_verb", "Voice Call",
                        "set", "_enadev", "Speaker"], env=UCM_ENV)
        subprocess.run(["pactl", "load-module", "module-alsa-sink",
                        "device=stone_mm5", "sink_name=" + FALLBACK_SINK,
                        "channels=2", "rate=48000", "tsched=0", "fragments=4",
                        "fragment_size=1920",
                        "sink_properties=device.description=Speaker"])
        subprocess.run(["pactl", "set-default-sink", FALLBACK_SINK])
        return False

    # --- actions ----------------------------------------------------------
    def hold_sco(self, want):
        running = self.sco is not None and self.sco.poll() is None
        if want and not running:
            log("bluetooth: opening %s for the SCO link" % FAKE_SCO_SOURCE)
            self.sco = subprocess.Popen(
                ["parec", "--raw", "-d", FAKE_SCO_SOURCE],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif not want and running:
            log("bluetooth: closing %s" % FAKE_SCO_SOURCE)
            self.sco.terminate()
            self.sco.wait()
            self.sco = None

    def hold_usb(self, want):
        """Release PulseAudio's USB card while a call uses the USB route.

        On "[Out] USB" the DSP plays to (and with "[In] USB" records from)
        the USB device itself (offload); the kernel only hands it the
        endpoints while the host driver has the streams closed (the kernel
        refuses otherwise, kernel/patches/0004), so PulseAudio's own sink
        and source for that card stay suspended while the port is selected
        (the sink may still be open from the ringtone). Outside calls the
        port is left at once, see leave_usb_port(): that sink is where media
        for the device plays."""
        target = set(self.usb_devs) if want else set()
        for kind, name in sorted(target - self.usb_held):
            log("usb: suspending %s for the DSP route" % name)
            subprocess.run(["pactl", "suspend-" + kind, name, "1"])
        for kind, name in sorted(self.usb_held - target):
            if (kind, name) in self.usb_devs:
                log("usb: resuming %s" % name)
                subprocess.run(["pactl", "suspend-" + kind, name, "0"])
        self.usb_held = target

    def bt_rate(self):
        """Set SLIMBUS_7 to 16 kHz for an mSBC link, 8 kHz otherwise."""
        deadline = time.monotonic() + SCO_LINK_WAIT_S
        link = False
        while True:
            try:
                out = subprocess.run(["hcitool", "con"], capture_output=True,
                                     text=True, timeout=2).stdout
                link = any(l.split()[1:2] in (["SCO"], ["eSCO"])
                           for l in out.splitlines() if l.strip().startswith(("<", ">")))
            except (OSError, subprocess.SubprocessError, IndexError):
                pass
            if link or time.monotonic() > deadline:
                break
            time.sleep(0.1)
        try:
            msbc = int(open(MSBC_ACTIVE).read().strip()) > 0
        except (OSError, ValueError):
            msbc = False
        rate = "KHZ_16" if msbc else "KHZ_8"
        # The rate only applies when the SLIMBUS_7 back end starts. On an
        # incoming call telephony-service moves the route to Bluetooth while
        # the ringtone plays, so PulseAudio's media stream (MultiMedia5 ->
        # SLIMBUS_7_RX) has already started the back end at the UCM default
        # of 8 kHz; the voice session would join it there and an mSBC link
        # gets silence. Close PulseAudio's side first (suspend), set the
        # rate, then let it reopen: everything after starts at this rate.
        subprocess.run(["pactl", "suspend-sink", SINK, "1"])
        subprocess.run(["pactl", "suspend-source", SOURCE, "1"])
        for name in BT_RATE_CONTROLS:
            subprocess.run(["amixer", "-q", "-D", MAIN_CARD, "cset", "name=%s" % name, rate])
        subprocess.run(["pactl", "suspend-sink", SINK, "0"])
        subprocess.run(["pactl", "suspend-source", SOURCE, "0"])
        log("bluetooth: %s link, SLIMBUS_7 %s" % (
            "mSBC (wideband)" if msbc else ("CVSD" if link else "no SCO"), rate))

    def voice_sub(self):
        """Subscription of the call that needs the voice path.

        Each SIM has its own DSP voice session: SIM 1 (ofono /ril_0)
        VoiceMMode1, SIM 2 (/ril_1) VoiceMMode2. The modem uses the one of
        the SIM the call is on; the other session stays silent."""
        subs = {2 if path.startswith("/ril_1/") else 1
                for path, state in self.calls.items() if state in VOICE_STATES}
        return 2 if subs == {2} else 1

    def start(self):
        if self.port == BT_PORT:
            self.bt_rate()
        if self.port is None:
            # No PulseAudio sink: apply the same UCM profile directly so a
            # call still has audio (earpiece).
            log("no %s; enabling UCM Earpiece directly" % SINK)
            subprocess.run(["alsaucm", "-c", MAIN_CARD, "set", "_verb", "Voice Call",
                            "set", "_enadev", "Earpiece"], env=UCM_ENV)
        sub = self.voice_sub()
        subprocess.run([CTL, "on"] + (["muted"] if self.src_mute else []) +
                       (["sub2"] if sub == 2 else []))
        try:
            gain = open(GAIN_FILE).read().strip()
        except OSError:
            gain = ""
        if gain:
            subprocess.run([CTL, "gain", gain])
        log("call audio on: %s, SIM %d%s%s" % (self.port, sub, ", muted" if self.src_mute else "",
                                       ", gain +%s dB" % gain if gain else ""))
        self.session, self.session_port, self.session_sub = True, self.port, sub
        self.muted = self.src_mute

    def stop(self):
        subprocess.run([CTL, "off"])
        log("call audio off")
        self.session, self.session_port, self.session_sub = False, None, None
        self.recorded = False

    def evaluate(self):
        if self.eval_timer is not None:
            GLib.source_remove(self.eval_timer)
            self.eval_timer = None
        now = time.monotonic()
        states = sorted(self.calls.values())
        want = any(s in VOICE_STATES for s in states)
        if self.calls:
            self.had_calls = True
        elif self.had_calls:
            # telephony-service restores its saved defaults about 2 s after
            # the call; that change comes back here through read_pa().
            self.had_calls = False
            self.post_call_until = now + 15
        self.hold_sco(self.port == BT_PORT)
        # Whenever sink.primary is on the USB port, not only in calls:
        # PulseAudio applies the route the moment telephony-service selects
        # it (at startup, ringing and hang-up too), and anything playing on
        # sink.primary then makes the DSP take the device. The host stream
        # must be closed by then. Outside calls leave_usb_port() moves off
        # the port right away, so this lasts only a moment.
        self.hold_usb(self.port == USB_PORT)
        if not self.calls and self.leave_usb_port():
            return False  # its port event brings us back

        if self.call_volume:
            self.call_volume.set(want, self.port)
        if not want:
            if self.call_since is not None:
                log("calls: %s" % (" ".join(states) or "none"))
            self.call_since = None
            if self.session:
                self.stop()
            return False
        if self.call_since is None:
            self.call_since = now
            log("calls: %s" % " ".join(states))
        wait = max(self.call_since, self.port_since) + SETTLE - now
        if not self.session or self.session_port != self.port or \
                self.session_sub != self.voice_sub():
            if wait > 0:
                self.eval_timer = GLib.timeout_add(int(wait * 1000) + 10,
                                                   self.evaluate)
                return False
            self.start()
        elif self.muted != self.src_mute:
            subprocess.run([CTL, "mute", "1" if self.src_mute else "0"])
            self.muted = self.src_mute
            log("mic %s" % ("muted" if self.muted else "unmuted"))
        if os.environ.get("STONE_CALL_REC_UL") and not self.recorded and \
                "active" in states:
            self.recorded = True
            out = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
                               "stone-uplink-%d.raw" % time.time())
            subprocess.Popen([CTL, "rec-ul", "8", out])
        return False

    def shutdown(self):
        if self.call_volume:
            self.call_volume.shutdown()
        if self.session:
            self.stop()
        self.hold_sco(False)
        self.hold_usb(False)
        if self.sub and self.sub.poll() is None:
            self.sub.terminate()
        self.loop.quit()
        return False


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    loop = GLib.MainLoop()
    router = Router(loop)
    for sig in (signal.SIGTERM, signal.SIGINT):
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, sig, router.shutdown)
    loop.run()


if __name__ == "__main__":
    main()
