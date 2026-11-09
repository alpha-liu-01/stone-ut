# Redmi Note 12 5G（sunstone）Droidian / Ubuntu Touch 可行性

探针时间：2026-11-09。只读，没有刷写、没有重启。ADB 序列号 `stone`。前半段是普通 `shell`，分区镜像和 `lpdump` 是用户授权 Magisk root 之后补做的。

参考材料：`docs/clue.md`。下文只在实测和公开设备树对得上的地方沿用它，对不上的地方以这次探针为准。

## 结论

这台机器值得做，而且应该按 Halium 来做，不要从主线内核或 Freedreno 起步。

图形这条路比 `clue.md` 担心的更顺：正在运行的显示 HAL 仍是 HIDL Composer 2.4，GPU 用户态是 2022 年的 Adreno 619，不是 Android 16 的 AIDL HWC3。libhybris 认识这套接口。

真正卡住安装方式的是分区，不是 GPU。`super` 里只有 slot B 的动态分区，其余空间被 virtual A/B 的 COW 快照占满，不存在 `system_a`。slot A 上虽有一套 boot 镜像，切过去没有对应的系统分区。第一次装 Linux 会替换 crDroid 的系统，或者占用加密的 userdata。回滚靠刷回 crDroid 包和事先导出的 boot 镜像，不能靠“另一条 slot 还是好的”。

仓库现在保持一个：本仓库 `stone-ut`。开始改内核时再单独 fork 内核仓库。设备树仓库先不开。

建议顺序：先 Droidian（Debian + Phosh），同一套 Halium boot 稳定后再放 Ubuntu Touch rootfs。电话、相机、指纹、深度休眠不进第一阶段。

## 这台机器是什么

| 项目 | 实测 |
| --- | --- |
| 机型 | Redmi Note 12 5G，SKU `sunstone_cn` |
| 产品 / 设备名 | `sunstone`；crDroid 设备 id 是统一树 `stone` |
| SoC | SM4375，平台 `holi`，QTI |
| CPU | 6× Cortex-A55（0xd05）+ 2× Cortex-A78（0xd41），arm64 |
| GPU | Adreno 619v2，节点 `/dev/kgsl-3d0` |
| 内存 | MemTotal 7,612,520 kB，约 8 GB 规格 |
| 存储 | userdata 约 104 GB，已用 31 GB，空闲 72 GB；f2fs，文件级加密 |
| 电池 | 设计容量 5000 mAh，Li-poly |
| 屏幕 | 1080×2400，440 dpi，约 392 dpi 物理密度，OLED，60/120 Hz，圆角半径 102，顶部挖孔 |
| 面板 | 内核命令行选定 `qcom,mdss_dsi_m17_38_0c_0a_fhdp_dsc_vid`，面板名 “xiaomi m17 38 0c 0a fhd dsc video dsi panel” |
| 系统 | crDroid 12.9，显示版本 `v12.9-20260416`，Android 16（SDK 36，`BP4A.251205.006`） |
| 安全补丁 | system 2026-04-01，vendor 2026-02-01 |
| 内核 | `5.4.302-qgki-g06497b244a0e`，PREEMPT，2026-04-16 15:36 EEST 编译，clang 21.0.0 |
| 基带 | `.4.c2-00029-MANNAR_GEN_PACK-1.34701.2.35423.3` |
| 当前槽位 | `_b` |
| Root | Magisk 30.6。`adb shell` 仍是 uid 2000，`su` 后是 `u:r:magisk:s0` |
| SELinux | Enforcing |

`ro.product.first_api_level` 和 `ro.vendor.api_level` 都是 31，说明出厂基线是 Android 12。正在运行的 vendor 镜像却是 crDroid 按 SDK 36 编出来的，指纹字符串仍写着 `Redmi/sunstone/sunstone:14/UKQ1.240624.001/OS2.0.6.0.UMQCNXM`。看 HAL 版本，不要看这串指纹。

