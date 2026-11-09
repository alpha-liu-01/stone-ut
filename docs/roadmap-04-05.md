# 路线图第 4 项后半和第 5 项

范围是 `docs/feasibility.md` 里第 4 项还没做完的部分，以及第 5 项里「把 Droidian 根文件系统准备好」。目标停在镜像已经放在磁盘上。不格式化 userdata，不刷写，不重启。

手机现在的状态：slot `_b`，crDroid `v12.9-20260416` 已用 2026-11-09 编出的 Halium 配置内核启动到 `sys.boot_completed=1`。`super` 和 userdata 都还没动。

## 要不要刷回 Android 14

这一阶段不刷。

那份 `third_party/crDroidAndroid-14.0-20241212-stone-v10.11.zip` 的指纹是 `POCO/moonstone_p_global`，不是这台 `sunstone_cn`。现在这套 Android 16 vendor 已经能和新内核一起进到桌面，显示 HAL 仍是 HIDL Composer 2.4。先让 Droidian 对这套 vendor 做一次启动试验。只有容器或 libhybris 明确因为 vendor 接口太新而失败时，才把 Android 14 当作下一次试验，并且要单独核对 moonstone 全球版和这台国行机的面板、固件是否一致。

Droidian 101 的通用根文件系统只提供到 api33（Android 13）。没有 api36。`ro.vendor.api_level` 是 31，对应他们文档里的 api32（Android 12/12.1）。本阶段用 api32。api33 留作同一次试验失败后的替换根文件系统，不必为此先刷 ROM。

userdata 可以清空。用户已确认里面没有要保留的内容。但清空仍然是下一阶段的人工测试，不在本篇的执行范围内。清空之后，只写回 `boot_b` 和 `vendor_boot_b` 不够让 Android 回来：还要把 userdata 重新格式化，让 crDroid 重建加密的 f2fs。`super` 里的系统分区保持不动。

## 1. 取得 api32 根文件系统

目标：拿到 Droidian 101 的通用 Phosh 根文件系统，并确认它是一份 ext4 镜像。

### 计划步骤

1. 下载稳定版，不用 nightly：`droidian-OFFICIAL-phosh-phone-rootfs-api32-arm64-101.20261023_20261022.zip`。放到 `third_party/`，不进 git。
2. 列出 zip 内容。早期移植用的是 recovery 包，里面应有 `data/rootfs.img`。
3. 解出 `rootfs.img`，确认文件系统类型和容量。
4. 记下默认解锁口令来自上游说明，是 `1234`。本阶段不启动它，所以还验证不了。

### 实现笔记

2026-11-09 下载稳定版，不用 nightly。文件在 `third_party/droidian-OFFICIAL-phosh-phone-rootfs-api32-arm64-101.20261023_20261022.zip`，1437967579 字节，不进 git。SHA256 `1f3b916d563a63b8e4cff663c4296c6ccfc0fd26f6fc8b125ed7c5fc304f4fd4`。

zip 里有 `data/rootfs.img`（4325376000 字节）、`setup.sh`、`tools/busybox`，以及一个占位的 `updater-script`。解出的镜像在 `third_party/droidian-rootfs/data/rootfs.img`，同样不进 git。`file` 识别为 ext4，UUID `a6af57c5-8efe-4f89-918a-cd7c7b530307`，块大小 4096，块数 1056000。

`/sbin/init` 指向 `../lib/systemd/systemd`。`/vendor` 是指向 `/android/vendor` 的符号链接，目标目录还不存在；`/android` 是空目录。真正的 vendor 挂载点是 `/mnt/vendor`。

默认解锁口令按上游说明是 `1234`。本阶段没有启动，没有验证。

### 事件

- 下载 api32 根文件系统 zip 并计算 SHA256。
- 列出 zip，解出 `data/rootfs.img`。
- 确认为 ext4，并看到 `/sbin/init` 与 vendor 挂载点的实际布局。

## 2. 确认启动链，避免拆掉已经能用的 vendor 挂载

目标：知道 Droidian 的 init 应该放在哪一层 ramdisk，以及 vendor 逻辑分区能不能被一份新的 init 直接挂上。

### 计划步骤

