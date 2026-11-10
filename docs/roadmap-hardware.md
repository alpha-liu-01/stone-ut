# 硬件：显示已经起来之后

`docs/roadmap-halium14.md` 的目标已经达到。2026-11-09 用户确认 Ubuntu Touch 进入 Lomiri，显示、触摸、GPU、亮度、充电感应和振动都正常。这一篇只修还没通的硬件。不重刷 `vendor_boot`、`dtbo`、`vbmeta`、`super`。`boot_b` 现在是正常的 `boot-ut.img`（内核 `#7`），没有免密 sudo，也不会自己回 fastboot。

`/etc/os-release` 是 Ubuntu 24.04.5 LTS。根文件系统来自 24.04-2.x 渠道的 `ubuntu-touch-android9plus-rootfs-arm64.tar.gz`。adb 已通，序列号 `stone`。手机时钟仍是 1970 年，Wi-Fi 能关联之后如果证书校验失败，先对时。

## 已经确认可用

- 显示、触摸（`fts_ts`）、GPU 加速、界面流畅、亮度调节。
- 充电：`/sys/class/power_supply/battery/status` 为 `Charging`。用户确认能识别到正在充电。
- 振动：`/sys/class/leds/vibrator` 存在，用户确认可用。
- adb。

## 修复顺序

1. 存储扩容。原因已经明确，而且剩下的空闲只有约 4G，后面编内核、抓日志都会写 userdata。
2. 用这棵内核重编 vendor 模块。Wi-Fi、声音、蓝牙、相机的 `.ko` 都是 `5.4.259-qgki`，加载不进 `5.4.283~positron`。`lsmod` 是空的。这一项不过，后面四项都会停在驱动没起来。
3. 声音。PulseAudio 只有一个假的 SCO sink，用户听到的是完全没有声音。
4. Wi-Fi。Android 的 wifi HAL 已经在跑，缺的是 `wlan0`。
5. SIM。ofono 一个 modem 都没有，和上面的 `.ko` 不是同一条线，所以排在驱动之后单独查。
6. 蓝牙。`/dev/vhci` 不存在，bluebinder 在重启循环里。打开 `CONFIG_BT_HCIVHCI` 并进第 2 项同一次内核构建，验证留在这一项。
7. 相机。节点在，应用一开就退。放在最后，因为显示栈已经通，崩溃更可能是 `camera.ko` 和 HAL。

## 1. 存储扩容

目标：根文件系统用满 `sda19`，设置里的内置存储接近 128GB 这部机器的 userdata，而不是现在的大约 10GB。

现象：整盘 `sda` 113.1G，`sda19`（卷标 userdata，挂在 `/`）103.5G。`df -h /` 只有 7.7G，已用 3.4G，可用 4.0G。设置里显示约 9.9GB。`out/halium14/userdata-ut.img` 按 8GiB 做的，刷进去只覆盖分区开头，没有 `resize2fs`。

### 计划步骤

1. 在线把 ext4 扩到 `sda19` 的末尾。ext4 扩大可以在挂载状态下做，不用重刷 userdata。
2. 当前镜像没有免密 sudo，phablet 的密码未知。扩容需要 root，先解决这一点再执行。
3. 扩完核对 `df` 和设置里的容量。确认已有文件还在。

### 实现笔记

2026-11-09 在线扩完。分区 `sda19` 217087640 个 512 字节扇区，文件系统原来 2097152 个 4K 块（8GiB），`resize_inode` 和 `64bit` 都在。`resize2fs` 1.47.0 在挂载状态下扩到 27135955 块，正好到分区末尾。`df -h /` 从 7.7G 变成 101G，已用仍是 3.4G，可用 93G。`/etc/os-release` 和 `/home/phablet` 还在。

正常镜像没有免密 sudo，phablet 在向导里设过密码。临时把 `boot-ut-trace.img`（`5da875e07435848fb10dc3213a949eb4c4856c1849a7e792d14582fdce580365`）写入 `boot_b`，用它的免密 sudo 执行扩容，再写回 `boot-ut.img`（`7817dbfd45d4fa86b8a977f6504ba11ceb66aabc64b0b7b1c3884ea4596ef264`）。userdata 没有重刷。写回后正常启动，`df` 仍是 101G，`/etc/sudoers.d/` 里没有 trace 的免密文件，Lomiri 在跑。设置里的数字还没有人看过。

### 事件