公开设备树 `crdroidandroid/android_device_xiaomi_stone` 的 `16.0` 分支写着：`TARGET_KERNEL_CONFIG := moonstone_defconfig`，`TARGET_KERNEL_SOURCE := kernel/xiaomi/sm6375`，`BOARD_BOOT_HEADER_VERSION := 3`，OTA 断言设备 `moonstone,sunstone,stone`。这次探针把 boot header v3 在两套 slot 的镜像上核实了。defconfig 名字没有从运行中的内核里读出来，编内核时以这份 BoardConfig 为入口，再和本机 `/proc/config.gz` 对差异。

## 和 clue.md 不一致的地方

`clue.md` 的大方向（Qualcomm、公开源码、先 Droidian、再 Ubuntu Touch）可以保留。下面几条以本机为准。

1. 正在运行的是 `stone` 统一树的 crDroid 12.9（2026-04-16），不是文档里说的较新 `gemstone` 分支。移植基线跟这套构建走。
2. `ro.vendor.build.version.sdk` 是 36，不是一份原厂 Android 12 vendor。但显示相关 HAL 没有跟着变成 AIDL HWC3，见下一节。
3. `getprop` 里的 `verifiedbootstate=green`、`flash.locked=1`、`vbmeta.device_state=locked` 是系统属性伪装。内核命令行是 `androidboot.verifiedbootstate=orange`。vbmeta 头的 flags 等于 3，也就是 verity 和 verification 都关了。Bootloader 处于解锁后的自定义 ROM 状态。
4. `clue.md` 把 Mesa Freedreno 当成后续图形路线。运行内核里 `CONFIG_DRM_MSM` 没有打开。`/dev/dri/card0` 和 `renderD128` 都属于 `5e00000.qcom,mdss_mdp` 的下游 `msm_drm`（compatible `qcom,sde-kms`），是显示控制器，不是 Freedreno 的 GPU 节点。GPU 只走 KGSL。
5. 15–25 小时进 Phosh 只在 boot 封装和 UBWC 都顺利时才靠谱。分区布局使“先试后回滚”比那份估算假设的更贵。

## 启动镜像和分区

两套物理 slot 的 boot 都是 Android boot header v3，页大小 4096。镜像本身读过头部，没有整包拉下来。

| 镜像 | header | 内核 | ramdisk | 镜像内 OS 字段 |
| --- | --- | --- | --- | --- |
| `boot_b`（当前） | v3，header 1580 字节 | 48,105,472 字节 | 1,576,326 字节 | Android 16.0.0，补丁级别 2026-04 |
| `boot_a` | v3 | 48,103,424 字节 | 1,573,252 字节 | Android 16.0.0，补丁级别 2026-03 |
| `vendor_boot_b` | v3，页 4096 | — | vendor ramdisk 23,809,557 字节 | 命令行以 `androidboot.hardware=qcom` 开头 |
| `vendor_boot_a` | v3，页 4096 | — | vendor ramdisk 23,788,247 字节 | 同上，体积略小 |

分区大小（512 字节扇区）：

| 分区 | 大小 |
| --- | --- |
| `boot_a` / `boot_b` | 各 128 MiB |
| `vendor_boot_a` / `vendor_boot_b` | 各 96 MiB |
| `dtbo_a` / `dtbo_b` | 各 24 MiB |
| `vbmeta_a` / `vbmeta_b` | 各 64 KiB |
| `super` | 9,126,805,504 字节，和设备树里的 `BOARD_SUPER_PARTITION_SIZE` 一致 |
| `userdata` | 217,087,640 扇区，约 103.5 GiB |
| `modem_b` | 180 MiB |
| `dsp_b` | 32 MiB |
| `bluetooth_b` | 1 MiB |