1. 解开当前 `boot_b` 和 `vendor_boot_b` 的 lz4 cpio。
2. 记录 boot ramdisk 里有什么。已知它被 Magisk 改过；换成 Droidian init 后，这次启动路径上不再有 Magisk。备份里的 `boot_b.img` 仍可把 Magisk 启动盘写回去。
3. 记录 vendor ramdisk 里的 first-stage init 和 `fstab.default`。`vendor` 是 `super` 里的逻辑分区，不是独立的 `by-name` 分区。
4. 决定本阶段的 init 只保证挂上 userdata 和 `rootfs.img`。vendor 的 mapper 节点如果在 init 里还不存在，就明确写成已知缺口，不假装已经挂上。

### 实现笔记

解开的是刷入 Halium 内核之前备份下来的那对 ramdisk。正在运行的 `out/halium/` 镜像复用了同一份 ramdisk，所以内容和现在 slot `_b` 上的一致。

boot ramdisk 是 Magisk 改过的 cpio：`.backup/.magisk`、`.backup/init.xz`、`overlay.d/sbin/magisk.xz`，入口是 `init`。换成下面这份 Droidian init 之后，这条启动路径上没有 Magisk。`backups/2026-11-09-crdroid-12.9/boot_b.img` 仍可把 Magisk 启动盘写回去。

vendor ramdisk 里的 `init` 是指向 `/system/bin/init` 的符号链接。`first_stage_ramdisk/fstab.default` 把 `system`、`system_ext`、`product`、`vendor`、`odm` 标成 `logical`、`slotselect`、`first_stage_mount`。它们在 `super` 里，没有 `by-name` 节点。userdata 在这份 fstab 里仍是加密 f2fs：`/dev/block/bootdevice/by-name/userdata`。

本阶段的 init 只挂 userdata 上的 ext4，再 loop 挂载里面的 `rootfs.img`。init 运行时还没有 Android 的 ueventd，也就没有 `/dev/block/mapper/vendor_b`。没有看到这个节点就继续，不假装 vendor 已经挂上。

### 事件

- 解开 boot 与 vendor ramdisk，确认 boot 侧是 Magisk，vendor 侧是第一阶段 init 和 fstab。
- 从 fstab 确认 vendor 是 `super` 里的逻辑分区。
- 把 vendor 挂载留成已知缺口。

## 3. 打出尚未刷入的 boot 和 vendor_boot

目标：用已经验证能启动 Android 的那份 `Image`，配上会去找 `rootfs.img` 的 initramfs。DTB 和 DTBO 索引保持现状。

### 计划步骤

1. 用静态 busybox 做一份 initramfs。init 挂载 proc、sysfs、devtmpfs，等待 `/dev/block/by-name/userdata`，以 ext4 挂载它，再 loop 挂载 `/userdata/rootfs.img`，然后 `switch_root` 到里面的 `/sbin/init`。
2. ramdisk 用 lz4 压缩，和这台机器现有的 boot ramdisk 一样。
3. 用 header v3 打包 `out/halium-droidian/boot.img`。内核仍是 `kernel/build/arch/arm64/boot/Image`。
4. 打包配对的 `vendor_boot.img`：复用现在的 vendor ramdisk 和 DTB，cmdline 在现有参数后加上 `datapart=/dev/block/by-name/userdata`。地址、页大小与已经启动成功的那对镜像相同。
5. 检查魔数、header version，以及两个文件分别小于 128 MiB 和 96 MiB。
6. 不执行 fastboot。

### 实现笔记

init 在 `boot/droidian-init/init`，打包脚本是 `boot/droidian-init/build-boot-images.sh`。busybox 是 Alpine `busybox-static` 1.37.0-r31 的 aarch64 静态二进制，放在 `third_party/busybox-aarch64/busybox`，不进 git。

devtmpfs 不会自己做出 `/dev/block/by-name/userdata`。那个链接要等 Android 的 ueventd。这台机器上 root 读到的 uevent 是 `DEVNAME=sda19`、`PARTNAME=userdata`，所以节点在 `/dev/sda19`。init 改为在 `/sys/class/block/*/uevent` 里找 `PARTNAME=userdata`，再挂这个节点。cmdline 仍按计划加上 `datapart=/dev/block/by-name/userdata`，留给以后的正式 initramfs；这份 busybox init 不读它。