- 用户把手机送进 fastboot。`current-slot` 是 `b`。写入 trace 镜像并重启，10 秒后 SSH 可用，`sudo -n` 是 root。
- `resize2fs /dev/sda19` 返回 0。块数 2097152 → 27135955。`df` 为 101G，已用 3.4G。
- 写回正常的 `boot-ut.img` 并重启。adb 起来后 `df` 仍是 101G，已有文件还在。

## 2. 用这棵内核重编 vendor 模块

目标：Wi-Fi、音频、蓝牙电源和相机的驱动由内核 `#7` 这棵树编出来，vermagic 对得上，启动后能进 `lsmod`。

现象：`uname -r` 是 `5.4.283~positron/42e99ef7`。`/android/vendor/lib/modules/` 有 39 个 `.ko`，`qca_cld3_wlan.ko` 的 vermagic 是 `5.4.259-qgki-g3ad529ef5970 SMP preempt mod_unload modversions aarch64`。两边对不上，所以一个都没加载。源码在这棵 `android_kernel_xiaomi_sm6375` 14.0 里：`drivers/staging/qcacld-3.0`，`techpack/audio`，`techpack/camera`，`techpack/datarmnet`。`halium-sunstone.fragment` 还没打开它们。

### 计划步骤

1. 不 insmod 现成的 `.ko`。
2. 在 fragment 里打开 qca-cld3、audio techpack（q6、bolero、wcd938x、machine）、camera，以及 `CONFIG_BT_HCIVHCI`。能编成模块就编成模块。
3. 打出新内核，写入 `boot_b`。其它分区不动。Android 14 的回退镜像 `out/halium14/boot.img` 保持不动。
4. 启动后看 `lsmod`、`wlan0`、声卡和 `/dev/vhci`。具体功能留给第 3、4、6、7 项。

### 实现笔记

2026-11-09 内核编出来了，还没写入手机。`adb reboot` 写不了重启参数，手机仍在跑 `#7`。

`#7` 里声卡、相机和 Wi-Fi 字符设备本来就在，不是没编进去。`/proc/asound/cards` 有 `holi-qrdsku1-snd-card`，`/dev/video*` 在，`/dev/wlan`（major 499）在，`/dev/btpower` 在。`lsmod` 是空的，因为 techpack 用 `obj-y` 编进了内核，不是模块。vendor 的 `.ko` 仍然对不上 vermagic，没有用它们。

两处真正缺的配置：`CONFIG_BT_HCIVHCI` 原来没开，所以没有 `/dev/vhci`。`CONFIG_CNSS_QCA6750` 原来没开，qcacld 没有走 WCN6750 的 IPCI。另外内建驱动要等用户态往 `/dev/wlan` 写 `ON` 才调用 `hdd_driver_load()`；`vendor.wifi_hal_legacy` 起来后已经退出，dmesg 里没有 "Wifi Turning On"。

`kernel/config/halium-sunstone.fragment` 加上 `CONFIG_BT_HCIVHCI=m` 和 `CONFIG_CNSS_QCA6750=y`。`#7` 的 Image 留在 `out/halium14/Image-7`。新内核是 `#8 SMP PREEMPT Mon Nov 9 19:42:19 EST 2026`，`kernel/build-14/arch/arm64/boot/Image` 48724480 字节，SHA256 `9840667736b261d43c78e0619b89363188707f1d176ff1934fea7bf93b886433`。`hci_vhci.ko` 的 vermagic 是 `5.4.283~positron/42e99ef7 SMP preempt mod_unload modversions aarch64`。

启动镜像里带了两件开机时要做的事：`stone-vhci.service` 执行 `insmod /lib/modules/stone/hci_vhci.ko`；`stone-wlan-on.service` 在 `lxc-android-config.service` 之后往 `/dev/wlan` 写 `ON`。先写入的 `boot-ut.img` SHA256 `db3ea3cf7d5f9bdefc4cd0f1445a446bab8e814931e6a6d26e87a0b06ea091b0`。

