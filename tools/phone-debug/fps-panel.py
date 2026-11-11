#!/usr/bin/env python3
"""What the panel is really doing (no root needed; the screen must be on).

  python3 fps-panel.py [SECONDS]      (default 20)

Two sources from the Qualcomm SDE display driver:
  /sys/class/drm/sde-crtc-0/vsync_event   VSYNC=<ns timestamp>, updated and
      sysfs_notify()'d on every vsync while vsync is enabled (Mir enables it
      while it composites). The spacing of consecutive timestamps is the
      panel's real refresh period: 8.33 ms at 120 Hz, 16.67 ms at 60 Hz.
  /sys/class/drm/sde-crtc-0/measured_fps  frames actually committed to the
      panel in the last fps_periodicity_ms (1 s): the rate at which the
      system compositor puts new frames on screen.
Plus GPU load/clock (kgsl) and CPU cluster clocks, sampled once a second.
Prints one line per second, then a summary.
"""
import os
import select
import sys
import time

CRTC = "/sys/class/drm/sde-crtc-0/"
KGSL = "/sys/class/kgsl/kgsl-3d0/"
CPUFREQ = "/sys/devices/system/cpu/cpufreq/"


def clocks():
    """GPU busy % and clock, CPU clock per cluster (MHz)."""
    out = []
    try:
        out.append("gpu %3s%% %3d MHz" % (read(KGSL + "gpu_busy_percentage").split()[0],
                                         int(read(KGSL + "gpuclk")) // 1000000))
    except OSError:
        pass
    for pol in sorted(os.listdir(CPUFREQ)):
        try:
            out.append("%s %4d" % (pol.replace("policy", "cpu"),
                                   int(read(CPUFREQ + pol + "/scaling_cur_freq")) // 1000))
        except OSError:
            pass
    return " ".join(out)


def read(path):
    with open(path) as f:
        return f.read().strip()


def main():
    secs = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    print("dpms: %s; modes: %s" % (read("/sys/class/drm/card0-DSI-1/dpms"),
          " ".join(read("/sys/class/drm/card0-DSI-1/modes").split())))
    fd = os.open(CRTC + "vsync_event", os.O_RDONLY)
    poll = select.poll()
    poll.register(fd, select.POLLPRI | select.POLLERR)
    os.read(fd, 64)
    last_ts, periods, all_periods, fps_vals = None, [], [], []
    end = time.monotonic() + secs
    next_report = time.monotonic() + 1
    while time.monotonic() < end:
        timeout = max(0, next_report - time.monotonic())
        if poll.poll(timeout * 1000):
            os.lseek(fd, 0, 0)
            raw = os.read(fd, 64).decode().strip()
            try:
                ts = int(raw.split("=")[1])
            except (IndexError, ValueError):
                ts = None
            if ts and last_ts and ts > last_ts:
                periods.append((ts - last_ts) / 1e6)
            last_ts = ts or last_ts
        if time.monotonic() >= next_report:
            next_report += 1
            fps = read(CRTC + "measured_fps")
            fps_vals.append(float(fps.split()[1]))
            if periods:
                p = sorted(periods)
                med = p[len(p) // 2]
                vs = "vsyncs %3d median %.2f ms" % (len(p), med)
            else:
                vs = "vsyncs   0  (vsync off: nothing being composited)"
            print("%s | %s | %s" % (fps, vs, clocks()), flush=True)
            all_periods += periods
            periods = []
    print("== summary")
    if all_periods:
        p = sorted(all_periods)
        print("vsync period median %.2f ms (%.1f Hz), %d vsync events" % (
            p[len(p) // 2], 1000 / p[len(p) // 2], len(p)))
    if fps_vals:
        print("committed frames/s: max %.1f, mean %.1f" % (max(fps_vals), sum(fps_vals) / len(fps_vals)))


if __name__ == "__main__":
    main()