`dtbo_b` 是标准 DTBO 魔数，表里只有 2 个条目，整包大约 1018 字节。当前 `dtbo_idx=1`，`dtb_idx=0`。基线 DTB 在 boot 镜像里，DTBO 只是很小的 overlay。基线 DTB 里同时放了多块面板（m17、m17 k6s、nt36672e、visionox 等），这是 stone/moonstone 共用树的结果。运行时以命令行里的 `msm_drm.dsi_display0` 为准，不要按第一块面板去适配。

`vbmeta_b` 魔数 `AVB0`，算法类型 2（SHA256_RSA2048），flags 为 3：hashtree 关闭，verification 关闭。

`lpdump` 看到的动态分区只有：

- `odm_b`、`product_b`、`system_b`、`system_ext_b`、`vendor_b`
- 以及对应的 `*-cow`

没有 `system_a` / `vendor_a`。COW 从 `super` 后部一直排到最后一个扇区。`super` 没有空闲区间，也没有第二套系统。逻辑分区属性是 `readonly,updated`，说明 virtual A/B 的更新已经落在 slot B 上，另一侧的空间正被快照占用。

已挂载的文件系统：`system`、`system_ext`、`product`、`vendor`、`odm` 都是 ext4。fstab 同时接受 ext4 和 erofs。`vendor` 742 MB 里只剩约 9 MB，`system` 大约 93% 满。不要往现有 vendor 里塞文件。

userdata 是 f2fs，`fileencryption=aes-256-xts`，还有 metadata encryption 和 inlinecrypt。fstab 里有 microSD（`4784000.sdhci`）和 USB OTG 的 vold 项。探针时没有 `mmcblk`，卡槽是空的。

内核是单体的。`/proc/config.gz` 里没有任何 `=m`，`lsmod` 为空，`/vendor/lib/modules` 不存在。Wi-Fi、触摸、KGSL、蓝牙都编进内核。`vendor_boot` 里那 23 MB 是 Android 第一阶段 ramdisk，不是外置模块包。

## 内核配置里和 Halium 有关的缺口

运行配置可读，共 6680 行。已经打开、对移植有用的部分：

- `CONFIG_ANDROID`、binderfs、binder/hwbinder/vndbinder、ashmem、ION system heap
- `CONFIG_NAMESPACES`、`CONFIG_UTS_NS`、`CONFIG_NET_NS`
- `CONFIG_CGROUPS`、`CONFIG_BLK_DEV_INITRD`、`CONFIG_EFI_STUB`
- `CONFIG_USB_CONFIGFS` 和 FunctionFS
- `CONFIG_QCOM_KGSL`、`CONFIG_DRM`、`CONFIG_DRM_MIPI_DSI`，显示走下游 msm_drm
- `CONFIG_CLD_LL_CORE`（Wi-Fi 内建）、`CONFIG_BT_QCA`、`CONFIG_BT_HCIUART_QCA`
- `CONFIG_TOUCHSCREEN_FT3519T`、`CONFIG_TOUCHSCREEN_SYNAPTICS_DSX`
- `CONFIG_BUILD_ARM64_DT_OVERLAY`

Halium / LXC / systemd 还缺、需要在内核里打开的：

- `CONFIG_PID_NS` 关闭。没有它，容器起不来。
- `CONFIG_USER_NS` 关闭。
- `CONFIG_VT` 关闭。
- `CONFIG_DEVTMPFS` 关闭。
- `CONFIG_FHANDLE` 关闭。Debian systemd 会要它。
- 这份配置里没有 `CONFIG_IPC_NS` 这一行。是高通树拿掉了该选项，还是默认并进了 `CONFIG_NAMESPACES`，要到源码里确认。挂载命名空间同样没有单独开关。

这些都是 Halium 移植的常规内核补丁，不是这台机器特有的死结。补丁应该做成相对 crDroid `android_kernel_xiaomi_stone` 的小差异，而不是把整棵内核拷进本仓库。

编这份内核的编译器是 clang 21。Droidian 移植文档里列出的 Android clang 停在给 Android 13 用的 clang 14。第一轮编译应沿用 crDroid 能编过 `5.4.302` 的工具链，不要先换成文档里的旧 clang。

