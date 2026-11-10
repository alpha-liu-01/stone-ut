#!/usr/bin/python3
"""Run the voice call audio session and follow the route PulseAudio picked.

Who decides what:
- lomiri-telephony-service picks the call output (earpiece by default,
  speaker or Bluetooth from the dialer's audio button, Bluetooth on its own
  when a headset is connected) and switches the sink.primary/source.primary
  ports.
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
    is up, so the link has to exist before the voice session starts.

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

CTL = os.environ.get("STONE_CALL_AUDIO", "/usr/lib/stone/call-audio.sh")
SINK = "sink.primary"
SOURCE = "source.primary"
BT_PORT = "[Out] Bluetooth"
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
UCM_ENV = dict(os.environ, ALSA_CONFIG_UCM2=os.environ.get(
    "ALSA_CONFIG_UCM2", "/usr/share/stone/ucm2"))


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
        self.muted = False
        self.recorded = False
        self.sco = None           # process holding source.fake.sco open
        self.sub = None           # pactl subscribe
        self.pa_timer = None
        self.eval_timer = None
        self.fallback_timer = None
        self.fallback = False

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
            for s in pactl_json("list", "sinks"):
                if s.get("name") == SINK:
                    port = s.get("active_port")
            for s in pactl_json("list", "sources"):
                if s.get("name") == SOURCE:
                    mute = bool(s.get("mute"))
        except (OSError, ValueError, subprocess.SubprocessError) as e:
            log("pulseaudio not readable: %s" % e)
        if port != self.port:
            log("route: %s -> %s" % (self.port, port))
            self.port, self.port_since = port, time.monotonic()
        self.src_mute = mute
        if port is None and self.fallback_timer is None and not self.fallback:
            self.fallback_timer = GLib.timeout_add_seconds(
                FALLBACK_AFTER_S, self.speaker_fallback)
        self.evaluate()
        return False

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
        subprocess.run(["alsaucm", "-c", "hw:0", "set", "_verb", "HiFi",
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

    def start(self):
        if self.port is None:
            # No PulseAudio sink: apply the same UCM profile directly so a
            # call still has audio (earpiece).
            log("no %s; enabling UCM Earpiece directly" % SINK)
            subprocess.run(["alsaucm", "-c", "hw:0", "set", "_verb", "HiFi",
                            "set", "_enadev", "Earpiece"], env=UCM_ENV)
        subprocess.run([CTL, "on"] + (["muted"] if self.src_mute else []))
        try:
            gain = open(GAIN_FILE).read().strip()
        except OSError:
            gain = ""
        if gain:
            subprocess.run([CTL, "gain", gain])
        log("call audio on: %s%s%s" % (self.port, ", muted" if self.src_mute else "",
                                       ", gain +%s dB" % gain if gain else ""))
        self.session, self.session_port = True, self.port
        self.muted = self.src_mute

    def stop(self):
        subprocess.run([CTL, "off"])
        log("call audio off")
        self.session, self.session_port = False, None
        self.recorded = False

    def evaluate(self):
        if self.eval_timer is not None:
            GLib.source_remove(self.eval_timer)
            self.eval_timer = None
        now = time.monotonic()
        states = sorted(self.calls.values())
        want = any(s in VOICE_STATES for s in states)
        self.hold_sco(self.port == BT_PORT)

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
        if not self.session or self.session_port != self.port:
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
        if self.session:
            self.stop()
        self.hold_sco(False)
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
