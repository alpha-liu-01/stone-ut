# Installing Ubuntu Touch on stone

This replaces Android on the phone and **erases all data on it**. Tested on a Redmi Note 12 5G `sunstone_cn`; other variants are untested (see the README).

## You need

- An unlocked bootloader (Xiaomi's unlock procedure).
- `adb` and `fastboot` (Android platform-tools) on a computer.
- The two images from `sh build.sh` (see the README): `out/halium14/boot-ut.img` and `out/halium14/userdata-ut.img`.
- The crDroid 14.0 v10.11 zip (`crDroidAndroid-14.0-20241212-stone-v10.11.zip`, fetched by `tools/fetch-inputs.sh` into `third_party/`), and crDroid's recovery for it from `https://sourceforge.net/projects/crdroid/files/stone/10.x/recovery/`.

## 1. Install crDroid 14

Ubuntu Touch keeps crDroid 14's `vendor` and `odm` partitions and its device tree (`vendor_boot`, `dtbo`), and replaces only `boot` and userdata. Install it with crDroid's own steps ([crdroid.net/stone/10/install](https://crdroid.net/stone/10/install)):

1. Make sure the phone runs the latest regional HyperOS firmware. crDroid requires it; the zip carries no modem or bootloader firmware.
2. In fastboot (Volume Down + Power): `fastboot flash boot <crDroid recovery boot.img>`.
3. Boot into that recovery, choose "Format data", then `adb sideload crDroidAndroid-14.0-20241212-stone-v10.11.zip`.
4. Reboot once into crDroid, check that it starts, then turn the phone off.

Use exactly v10.11. The port's vendor workarounds were made against it.

## 2. Install Ubuntu Touch

Put the phone into fastboot (Volume Down + Power), then:

```sh
fastboot getvar current-slot          # crDroid's slot; the commands below write to it
fastboot flash userdata out/halium14/userdata-ut.img
fastboot flash boot out/halium14/boot-ut.img
fastboot reboot
```

- The userdata image is a raw 8 GiB ext4 image. fastboot first says "Invalid sparse file format at header magic", then sends it in chunks; that is expected. It takes about 1.5 minutes.
- Do not flash `vendor_boot`, `dtbo`, `vbmeta` or the logical partitions: they stay crDroid 14's.

The first boot takes longer than later ones. Go through the welcome wizard; the passcode you set is also `phablet`'s password for `sudo`.

## 3. Use the whole userdata partition

The root filesystem image is 8 GiB; grow it to the partition once:

1. Settings → About → Developer mode: turn it on (it needs a passcode), and connect USB.
2. Run:

   ```sh
   adb shell
   sudo resize2fs "$(findmnt -no SOURCE /)"
   df -h /
   ```

It grows while mounted; `df` then shows the full size (about 100 GB on the 128 GB model).

## Updating

To install a newer build, flash only the boot image: `fastboot flash boot out/halium14/boot-ut.img`. The overlay in it is copied into the root filesystem on the next boot. Flashing `userdata-ut.img` again erases everything.

## Recovery

Volume Up + Power (or `sudo reboot recovery`) starts UBports' recovery, which is part of the boot image. It gives a root `adb shell` and fastbootd ("Enter fastboot"). "Factory reset" is disabled on purpose: userdata *is* the Ubuntu Touch system here, so a format would erase the OS. To reach your files from the recovery:

```sh
adb shell
mkdir -p /mnt/ut && mount -o ro -t ext4 /dev/block/by-name/userdata /mnt/ut
```

## Back to Android

Install crDroid again with step 1 ("Format data" replaces the Ubuntu Touch filesystem).