## 硬件和 HAL

### 图形

SurfaceFlinger 报的 GLES 是：

`Qualcomm, Adreno (TM) 619, OpenGL ES 3.2 V@0530.0 (GIT@c263890aed, Ifb496a9c37, 1656315076) (Date:06/27/22)`

`ro.opengles.version` 为 196610，即 GLES 3.2。Vulkan 属性是 `adreno`。KGSL 的 `gpu_model` 是 `Adreno619v2`。

`/vendor/etc/vintf/manifest/vendor.qti.hardware.display.composer-service.xml`：

- `vendor.qti.hardware.display.composer` HIDL 3.0
- `android.hardware.graphics.composer` HIDL 2.4
- `vendor.display.config` HIDL 2.0
- `vendor.display.color` HIDL 1.5

Mapper 是 HIDL passthrough，同时注册了 mapper 3.0 和 4.0，以及 QTI mapper 3.0/4.0。注释写明来源是 `hardware/qcom-caf/sm8350/display`。

HWC 当前图层格式是 `RGBA_8888_UBWC`。libhybris 加载 HWC 2.4 之后，黑屏的常见原因就是 UBWC，不是“没有 GPU 节点”。

这条组合（KGSL + HIDL HWC 2.4 + 2022 年 Adreno 用户态）是 Halium 已经做过很多次的类型。它不支持把现有内核直接拿去跑 KWin/Freedreno。

### 触摸、按键、指纹

| 输入设备 | 位置 | 说明 |
| --- | --- | --- |
| `fts_ts` | i2c-2，地址 0x38 | 触摸屏。dmesg 里 Device ID `0x54`，FocalTech |
| `qpnp_pon` | PM6125 power-on | 电源键 |
| `gpio-keys` | 平台设备 | 侧键 |
| `holi-qrdsku1-snd-card Headset/Button Jack` | ALSA，q6core APR | 耳机座 |
| `uinput-fpc` | 虚拟输入 | 指纹用户态。内核日志里是 `fpc1020` |
| `uinput-goodix` | 虚拟输入 | 树里还有 Goodix，本机活跃驱动是 FPC |

触摸驱动编进内核，而且已经接到 DRM blank 通知。Phosh 的触摸有机会在不改驱动的情况下工作。指纹留到很后面。

### 无线

`wlan0` 和 `wlan1` 存在，驱动是平台设备 `c800000.qcom,icnss` 上的 `icnss2`。固件在 `modem` 分区的 `/vendor/firmware_mnt/image`，日期 2023-10-18，含 `bdwlan.102` 到 `bdwlan.10e` 这一组板级数据，以及 ADSP/modem split 镜像。蓝牙固件在独立的 `bluetooth` 分区，有 `apbtfw11.tlv` 和一组 `crbtfw*.tlv`。

Wi-Fi HAL 本身已经是 AIDL `android.hardware.wifi` version 3。Droidian 不必走这个 HAL：内核接口已经在了，第一选择是让 wpa_supplicant 直接用 `wlan0`，固件继续从 modem 分区读。

### 音频、传感器、其他

声卡名是 `holi-qrdsku1-snd-card`，挂在 `qcom,msm-audio-apr` / q6core 下面，`/dev/snd` 里是一整套高通压缩和 PCM 设备。这是 Android Audio HAL 的路，不是一块普通 ALSA 声卡。音频会比显示慢。

传感器：TDK icm4x6xx（加速度、陀螺）、QST qmc630x（磁力）、ams tmd2755（光感和距离），其余姿态和计步来自 Qualcomm SSC。另有小米 AOD 和 pickup 传感器。

manifest 里还有 Lineage 的红外 HAL、NFC 默认服务、小米指纹 biometric HAL。fstab 说明有 microSD 卡槽。这些都只登记到“硬件在”，没有逐项验证功能。

