#!/bin/sh
# Live install of the display fixes and the refresh rate setting without a
# flash (needs root). The boot image installs the same files from
# boot/ut-init/rootfs-overlay.
#
#   sudo sh /home/phablet/stone-display-install.sh
# Applies them at once (the System Settings page included): no reboot needed
# unless the compositor fix itself is not active yet.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
S=/home/phablet/stone-display
install -m 755 $S/display-setup.sh /usr/lib/stone/display-setup.sh
install -m 755 $S/display-mode.py /usr/lib/stone/display-mode.py
install -m 755 $S/refresh-rate-request.sh /usr/lib/stone/refresh-rate-request.sh
install -m 755 $S/stone-refresh-rate /usr/bin/stone-refresh-rate
install -d -m 755 /usr/share/stone/settings
install -m 644 $S/RefreshRate.qml $S/refresh_rate.py $S/brightness-PageComponent.qml /usr/share/stone/settings/
install -m 644 $S/stone-refresh-rate.conf /usr/lib/tmpfiles.d/stone-refresh-rate.conf
for u in stone-display-setup.service stone-refresh-rate.path stone-refresh-rate-request.service; do
    install -m 644 $S/$u /etc/systemd/system/$u
done
systemctl daemon-reload
systemd-tmpfiles --create /usr/lib/tmpfiles.d/stone-refresh-rate.conf
systemctl enable stone-display-setup.service
systemctl enable --now stone-refresh-rate.path
# Re-run the setup: steps already done are skipped; adds the Settings page.
sh /usr/lib/stone/display-setup.sh
ls -ld /run/stone-refresh-rate
systemctl is-active stone-refresh-rate.path
echo "installed; open System Settings > Brightness (close it first if it was open)"