写入后 `uname` 是 `#8`。声卡仍是 `holi-qrdsku1-snd-card`。`lsmod` 是空的，`/dev/vhci` 没有。`/lib` 是指向 `usr/lib` 的符号链接，initramfs 的 busybox `cp -R` 没有把 `lib/modules/stone/hci_vhci.ko` 写进去，`stone-vhci.service` 因 `ConditionPathExists` 跳过。模块改放到 `usr/lib/modules/stone/`。修正后的 `boot-ut.img` SHA256 `c32153dbaab0b590d20c6d1e3ed90abefd4e643eff1d9fdcd08fe4ed87e5f4c6`。用户再次进 fastboot 后写入。`/lib/modules/stone/hci_vhci.ko` 在，`stone-vhci.service` 是 active，`lsmod` 有 `hci_vhci`（24576，Used by 1），`/dev/vhci` 是 `crw------- root root 10, 137`。声卡仍在。`wlan0` 仍然没有。bluebinder 能打开 vhci，但 Android 蓝牙服务随即退出（`Bluetooth binder service failed` / `Remote has died`），这项留给第 6 项。adb 仍未枚举。

`wlan0` 没有。驱动已经认出 QCA6750，固件在 19.0 秒报 ready，探针一开始固件就 early crash（`PD service down ... cause: FW crash`），随后 `hif_wlan_enable` 返回 -110。`stone-wlan-on.service` 写 `ON` 得到 I/O error。这是固件在探针时崩溃，不是模块没加载。

RNDIS 和 SSH 正常。这次 adb 没有枚举，手机上只看到 `adbd-approver`，没有 `adbd`。

### 事件

- 对照运行中的 `#7`：声卡和 `/dev/wlan` 已由内建驱动注册，`/dev/vhci` 不存在，icnss2 报了 WLAN FW ready，但没有人写 `ON`，所以没有 `wlan0`。
- 编出 `#8` 和 `hci_vhci.ko`。
- 用户进 fastboot 后写入 `db3ea3cf…` 并重启。`#8` 起来了，声卡在，`lsmod` 空，没有 `/dev/vhci`，没有 `wlan0`。固件在 QCA6750 探针时崩溃。
- 模块路径改到 `usr/lib/modules/stone/`。新镜像 `c32153db…` 还没写入。
- 用户再次进 fastboot，写入 `c32153db…`。`hci_vhci` 已进 `lsmod`，`/dev/vhci` 存在。`wlan0` 仍没有。

## 3. 声音

目标：扬声器、听筒和耳机有声音。

现象：用户确认完全没有声音。PulseAudio 16.1 在跑，唯一的 sink 是 `sink.fake.sco`（`module-null-sink`，挂起）。没有真实声卡 sink。`audiosystem-passthrough-qti`（`IQcRilAudio`）找到 hwbinder 服务管理器后以状态 2 退出。vendor 侧的 `q6_dlkm.ko`、`bolero_cdc_dlkm.ko`、`wcd938x_dlkm.ko`、`machine_dlkm.ko` 都没加载。振动是好的，所以不是整个音频相关的 HAL 都没起来。

### 计划步骤

1. 等第 2 项的音频模块加载。
2. 看 `/proc/asound/cards` 和 PulseAudio 的 sink 列表，确认有一个真实输出。
3. 用短音测试扬声器。听筒和耳机有设备时再测。
4. 通话音频（`audiosystem-passthrough-qti`）留到第 5 项 SIM 有 modem 之后。

### 实现笔记

声卡在第 2 项就已经注册了（`holi-qrdsku1-snd-card`）。没有声音是因为 PulseAudio 建不出 droid sink。

`module-droid-discover` 按 `ro.build.version.sdk`（34）加载 `module-droid-card-30`。这份模块解析 `/vendor/etc/audio/audio_policy_configuration.xml` 时不认识 `AUDIO_OUTPUT_FLAG_SPATIALIZER`（`immersive_out`，第 141 行），整份策略作废，只剩 `sink.fake.sco`。拿掉这个端口之后，card-30 能解析策略，但接着在 `pa_droid_stream_set_route` 里对设备虚表偏移 `0x110` 做间接调用，那个槽是空的，PulseAudio 段错误退出。这块 HAL 的 `common.version` 是 `0x200`（`AUDIO_DEVICE_API_VERSION_2_0`），`open_output_stream` 在 `0xd0`，不是 `0x110`。`module-droid-card-28` 调用的就是 `0xd0`。

card-28 的解析器更旧：不接受空格分隔的多个 flag、采样率或声道，被包含的蓝牙策略文件还会触发断言把进程打掉。给它的策略做了这几处删减：去掉 spatializer 端口，每个 flag、采样率、声道只留一个它认识的值，被包含的四个文件改成同一套删减后的副本。`primary output` 保留 `AUDIO_OUTPUT_FLAG_PRIMARY`。

