# Archive

Files kept for reference. Nothing in the build uses them, and their paths inside are the old ones (they ran from `boot/droidian-init/` and `tools/phone-debug/`).

- `droidian-init/`: the initramfs and helpers of the abandoned Droidian route (`docs/roadmap-04-05.md`). `reboot-bootloader.c` moved to `boot/ut-init/`, because the `trace` and `disk` debug images still build it.
- `phone-debug/`: one-off scripts that installed a fix or a trace on the running phone for a live test, before the fix went into the boot image. Each fix is now in `boot/ut-init/rootfs-overlay`; the roadmap item that names the script says what it tested. The boot image's `init` removes the test files these scripts left behind (its cleanup list).
- `tools/patch-media-hub.py` and `rootfs-overlay/etc/systemd/user/media-hub.service.d/zz-stone-unconfined.conf`: the media-hub workaround for the empty AppArmor label. Kernel `#20` gives sockets AppArmor labels (`docs/roadmap-release.md` item 12), and the stock `media-hub-server` works and runs confined again.
