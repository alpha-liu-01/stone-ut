#!/bin/sh
# Live test of the flashlight toggle (docs/roadmap-hardware-2.md, flashlight).
# Run with sudo:  sudo sh /home/phablet/stone-torch-install.sh
# Installs torch.py, starts it as a runtime-only unit (/run/systemd/system,
# gone after a reboot), puts the deviceinfo keys into stone.yaml (the image
# restores its own copy at the next boot) and restarts the battery indicator.
set -eu
trap '' HUP
T=/home/phablet/torch-test
install -m 644 $T/torch.py /usr/lib/stone/torch.py
install -m 644 $T/stone-torch.service /run/systemd/system/stone-torch.service
install -m 644 $T/stone.yaml /etc/deviceinfo/devices/stone.yaml
systemctl daemon-reload
systemctl restart stone-torch.service
sleep 1
systemctl --no-pager --lines=5 status stone-torch.service | tail -6
ls -l /run/stone-torch/torch
device-info get FlashlightSysfsPath
setpriv --reuid=32011 --regid=32011 --init-groups -- env XDG_RUNTIME_DIR=/run/user/32011 \
    systemctl --user restart ayatana-indicator-power.service
echo "battery indicator restarted"
echo "stone-torch-install: done; Ctrl+C is safe now" > /dev/tty 2>/dev/null || true