当前会话用 phablet 的用户单元覆盖 `PULSE_SCRIPT`，指向 `/home/phablet/.config/stone/touch.pa`，里面改为加载 `module-droid-card-28`。重启后这份用户配置还在，不需要再刷 boot。同一改动放进了 `boot/ut-init/rootfs-overlay/`（`/etc/pulse/stone-touch.pa`、`/usr/share/stone/` 下的策略、`pulseaudio.service.d/zz-stone-audio.conf`），下一次做启动镜像时带上。

结果：`sink.primary_output` 和 `sink.deep_buffer` 都在，但用户确认外放和铃声都没有响。`paplay` 返回 0 只说明数据进了 HAL。64 位进程加载的是 `/vendor/lib64/hw/audio.primary.default.so`（11 KB 的 AOSP 空实现）。真正的 HAL 是 32 位的 `audio.primary.holi.so`，PulseAudio 碰不到它。

按 `mixer_paths_qrdsku1.xml` 的 `speaker` 和 `low-latency-playback` 把 MultiMedia5（`hw:holiqrdsku1sndc,9`）接到扬声器：`RX_MACRO RX2 MUX=AIF2_PB`，`RX INT2_1 MIX1 INP0=RX2`，`RX INT2_1 INTERP=RX INT2_1 MIX1`，`AUX_RDAC Switch=1`，`SpkrLeft Sipa Power=On`，`RX_CDC_DMA_RX_1 Audio Mixer MultiMedia5=1`。直接 `aplay` 到这个设备后，用户确认听到了声音。

这条通路现在是 PulseAudio 的默认 sink `sink.speaker`（`module-alsa-sink`）。开机时 `speaker-route.sh` 先写混音器。当前会话用的是 `/home/phablet/.config/stone/` 里的脚本和 `touch.pa`，重启后还在。同样的文件在 `boot/ut-init/rootfs-overlay/usr/lib/stone/speaker-route.sh` 和 `etc/pulse/stone-touch.pa`，下一次做启动镜像时带上。通过 `sink.speaker` 再播了一次 2 秒 440 Hz，用户确认听到了。听筒、耳机还没接这条通路。麦克风和通话音频仍未做。

用户接着反馈：隔一会儿打出的第一下按键音正常，后面的不响或者很弱；设置里试听铃声完全没有。同一套操作在 Ubuntu Touch 24.04.2 的 Nothing Phone 上铃声是响的。

按键音不稳的原因在 `msm-pcm-q6-v2.c` 的 mmap 路径：启动时把环形缓冲的每个 period 都交给 DSP，每播完一个又立刻重新排队。DSP 手里始终是整段缓冲，Pulse 以为还能回绕改写的数据其实已经交出去了。设备刚打开时的第一声不需要回绕，听得到；`module-suspend-on-idle` 大约 5 秒内设备还开着，后面的短音靠回绕插入，就丢了或只剩一截。

第一次改成 `mmap=0`，结果更糟。拷贝模式下每次写都在 `msm_pcm_copy` 里等 DSP 还回 period，Pulse 的 ALSA 线程长时间处于 D 状态，日志里是 `q overrun, queuing locally`。用户听到按键音之间延迟很大，铃声大约一分钟后才响。

现在的做法：保留 mmap，缓冲改小为 4×10 ms（`fragments=4 fragment_size=1920`），`rewind_safeguard=7680` 等于整段缓冲，Pulse 不再回绕，新声音最多晚 40 ms 起播。连续 6 次 80 ms 短音，每次 `paplay` 从连接到播完约 165 ms，没有排队。用户单元和 overlay 里的 `touch.pa` 都已改。

铃声不走这条 sink 的直接播放。设置里的试听是 Qt `Audio`，Ubuntu Touch 把它交给 media-hub。这颗内核的 AppArmor 没有给 unix socket 填对端标签（`SO_PEERSEC` 返回 `ENOPROTOOPT`），`/sys/kernel/security/apparmor/features/dbus/mask` 也不存在。会话总线因此对每个连接都回答 `AppArmorSecurityContextUnknown`。media-hub 拿到空的配置名就 `abort`，整次试听失败。Nothing Phone 的内核能给出标签，所以同样的界面有声音。

处理放在用户目录，不需要再刷启动镜像：`/home/phablet/.config/stone/media-hub-server` 是 `/usr/bin/media-hub-server` 的副本，空标签时换成一个静态的 `unconfined` 字符串再走原来的解析。`~/.config/systemd/user/media-hub.service.d/zz-stone-unconfined.conf` 把服务指到这份副本。用和设置相同的路径播了 `/usr/share/sounds/lomiri/ringtones/Ubuntu.ogg`：media-hub 不再崩溃，在 `sink.speaker` 上以 `media.role=alert` 播放，大约 8 秒后正常停。

