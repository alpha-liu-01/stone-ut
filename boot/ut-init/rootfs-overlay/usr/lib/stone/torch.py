#!/usr/bin/python3
"""Flashlight for the battery indicator's toggle (docs/roadmap-hardware-2.md,
flashlight).

The flash is an I2C LED driver on the camera control bus (qcom,camera-flash),
driven only by the camera stack: there is no LED class device for
ayatana-indicator-power's sysfs backend, and its camera-hal backend speaks
the AIDL camera provider, while this vendor only has the HIDL one
(android.hardware.camera.provider@2.4::ICameraProvider/legacy/0).

So the indicator's "simple" backend writes "1"/"0" into
/run/stone-torch/torch (deviceinfo FlashlightSysfsPath, stone.yaml), and this
service watches that file and calls ICameraDevice@3.2::setTorchMode() on the
first camera that accepts it, as Android's torch tile does through
CameraService. The provider refuses while a camera is open (CAMERA_IN_USE);
that is logged.
"""
import ctypes
import os
import signal
import struct
import sys

import gbinder

DIR = "/run/stone-torch"
NAME = "torch"
PROVIDER = "android.hardware.camera.provider@2.4::ICameraProvider"
INSTANCE = PROVIDER + "/legacy/0"
DEVICE = "android.hardware.camera.device@3.2::ICameraDevice"
TX_GET_CAMERA_ID_LIST = 3            # ICameraProvider@2.4
TX_GET_DEVICE_V3 = 6                 # getCameraDeviceInterface_V3_x
TX_SET_TORCH_MODE = 3                # ICameraDevice@3.2
STATUS = {0: "OK", 1: "ILLEGAL_ARGUMENT", 2: "CAMERA_IN_USE",
          3: "MAX_CAMERAS_IN_USE", 4: "METHOD_NOT_SUPPORTED",
          5: "OPERATION_NOT_SUPPORTED", 6: "CAMERA_DISCONNECTED",
          7: "INTERNAL_ERROR"}

IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080
libc = ctypes.CDLL(None, use_errno=True)


def log(msg):
    print(f"stone-torch: {msg}", flush=True)


def val(result):
    ok, v = result
    if not ok:
        raise RuntimeError("short binder reply")
    return v


class Torch:
    def __init__(self):
        self.sm = gbinder.ServiceManager("/dev/hwbinder")
        self.device = None          # (name, client) that accepted the torch

    def _provider(self):
        remote, status = self.sm.get_service_sync(INSTANCE)
        if remote is None:
            raise RuntimeError(f"{INSTANCE} not registered (status {status})")
        return gbinder.Client(remote, PROVIDER)

    def _status(self, reply):
        r = reply.init_reader()
        hidl = val(r.read_int32())
        if hidl:
            raise RuntimeError(f"HIDL transport status {hidl}")
        return r, val(r.read_uint32())

    def _devices(self, provider):
        reply, status = provider.transact_sync_reply(TX_GET_CAMERA_ID_LIST,
                                                     provider.new_request())
        if reply is None:
            raise RuntimeError(f"getCameraIdList failed: {status}")
        r, st = self._status(reply)
        if st:
            raise RuntimeError(f"getCameraIdList: {STATUS.get(st, st)}")
        # read_hidl_string_vec() returns the list itself, not (ok, value).
        names = r.read_hidl_string_vec()
        if not isinstance(names, list):
            raise RuntimeError("getCameraIdList: unreadable reply")
        for name in names:
            req = provider.new_request()
            req.append_hidl_string(name)
            reply, status = provider.transact_sync_reply(TX_GET_DEVICE_V3, req)
            if reply is None:
                continue
            r, st = self._status(reply)
            if st:
                log(f"{name}: getCameraDeviceInterface: {STATUS.get(st, st)}")
                continue
            yield name, gbinder.Client(r.read_object(), DEVICE)

    def _set(self, client, on):
        req = client.new_request()
        req.append_int32(1 if on else 0)     # TorchMode: OFF = 0, ON = 1
        reply, status = client.transact_sync_reply(TX_SET_TORCH_MODE, req)
        if reply is None:
            raise RuntimeError(f"setTorchMode failed: {status}")
        return self._status(reply)[1]

    def set(self, on):
        for attempt in (1, 2):               # retry once with a fresh provider
            try:
                if self.device is not None:
                    st = self._set(self.device[1], on)
                    log(f"{'on' if on else 'off'} ({self.device[0]}): {STATUS.get(st, st)}")
                    return st == 0
                for name, client in self._devices(self._provider()):
                    st = self._set(client, on)
                    if st == 0:
                        self.device = (name, client)
                        log(f"{'on' if on else 'off'} ({name}): OK")
                        return True
                    if st == 2:              # CAMERA_IN_USE: do not try others
                        log(f"{name}: {STATUS[st]}; close the camera first")
                        return False
                    log(f"{name}: setTorchMode: {STATUS.get(st, st)}")
                log("no camera accepted setTorchMode")
                return False
            except (RuntimeError, OSError) as e:
                log(f"attempt {attempt}: {e}")
                self.device = None
        return False


def main():
    os.makedirs(DIR, exist_ok=True)
    path = os.path.join(DIR, NAME)
    if not os.path.exists(path):
        # The unit creates it with the right owner; this is for manual runs.
        open(path, "w").close()
    torch = Torch()

    fd = libc.inotify_init1(0)
    if fd < 0 or libc.inotify_add_watch(fd, DIR.encode(),
                                        IN_CLOSE_WRITE | IN_MOVED_TO) < 0:
        log(f"inotify: {os.strerror(ctypes.get_errno())}")
        return 1

    def stop(signum, frame):
        torch.set(False)
        sys.exit(0)
    signal.signal(signal.SIGTERM, stop)

    log(f"watching {path}")
    while True:
        buf = os.read(fd, 4096)
        i, names = 0, set()
        while i < len(buf):
            _wd, _mask, _cookie, length = struct.unpack_from("iIII", buf, i)
            names.add(buf[i + 16:i + 16 + length].rstrip(b"\0").decode(errors="replace"))
            i += 16 + length
        if NAME not in names:
            continue
        try:
            with open(path) as f:
                value = f.read().strip()
        except OSError:
            continue
        if value in ("0", "1"):
            torch.set(value == "1")


if __name__ == "__main__":
    sys.exit(main())