Health HAL 是 AIDL version 4。充电和电量在内核 power supply 里大概率还能读到，不依赖这个 HAL 才能看到百分比。

## 可行性

Halium 上游仓库在 2026 年 5 月仍有 `halium-11.0` 到 `halium-14.0` 分支。UBports 移植介绍里的公开对照表写到 Halium 13（LineageOS 20）。Droidian 文档写明：Android 9 及以后的机器可以做，已有 Halium 9 以上内核的 Ubuntu Touch 移植通常能跑 Droidian。

本机没有现成的 Droidian 或 Ubuntu Touch 移植。这是新端口，不是安装现成镜像。

| 阶段 | 判断 | 依据 |
| --- | --- | --- |
| 导出 boot / vendor_boot / dtbo / vbmeta，并保住 crDroid 安装包 | 可以做 | root 已能读这些分区；两套 slot 的 boot 都还在 |
| 打上命名空间等开关后编出能启动的 Halium 内核 | 较有把握 | 5.4、header v3、单体内核、公开源码都齐；工具链必须能编过这份 qgki 树 |
| 进 Droidian shell / SSH | 较有把握 | 常规 Halium 目标。风险在 boot 与 vendor_boot 必须成对，以及切槽后没有 system_a |
| Phosh、触摸、GPU 加速 | 有机会，但是第一道技术坎 | HWC 2.4 + KGSL + 2022 年驱动是有利条件；UBWC 和 mapper 4.0 仍可能黑屏 |
| Wi-Fi | 有机会，排在显示之后 | `wlan0` 和 icnss2 固件都在；监管域和固件路径要单独处理 |
| 音频、充电显示、基础休眠 | 音频明显更难 | q6core / APR，不是简单声卡 |
| 电话、相机、指纹、NFC、红外 | 第一阶段不做 | 高通 modem、FPC、SSC 都依赖 Android HAL，周期以周计 |
| 主线内核或 Freedreno | 不做 | `CONFIG_DRM_MSM` 未开，GPU 节点是 KGSL |

`clue.md` 里“15–25 小时进 Phosh”只覆盖顺利的那条路：Halium 认这份 vendor、不必新写 HWC、UBWC 一次通过。内核补丁和 boot 打包如果顺，SSH 是几天内的工作。Phosh 要是被 UBWC 或 mapper 挡住，就是数周。能当日常手机用的 Ubuntu Touch 不在这个预算里。

Droidian 和 Ubuntu Touch 共用内核、vendor blob 和 Halium boot。Ubuntu Touch 还要单独做 Lomiri、设备配置和 OTA 布局，所以它是第二阶段，不是换一个 rootfs 就结束。

## 仓库

现在只使用这一个仓库。

`stone-ut` 放文档、Halium 内核配置片段、刷写和备份脚本、Droidian 适配、以后的 Ubuntu Touch 设备配置。两个系统的用户空间分目录放，不拆成两个项目。专有 blob 和整份 boot 镜像不要提交。

第二个仓库在第一次改内核时再建立：fork `crdroidandroid/android_kernel_xiaomi_stone`，分支专门给 Halium 5.4。内核是 GPL、体积大、上游跟 crDroid 走，放进本仓库会让克隆和评审都失真。本仓库只记录它的远程地址、分支和配置差异。

第三个仓库先不建。那会是 `android_device_xiaomi_stone` 的 fork，只有在现有 vendor 的 HIDL 图形栈驱动不了 libhybris、必须重编一套更旧的 vendor 时才需要。第一阶段直接用这台机器上的 vendor 分区和 modem 固件。crDroid 的 `proprietary_vendor_xiaomi-stone` 只作对照，不复制进 git。

## 路线图