### 事件

- `module-droid-card-30` 因 `AUDIO_OUTPUT_FLAG_SPATIALIZER` 解析失败，去掉该端口后又在 HAL 虚表 `0x110` 空指针上崩溃。
- 改加载 `module-droid-card-28`。出现 `sink.primary_output`，但用户确认没有声音。原因是 64 位空 HAL。
- 按 qrdsku1 的扬声器通路用 `aplay` 播放，用户确认听到了。
- PulseAudio 默认输出改为 `sink.speaker`（MultiMedia5）。又播了一次短音，用户确认听到了。
- 按键音只有停顿后的第一声正常。原因是 DSP 不回绕。`sink.speaker` 改为 `mmap=0`。
- 铃声试听把 media-hub 打崩：内核给不出 AppArmor 对端标签，空名字触发 abort。用户目录里的 media-hub 把空标签当成 `unconfined`。同一条试听路径播完了 `Ubuntu.ogg`，输出在 `sink.speaker`。
- 用户反馈按键音之间延迟极大，铃声晚约一分钟。原因是 `mmap=0` 让 Pulse 卡在 `msm_pcm_copy`。改回 mmap，40 ms 缓冲，`rewind_safeguard` 覆盖整段缓冲。短音不再排队，铃声试听约 0.85 秒内在扬声器上开始播放。

## 4. Wi-Fi

目标：能扫描、关联，并拿到 IP。

现象：用户确认 Wi-Fi 不可用。没有 `wlan0`。Android 侧 `vendor.wifi_hal_legacy` 和 `wificond` 都是 running，`wifi.interface` 为 `wlan0`。驱动是 `qca_cld3_wlan.ko`，没加载。

### 计划步骤

1. 等第 2 项出现 `wlan0`。
2. 扫描并连接一个已知网络，确认 DHCP。
3. 若关联成功但网页失败，先看手机时钟是不是还在 1970 年。

### 实现笔记

### 事件

## 5. SIM

目标：ofono 能看到 modem，设置里能识别 SIM。

现象：用户确认 SIM 完全不识别。`ofono` 在运行，`GetAvailableModems` 返回 0 个，`GetErrors` 也是 0。`rmnet_data0` 到 `rmnet_data5`、`rmnet_ipa0` 已经存在，数据接口这条线至少建出来了。上一篇里 `qcrilNrd` 有过崩溃循环，这次 adb 的 logcat 没有拿到新的 RIL 行。

### 计划步骤

1. 读容器里 `qcrilNrd`、`rild` 的 logcat，和 ofono 的 journal。先分清是基带没起来，还是 ofono 没有去连。
2. 有 modem 对象之后再看 SIM 状态、信号和运营商。
3. 通话音频回到第 3 项留下的 `audiosystem-passthrough-qti`。

### 实现笔记

### 事件

## 6. 蓝牙

目标：bluebinder 保持运行，能扫到设备。

现象：用户确认蓝牙不可用。`bluetooth.service` 是 active。`bluebinder.service` 停在 activating，重启计数已经过 646。`bluebinder_wait.sh` 认为 Android 蓝牙服务在跑，随后 `Failed to open /dev/vhci device`，systemd 记 `Error: 19 (No such device)`，结果是 `protocol`。`/dev/vhci` 需要 `CONFIG_BT_HCIVHCI`，当前内核没有。`btpower.ko` 也没加载。

### 计划步骤

1. 第 2 项的内核里已经带上 `CONFIG_BT_HCIVHCI` 和 `btpower`。这一项只验证。
2. 确认 `/dev/vhci` 存在，`bluebinder` 不再重启。
3. 扫描周围设备。

### 实现笔记

### 事件

## 7. 相机

目标：相机应用能打开并出预览。

现象：用户确认相机一开就闪退。`/dev/video0`、`video1`、`video2`、`video32`、`video33` 在，`/dev/video/venus_dec` 和 `venus_enc` 也在。`camera.ko` 没加载。这次没有抓到应用侧的崩溃栈。

### 计划步骤

1. 等第 2 项的 `camera.ko` 加载，再打开相机，看是还闪退还是能预览。
2. 仍闪退就取 journal 和 logcat，对着 HAL 查，不先改显示栈。

### 实现笔记

### 事件