ramdisk 用 `lz4 -l`，魔数 `02 21 4C 18`，和现有 boot ramdisk 的 legacy 帧一致。解包后能看到 `/init` 和 `/bin/busybox`。

`/vendor` 是符号链接，不能当挂载点。init 只在已经存在 `/dev/block/mapper/vendor_b` 时，才尝试把 ext4 挂到根文件系统里现成的 `/mnt/vendor`。这次打包时这个节点不存在。

产物，都没有刷入：

- `out/halium-droidian/boot.img`，49160192 字节，小于 128 MiB。header v3，内核 48402944 字节，OS 16.0.0 / 2026-04。SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`
- `out/halium-droidian/vendor_boot.img`，24264704 字节，小于 96 MiB。header v3，页大小 4096，vendor ramdisk 23817365 字节，DTB 441127 字节，地址与已经启动成功的那对镜像相同。SHA256 `c3d904e5fdcff96fcc8de91f3f1950c6ee3a590fad15397c42475818668554d3`

DTBO 没有重打，`dtbo_idx` 仍是 1。

### 事件

- 取静态 aarch64 busybox，写成 initramfs。
- 用运行中手机的 uevent 确认 userdata 的 `PARTNAME`，init 改为按它找块设备。
- 打出 header v3 的 boot 和 vendor_boot，核对魔数、地址和分区大小。没有执行 fastboot。

## 4. 准备 userdata 内容，但先不写入手机

目标：在主机上放好一份以后可以写入 userdata 的 ext4 镜像，里面已经有 `/rootfs.img`。

### 计划步骤

1. 用第 1 项解出的 `rootfs.img` 做一份稍大的 ext4 镜像，挂载点布局和 initramfs 约定一致：镜像根目录上的文件名是 `rootfs.img`。
2. 镜像只要装得下根文件系统并留出一点余量，不必做成 103 GiB。以后写入分区开头即可，ext4 超级块自己记录大小。
3. 计算 SHA256，把路径写进笔记。
4. 不运行 `fastboot format`，不运行 `fastboot flash userdata`。

### 实现笔记

`out/halium-droidian/userdata.img`，5033164800 字节（4800 MiB），ext4，卷标 `userdata`，UUID `d39d4bb1-41fc-47de-8e68-550de0443df1`。根目录只有 `lost+found` 和 `rootfs.img`。这个 `rootfs.img` 是 4325376000 字节，和 zip 里的那份一样大。SHA256 `66e0a5cfe61e03ccc81921b78a7251501d948b059916eff94fa82ffe55e7113d`。

它比手机上的 userdata 小得多。写入分区开头即可，ext4 超级块记录的是这 4800 MiB。镜像准备好时没有刷入；用户确认 userdata 没有要留的内容并进入 fastboot 之后，才写入手机。见下一节。

### 事件

- 用 `mke2fs -d` 把 `rootfs.img` 放进一份 4800 MiB 的 ext4。
- 用 debugfs 确认根目录文件名是 `rootfs.img`。
- 计算 SHA256。没有写入手机。

## 5. 写入 slot B 并重启

用户确认 userdata 可以清空，并且手机已经停在 fastboot。只写 boot、vendor_boot 和 userdata。不写 dtbo、vbmeta、`super`。

### 实现笔记

2026-11-09 写入前 `current-slot` 是 `b`，`unlocked: yes`。顺序是先 `userdata`，成功后再写 `boot_b` 和 `vendor_boot_b`，这样 userdata 失败时原来的 Android 启动盘还在。

`fastboot flash userdata` 先报 `Invalid sparse file format at header magic`，随后把这份 raw ext4 分成 5 段发出，每段 Writing 都是 OKAY，总时间 91.7 秒。`boot_b` 和 `vendor_boot_b` 也是 OKAY。写完后槽位仍是 `b`。然后 `fastboot reboot`。

主机内核日志里，手机在 11:15:48 从 fastboot（`18d1:d00d`）断开。之后没有再枚举。用户看到开机第一屏之后 Droidian logo 亮了约一秒，然后 OLED 全黑，无法从屏幕判断背光。用户手动回到了 fastboot。logo 能画出来，说明 init 已经挂上 userdata、loop 挂上 `rootfs.img` 并 `switch_root` 进了根文件系统，Plymouth 跑过。黑屏发生在这之后。

fastboot 本身读不走这次启动的日志。分区表里有 `logdump`（64 MiB）和 `minidump`，这个 bootloader 没有可用的 `fetch`。为了不把 userdata 交给会按 f2fs 处理它的 Android recovery，另外打了 `out/halium-droidian/boot-logs.img`：只读挂载根文件系统，收集 pstore、journal 和 `logdump` 的字符串，再用内核里已有的 USB ACM 串口送出来。还没写入。读取 `fastboot getvar all` 时主机提前关掉了管道，bootloader 随后不再回答命令，需要手动重新进入 fastboot 才能刷这份日志镜像。

回滚仍然是：进 fastboot，写回 `backups/2026-11-09-crdroid-12.9/boot_b.img` 和 `vendor_boot_b.img`，再让 Android 把 userdata 格式化成加密 f2fs。`super` 不动。

### 事件

- 确认槽位 `_b`、已解锁。
- 写入 `userdata`、`boot_b`、`vendor_boot_b`，fastboot 均返回 OKAY。
- 重启。主机侧 USB 断开后没有再枚举。
- 用户看到 Droidian logo 约一秒后黑屏，并手动回到 fastboot。
- 打出尚未写入的 `boot-logs.img`。bootloader 在被截断的 `getvar all` 之后不再响应。
- 用户重新进入 fastboot。其间系统又启动过一次。只写入 `boot_b` 的 `boot-logs.img`，槽位仍是 `_b`。主机看到 USB 设备 `0525:a4a7`，产品名 `boot-log`。串口内容里 pstore 为空，`rootfs.img` 因为只读挂载无法回放日志，`journalctl` 没有跑成。这份启动不进 Droidian，所以没有 logo。
- 改用 `boot-disk.img` 把 userdata 只读导出成 U 盘 `/dev/sdb`。读写挂载后 `journalctl` 的结果是 `No journal files were found`。根文件系统里 `/usr/lib/systemd/journald.conf.d/10-journald-volatile.conf` 把 `Storage` 设成 `volatile`，上次启动的日志只在内存里，重启后没有了。
- 已准备 `boot-patch.img`。用户回到 fastboot 后写入。约 13 秒后手机自己回到 fastboot，中途没有出现 USB 网卡或 U 盘，和补丁写完就重启进 bootloader 的路径一致。随后写回能进 Droidian 的 `boot.img` 并重启。槽位仍是 `_b`。
- 这次启动画出 logo 约一秒。用户等了将近一分钟后回到 fastboot。用 `boot-disk.img` 导出 userdata。journal 已落盘。`android-mount` 失败：`/vendor` 是指向不存在的 `/android/vendor` 的符号链接，`parse-android-dynparts` 只读 metadata slot 0，映射出的是 `dynpart-vendor_a` 而不是 slot `_b` 的 vendor。LXC android 和 Phosh 都因这个依赖失败。新的 `boot-patch.img` 会创建 `/android/*` 目录，并把 dynparts 的槽位改成 1。
- 补丁 boot 已写入 `boot_b`，约 12 秒后自己回到 fastboot。随后写回 Droidian `boot.img`（SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`）并重启。槽位仍是 `_b`。userdata、vendor_boot、dtbo、vbmeta、super 没有动。
- 再次黑屏后用 `boot-disk.img` 读出 journal。dynparts 槽位补丁生效：`dynpart-vendor_b` 已挂上，`/vendor/build.prop` 通过。`android-rootfs.img`（Halium arm64，SDK 32）也挂到了容器根。`android-mount` 仍失败，因为 `ExecStartPost` 要绑定 `/android/system/lib64/libselinux_stubs.so`，这个路径是空目录，真正的库在容器根的 `/system/lib64`。LXC 配置还要求绑定不存在的 `/android/data`，并且 `lxc.arch` 写成了 `armhf`，而 `/system/bin/init` 是 aarch64。新的 `boot-patch.img`（SHA256 `95f3b9017c96f2109a88d04824bb56acff0e170c7efbd923ed35b83e352fecb8`）补这三处。
- 这份补丁已写入 `boot_b`，约 12 秒后自己回到 fastboot。随后写回 Droidian `boot.img` 并重启。槽位仍是 `_b`。
- 再次黑屏。`android-mount` 成功，LXC android 进入 running，主机名变成 RedmiNote125G，Phosh 也启动了。`linkerconfig` 在 early-init 因 `SANITIZER_DEFAULT_VENDOR is not defined` 收到 signal 6，没有生成 linker namespace。`vndservicemanager` 和 `vendor.qti.hardware.display.composer` 都以状态 1 退出，composer 的 onrestart 还找不到 surfaceflinger。新的 `boot-patch.img`（SHA256 `7bec092b186f197aa1f110d23f516683eab5e0a6986e8431860a3e378e496605`）把 linkerconfig 换成写宽松 `ld.config.txt` 的脚本，并让 `logcat` 落到 `/var/log/stone-logcat.txt`。
- 这份补丁已写入 `boot_b`，约 12 秒后自己回到 fastboot。随后写回 Droidian `boot.img` 并重启。槽位仍是 `_b`。
- 再次黑屏。替换后的 `linkerconfig` 以状态 0 退出，不再报 `SANITIZER_DEFAULT_VENDOR`。`vndservicemanager` 仍在约 50 毫秒后以状态 1 退出。容器 `/dev` 是新的 tmpfs，`vndbinder` 不在里面。这次 journal 在重写时被重启截断，`logcat` 文件是空的。新的 `boot-patch.img`（SHA256 `6ec50e4daa21aee689d7e3aea5cd0b51f792ee87e794fe28a15518f5bda1b230`）在容器里创建 `binder`、`hwbinder`、`vndbinder`，并把这两个 HAL 的 stderr 送到内核日志。
- 这份补丁已写入 `boot_b`，约 12 秒后自己回到 fastboot。随后写回 Droidian `boot.img` 并重启。槽位仍是 `_b`。
- logo 这次大约 3 秒。`binder`、`hwbinder`、`vndbinder` 已经存在。`vndservicemanager` 被包到 `/vendor_real/bin` 后，链接器没有把它算进 vendor namespace，加载了 Halium 的旧 `libc++`，缺少 `std::stringstream` 的 vtable。新的 `boot-patch.img`（SHA256 `62ca25ccdf8a668efbe00fb375a5fe915bd84165e7f228d59e857f06632c11ee`）把 `/vendor_real/bin` 放进 vendor namespace。
- 这份补丁已写入 `boot_b`，约 12 秒后自己回到 fastboot。随后写回 Droidian `boot.img` 并重启。槽位仍是 `_b`。
- logo 仍然约 3 秒。`ld.config` 里已经有 `/vendor_real/bin`，`vndservicemanager` 和 `vendor.qti.hardware.display.composer-service` 都被包上了。根文件系统 3.9G 已用满，这次启动的 `dmesg` 只写下开头 16KB（内核时间 0.4 秒），`journal` 和 `logcat` 是空的，所以看不到新的链接错误。Halium 的 `/system/lib64/libc++.so` 没有 `std::stringstream` 的 vtable；同一份 vendor ramdisk 里的 `libc++.so`（NDK r28）有这个符号。新的 `boot-patch.img`（SHA256 `d661ccad0d9de5eee6cb25ceaf30dd11a1eafcaa06a2c547d9e81a129f6f2bc6`）清掉 apt 缓存和旧 journal 腾出空间，把带该符号的 `libc++` 放到 `/vendor_real/lib64` 并排在 vendor namespace 搜索路径最前，同时先把链接结果写进小文件。
- 这份补丁已写入 `boot_b`。补丁启动离开 fastboot 约 15 秒后自己回到 fastboot。随后写回 Droidian `boot.img`（SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`）并重启。槽位仍是 `_b`。userdata、vendor_boot、dtbo、vbmeta、super 没有动。
- logo 这次大约 1 秒。vendor 的 `libc++` 含有 `stringstream`，已经放到 `/vendor_real/lib64`。新的链接错误是 `libapexsupport.so` 找不到，`/vendor/lib64/libbinder.so` 需要它，Halium 12 没有这个库。`vndservicemanager` 因此仍以状态 1 退出。新的 `boot-patch.img`（SHA256 `6379cb98bc64f65be69da4d2f1fb64b9ccc36bfec9e695d1d31dd23f934f3382`）放入只导出四个 `AApexInfo_*` 符号、并对非 APEX 进程返回 `AAPEXINFO_NO_APEX` 的 `libapexsupport.so`。
- 这份补丁已写入 `boot_b`。补丁启动离开 fastboot 约 14 秒后自己回到 fastboot。随后写回 Droidian `boot.img`（SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`）并重启。槽位仍是 `_b`。userdata、vendor_boot、dtbo、vbmeta、super 没有动。
- logo 仍然约 1 秒。`libapexsupport.so` 已放进 `/vendor_real/lib64` 和 `/system/lib64`。容器没有跑起来：`lxc-start` 收到 `ABORTING`。包装脚本在容器启动前把 `ld.config.txt` 写进了镜像里的 `/linkerconfig`。`/init` 不匹配任何 `dir.*`，链接器要找不存在的 `[default]` 段，init 起不来。新的 `boot-patch.img`（SHA256 `7278da93c54ea3fefcbe178efedde0bde6b08f67e5afed5d669840d1c151a653`）删掉这个文件，补上 `[default]`，并不再提前写入。
- 这份补丁已写入 `boot_b`。补丁启动离开 fastboot 约 14 秒后自己回到 fastboot。随后写回 Droidian `boot.img`（SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`）并重启。槽位仍是 `_b`。userdata、vendor_boot、dtbo、vbmeta、super 没有动。
- logo 大约 2 秒。`/linkerconfig/ld.config.txt` 已经删掉，容器仍然是 `ABORTING`，`lxc-android.log` 是空的，因为 `lxc-start -d` 把真正的错误留在了已经脱离的进程里。新的 `boot-patch.img`（SHA256 `0f1491344aff6dbbbd886cec94bcaf7310448d98ab06ad6cd5a6de9b8f8ce341`）改成前台启动并把 stderr 落到 `/var/log/lxc-foreground.log`，同时把 `libapexsupport.so` 从 `/system/lib64` 挪走，只留给 vendor 进程。
- 这份补丁已写入 `boot_b`。补丁启动离开 fastboot 约 14 秒后自己回到 fastboot。随后写回 Droidian `boot.img`（SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`）并重启。槽位仍是 `_b`。userdata、vendor_boot、dtbo、vbmeta、super 没有动。
- logo 仍约 2 秒。前台 LXC 日志只有 `lxc.seccomp` 不支持的重复警告，没有新信息。
- 换方向。黑屏的直接原因是：logo 由 Plymouth 通过内核 DRM（`msm_drm`，1080x2400@120）画出，内核没有 `DRM_FBDEV_EMULATION`，也没有 fbcon，Plymouth 退出后只要 phosh 没起来屏幕就是黑的。phosh 被 Droidian 的 `20-wlroots-hwc-env.conf` 和 `40-droid-wait.conf` 绑在 Android hwcomposer 上，而 hwcomposer 需要 Halium 12 system 跑 Android 16 vendor 的 HAL。Treble 只保证 system 不比 vendor 旧，这个组合缺的是整代 LLNDK（`libapexsupport`、新 `libc++`、VINTF manifest 9.0 等），逐个补库不是可收敛的路。
- 新路径与 Mobian 类似：不经过 Android，直接在内核 DRM 上跑 phoc。rootfs 自带的 `libwlroots.so.12a` 有 DRM 后端和 pixman 渲染器，`phosh-session` 默认就是 `WLR_BACKENDS=drm,libinput`，GL 走 glvnd，可以选 Mesa。新的 `boot-patch.img`（SHA256 `9679deaf2f5b9b7403d1dafb6b1ea08eaf8d5b1576df68c1be811e96da23fbba`）屏蔽上面两个 drop-in，phoc 用 pixman，客户端用 Mesa 软件渲染和 `GSK_RENDERER=cairo`，清掉 hybris 的 `LD_PRELOAD`，`DSI-1` 缩放 3。每次 phosh 重启在 legacy KMS（Plymouth 用的接口）和 atomic 之间切换。`lxc@android` 和 `android-service@hwcomposer` 被屏蔽，原单元留在 `lxc@android.service.stone-orig`。`android-mount` 仍由 `local-fs.target` 拉起，vendor 固件照常挂载。rootfs 已经 100% 满，ext4 的 5% 保留块只给 root，phosh 用户写不了家目录；补丁删除 `en`、`zh` 以外的翻译和 `/usr/share/doc`，并把 journal 限制在 48M。
- 这份补丁已写入 `boot_b`。补丁启动离开 fastboot 约 16 秒后自己回到 fastboot（比之前多约 2 秒，删除文件需要时间）。随后写回 Droidian `boot.img`（SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`）并重启。槽位仍是 `_b`。userdata、vendor_boot、dtbo、vbmeta、super 没有动。
- logo 约 1～2 秒后黑屏。rootfs 已有 211M 可用。journal 里完全没有 phosh：`phosh.service` 本身没有 `[Install]` 链接，Droidian 只靠 `android-service@hwcomposer.service.d/20-phosh.conf` 的 `BindsTo=phosh.service` 把它拉起来。屏蔽 hwcomposer 后 phosh 不在启动事务里，只剩看不见的 tty1 getty，6.6 秒 Plymouth 退出时显示被 blank。另外后面的 `sed -i` 把 `lxc@android.service` 的 `/dev/null` 链接改成了空文件。新的 `boot-patch.img`（SHA256 `17cc592ed19f1f1b49e42eabfed99159f1596c1a2333b1047cd06f43fc648c15`）把 phosh 加进 `graphical.target.wants`，sed 改到 `.stone-orig` 上。这次失败与 Android 14 ROM 无关。
- 这份补丁已写入 `boot_b`。补丁启动约 11 秒后自己回到 fastboot。随后写回 Droidian `boot.img`（SHA256 `5c9ede670be9391469784978ebebf9bf37325a5db0809bd02abe5e132577db18`）并重启。
- **第一次进入 phosh 桌面。** 显示走内核 DRM，phoc 用 pixman 软件渲染，没有 Android 容器，触摸可用（能解锁进桌面）。补丁改的是 userdata 里的 rootfs，以后正常启动会保留这些改动。手机此时在 USB 上没有任何设备出现：Droidian rootfs 里没有 sshd，也没有配置 USB 网络。内核有 `CONFIG_USB_CONFIGFS_NCM=y`，可以做 USB 网络。
- Wi-Fi 不可用，改走 USB 网络加 SSH。新的 `boot-patch.img`（SHA256 `786b9b82b756f7f8310d783705c15bac8b12e20ad317a4946450a8e6284bbad0`）在补丁启动里用 chroot + `dpkg` 离线装 trixie 的 `openssh-server` 及缺的 10 个依赖（deb 和 SHA256 校验放在 `out/halium-droidian/debs/`）。主机密钥在电脑上生成，免得手机早期启动等熵。只允许密钥登录 root 和 `droidian`，私钥在 `out/halium-droidian/ssh/`。`stone-usbnet.service` 用 configfs 建 NCM gadget：手机 `10.15.19.82`，电脑侧 MAC `02:00:5e:10:15:19`；手机的 NetworkManager 不接管这个接口。电脑上加了 NetworkManager 连接 `stone-usb`，按 MAC 匹配，静态 `10.15.19.100/24`，不设默认路由。
- 这份补丁已写入 `boot_b`，约 14 秒后回到 fastboot，`dpkg` 安装成功。写回 Droidian `boot.img` 后约 10 秒电脑上出现 `enx02005e101519`，可以 `ssh root@10.15.19.82` 登录（主机密钥与预先生成的一致）。辅助脚本 `out/halium-droidian/ssh/phone`。当前状态：phosh 运行中；rootfs 剩 190M；电池读数正常（`battery` 100%、Full）；`/dev/kgsl-3d0` 和 `/dev/dri/renderD128` 都在，可以尝试 Mesa 的 KGSL 硬件加速；没有 `wlan0`（WLAN 驱动未加载）。失败的单元只有 `droidian-fpd`、`lxc-net`、`nfcd`、`ofono`，都依赖 Android 容器。
- 决定改走 Halium 14。vendor 用已核对可装到 sunstone 的 crDroid 14 包，系统镜像用 UBports 的 Halium 14，根文件系统用 Ubuntu Touch 24.04-2.x。Droidian 没有 api34 发布文件。新路线图是 `docs/roadmap-halium14.md`。这篇在手机上的 Phosh 试验停在这里。