1. 备份，仍不刷机。用 root 导出 slot A 和 slot B 的 `boot`、`vendor_boot`、`dtbo`、`vbmeta`。另外留好这份 crDroid 12.9 的安装包。个人数据单独备份。确认知道如何用 fastboot 把 slot B 的 boot 镜像写回去并切回 `_b`。
2. 把运行中的 `/proc/config.gz` 存进本仓库，做成相对 `moonstone_defconfig` 的差异说明。打开 PID/USER namespace、VT、DEVTMPFS、FHANDLE，核对 IPC 和 mount namespace。用能编过 crDroid 5.4 的 clang 编内核。
3. 打出 header v3 的 boot 和配对的 vendor_boot。DTB 仍进 boot，DTBO 保持现在的索引 1，除非内核设备树把面板选盘逻辑改了。
4. 实验性启动只替换 boot 类分区，不动 `super` 和 userdata。slot A 的旧 boot 可以覆盖，但要先导出；它不是一套能启动的旧系统。一旦新内核能进 Halium init，再决定 rootfs 放哪。
5. rootfs 用 Droidian。`super` 没有空间并行安装。userdata 是加密 f2fs，Halium 占用它就会清掉 Android 数据。这一步之前备份必须已经验证能刷回。插一张 microSD 只作为以后的根文件系统候选，这次探针时卡槽是空的。
6. 用 libhybris 接 HWC 2.4 和 KGSL，确认 `fts_ts`，再开 Phosh。Wi-Fi 走 `wlan0`。充电状态走内核接口。
7. 同一套 boot 换 Ubuntu Touch rootfs，补 Lomiri 和设备配置。
8. 音频、电话、相机、指纹、休眠单独立项。哪一项要改 vendor 或重编设备树，再决定开不开第三个仓库。

## 风险

1. 切到 slot A 不会得到一套完好的 crDroid。`super` 里没有 slot A 的逻辑分区。误切槽的表现是启动失败，修复方法是写回 slot B 的 boot 并切回 `_b`，前提是那些镜像已经导出。
2. 安装 Linux rootfs 的那一步会破坏现有系统或用户数据。`super` 已满，不能做成双系统。COW 还占着后半个 `super`，直接改动态分区前要先理解 snapshot，不能只按普通 A/B 去删分区。
3. vendor 几乎写满，系统分区也很满。适配文件要放在 rootfs 里，不要 remount vendor 再拷进去。
4. UBWC 帧缓冲可能让 HWC 已经加载、屏幕仍然全黑。这是显示阶段的主要技术风险。
5. 内核由 clang 21 编出。换一套较旧的 Halium clang 可能编不过，或编过但和现有 vendor 模块接口不一致。本机又没有外置模块，接口不一致首先会表现在显示和 Wi-Fi 固件加载上。
6. 共用设备树覆盖 sunstone 和 moonstone。defconfig 名叫 moonstone，面板表里有多块屏。编出来的 DTB 必须仍选中 m17 38 0c 0a 这块屏，并且 `dtbo_idx` 仍是 1。
7. 命令行和 vbmeta 说明验证已关，但属性被伪装成 locked/green。后续 fastboot 脚本要读命令行和 vbmeta flags，不要读 `getprop ro.boot.flash.locked`。不要重新上锁。
8. 音频、modem、指纹、相机任何一项都可能单独变成几周工作。它们失败不影响“Phosh 能亮”这个第一目标，但会决定这台机器能不能当电话用。
9. 没有官方移植。做完之后维护跟着 crDroid 的 5.4 内核走；stone 树如果停更，安全修复要自己接。

## 这次没有做的事

- 没有刷写、没有切换槽位、没有导出完整镜像文件。
- 没有读 userdata 里的个人文件。dmesg 环形缓冲区已经卷过，开机早期的面板和 Wi-Fi 探测日志不在了。
- 没有拆开 vendor_boot ramdisk 看里面的 init 和 fstab 副本。头部尺寸已经说明它是一套大约 23 MB 的 v3 vendor ramdisk。
- 没有在源码里确认 `CONFIG_IPC_NS` 消失的原因。
- 没有验证红外、NFC、相机颗数和卡槽在插入存储卡之后的实际行为。
