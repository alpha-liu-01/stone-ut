# Halium 14 与 Ubuntu Touch 24.04

让 vendor 和容器里的 Halium 系统镜像在 Android 14 对齐。Linux 根文件系统用 Ubuntu Touch 24.04-2.x。Droidian 101 和 2026-10-07 的 nightly 没有发布 api34 通用根文件系统，这一篇不用 Droidian。

手机此刻仍在跑 `docs/roadmap-04-05.md` 末尾的 Droidian Phosh（内核 DRM，USB 网络上可以 SSH）。本篇在第 6 项之前不重启、不写分区、不格式化 userdata。第 6 项要看屏幕，执行到那里就停下。

## 决定

- 停在 Droidian api32 的 `android-rootfs.img`。那份镜像是 Halium 12，配这台机器上的 Android 16 vendor 时，vendor 进程在进 init 之前就因 LL-NDK 对不上而退出。显示 HAL 仍是 HIDL Composer 2.4，libhybris 还没有被执行到。
- vendor 用已经放在工作区里的 `third_party/crDroidAndroid-14.0-20241212-stone-v10.11.zip`。OTA 断言是 `pre-device=moonstone,sunstone,stone`，可以装到这台 sunstone。指纹 `POCO/moonstone_p_global` 是这棵统一 `stone` 树的编译产品名。`post-sdk-level=34`，安全补丁 2024-12-01。
- 容器系统镜像用 UBports CI 的 Halium 14 arm64 通用包。`Halium/android` 的 `halium-14.0` 分支在 2026-05-18 仍有更新，移植脚本从 2025-04 起带有这个产物的地址。
- 根文件系统用 Ubuntu Touch 24.04-2.x。UBports 的 `prepare-fake-ota.sh` 把根文件系统和 Halium 版本分开选：24.04-2.x 对应 `ubuntu-touch-android9plus-rootfs-arm64.tar.gz`，Halium 14 对应另一份 `halium_halium_arm64.tar.xz`。文件名里的 android9plus 是渠道的历史名字。
- 内核用 `crdroidandroid/android_kernel_xiaomi_sm6375` 的 `14.0`，提交 `42e99ef7fcd885b2e8c2ebbc7e0c700f1294c52d`。`crdroidandroid/android_kernel_xiaomi_stone` 现在只发布 `16.0`。正在运行的内核来自那棵 16.0 树，留给上一篇，这一篇不覆盖 `kernel/build/`。
- 刷入这份 zip 会替换 `super` 里的 crDroid 16。工作区没有 crDroid 12.9 的完整安装包。`backups/2026-11-09-crdroid-12.9/` 只能写回启动分区。

产物、内核树和压缩包放在 gitignore 的目录里，不提交。

## 1. 确认三件套还能下载

目标：在下载大文件之前，确认 Jenkins 上的 Halium 14 产物、Ubuntu Touch 24.04-2.x 根文件系统，以及 Android 14 内核分支都还在。

### 计划步骤

1. 请求下面两个地址的 HTTP 头。任一地址 404 就停在这一项，不改用别的版本碰运气。
   - `https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%252Fporting%252Fcommunity-ports%252Fjenkins-ci%252Fgeneric_arm64/job/halium-14.0/lastSuccessfulBuild/artifact/halium_halium_arm64.tar.xz`
   - `https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%252F24.04-2.x/lastSuccessfulBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz`
2. 记下最终跳转到的文件名和 `Content-Length`。
3. 再确认 `android_kernel_xiaomi_sm6375` 的 `14.0` 仍指向 `42e99ef7`。

### 实现笔记

2026-11-09 两个地址都直接返回 HTTP 200，没有跳转。

- Halium 14：`halium_halium_arm64.tar.xz`，`Content-Length` 144311736，`Content-Type` `application/x-xz`。
- Ubuntu Touch 24.04-2.x：`ubuntu-touch-android9plus-rootfs-arm64.tar.gz`，`Content-Length` 971702706，`Content-Type` `application/gzip`。
- `android_kernel_xiaomi_sm6375` 的 `14.0` 仍是 `42e99ef7fcd885b2e8c2ebbc7e0c700f1294c52d`。

### 事件

- 请求两个 CI 产物的 HTTP 头，都是 200。
- 再次读取内核远程分支，提交没有变。

## 2. 下载 Halium 14 系统镜像和 Ubuntu Touch 根文件系统

目标：把两个压缩包放到 `third_party/halium14/`，确认一个是 Android 14 的系统镜像，一个是 Ubuntu 24.04 的根文件系统。

### 计划步骤

1. 下载第 1 项记下的两个文件。目录已在 `.gitignore`。
2. 计算 SHA256。
3. 列出压缩包内容。系统镜像里读 `ro.build.version.sdk` 和 `ro.build.version.release`。根文件系统里读 `/etc/os-release`。
4. 记下安装布局：系统镜像和根文件系统各是什么文件名，第 6 项要按这个布局写刷写步骤。

### 实现笔记

2026-11-09 两个文件都下到 `third_party/halium14/`，不进 git。

- `halium_halium_arm64.tar.xz`，144311736 字节，SHA256 `1b1b42138618e34db740f324653b390dd69e067450f9fc453290fdf323c4915e`。包里只有 `system/var/lib/lxc/android/android-rootfs.img`（453488640 字节，ext4）。镜像内 `system/build.prop` 是 `lineage_halium_arm64-userdebug 14 AP2A.240905.003`，`ro.build.version.sdk=34`，`ro.build.version.release=14`。
- `ubuntu-touch-android9plus-rootfs-arm64.tar.gz`，971702706 字节，SHA256 `ec130c13231b5562e4ce360d555f1aee5769275b7c3b8eae9f89bfc03ec92562`。`/usr/lib/os-release` 是 Ubuntu 24.04.5 LTS，`VARIANT=Touch`，`VERSION_CODENAME=noble`。`/etc/os-release` 指向这个文件。压缩包来自 24.04-2.x 的 CI 任务。根文件系统顶层已经有 `android/`、`userdata/`、`system` 这些挂载点。

安装时，Halium 的 `android-rootfs.img` 落在根文件系统的 `/system/var/lib/lxc/android/android-rootfs.img`。Ubuntu 根文件系统单独展开。具体刷写命令留到第 6 项，这一项不写分区。

### 事件

- 下载 Halium 14 通用包和 Ubuntu Touch 24.04-2.x 根文件系统。
- 读出系统镜像的 SDK 34 / Android 14，以及根文件系统的 Ubuntu 24.04.5 Touch。

## 3. 取出 Android 14 内核并核对面板

目标：浅克隆 `14.0`，确认它仍用 `moonstone_defconfig`，并且设备树里有这台机器的 m17 面板。不编译。

### 计划步骤

1. 克隆到 `third_party/android_kernel_xiaomi_sm6375/`，`--depth 1 --branch 14.0`。
2. 确认 defconfig 路径是 `arch/arm64/configs/moonstone_defconfig`。
3. 在设备树里查找 `qcom,mdss_dsi_m17_38_0c_0a_fhdp_dsc_vid`。找不到就停下，不用 moonstone 的另一块面板代替。
4. 在这棵树的 `init/Kconfig` 里核对 `CONFIG_IPC_NS` 仍依赖 `CONFIG_SYSVIPC` 或 `CONFIG_POSIX_MQUEUE`。现有片段 `kernel/config/halium-sunstone.fragment` 已经打开 `CONFIG_SYSVIPC`，可以继续用。依赖关系变了就停下。

### 实现笔记

2026-11-09 浅克隆到 `third_party/android_kernel_xiaomi_sm6375/`，不进 git。`HEAD` 是 `42e99ef7fcd885b2e8c2ebbc7e0c700f1294c52d`。

`arch/arm64/configs/moonstone_defconfig` 在。面板节点 `qcom,mdss_dsi_m17_38_0c_0a_fhdp_dsc_vid` 在 `arch/arm64/boot/dts/vendor/xiaomi/dsi-panel-m17-38-0c-0a-fhdp-dsc-video.dts`。`arch/arm64/boot/dts/vendor/xiaomi/Makefile` 里 `moonstone.dtb` 是基线 DTB，`sunstone-overlay.dtbo` 是第二条，对应 `dtbo_idx=1`。

`init/Kconfig` 里 `CONFIG_IPC_NS` 依赖 `SYSVIPC || POSIX_MQUEUE`，默认 y。`kernel/config/halium-sunstone.fragment` 打开了 `CONFIG_SYSVIPC`，依赖关系和 16.0 那棵树一致，片段可以继续用。

没有编译。

### 事件

- 浅克隆 `14.0` @ `42e99ef7`。
- 核对 defconfig、m17 面板和 sunstone overlay 的顺序。
- 核对 `CONFIG_IPC_NS` 的依赖，沿用现有片段。

## 4. 编出 Halium 内核

目标：用第 3 项的树加上现有 Halium 片段，编出 `Image` 和含 m17 面板的 DTB。不刷入。

### 计划步骤

1. 工具链沿用上一篇已经编过 5.4 的一套：Ubuntu clang、`third_party/toolchain` 里的 gcc 13.3.0 nolibc、`ld.lld`。本机没有 Android 14 时代的 AOSP clang 时不另外下载一套旧 clang，编译错误停在原处。
2. 展开 `moonstone_defconfig`，再用 `kernel/config/halium-sunstone.fragment` 合并。输出目录是 `kernel/build-14/`。
3. 编译 `Image` 和 `dtbs`。qcacld 若再报 `-Wimplicit-enum-enum-cast`，沿用上一篇的 `KCFLAGS=-Wno-implicit-enum-enum-cast` 续编，并在笔记里写明。其他错误停下。
4. 确认 DTB 含 `m17_38_0c_0a`，并记下 sunstone overlay 在 Makefile 里的顺序。
5. 记录 `Image`、DTB 的大小和路径。

### 实现笔记

2026-11-09 编完，没有刷入。输出在 `kernel/build-14/`，不进 git，也没有覆盖 `kernel/build/` 里上一篇的 16.0 产物。

工具链是 Ubuntu clang 21.1.8、`third_party/toolchain` 的 gcc 13.3.0 nolibc、`ld.lld`。`moonstone_defconfig` 里 `CONFIG_SYSVIPC`、`CONFIG_PID_NS`、`CONFIG_USER_NS`、`CONFIG_VT`、`CONFIG_DEVTMPFS`、`CONFIG_FHANDLE` 原本是关闭的，合并 `kernel/config/halium-sunstone.fragment` 之后这几项和 `CONFIG_IPC_NS`、`CONFIG_VT_CONSOLE`、`CONFIG_DEVTMPFS_MOUNT` 都是 y。第一次在仓库根目录跑 `merge_config.sh` 时，它在错误的目录里找 `alldefconfig`；改到内核树里重跑后写进了 `.config`。

clang 21 在 16.0 那棵树上会把 qcacld 的枚举转换当成错误。这次从一开始就加了 `KCFLAGS=-Wno-implicit-enum-enum-cast`。链接只有栈帧大小警告，以及 `embms_tm_multicast_recv`、`ope_soc_info` 两个 static `EXPORT_SYMBOL` 警告。`Image` 生成。

产物：

- `kernel/build-14/arch/arm64/boot/Image`，47860224 字节，SHA256 `49df6f26aa062243737a1b593618135823f302af3b4392000eedc29c89e12cb2`
- `moonstone.dtb`，441131 字节，含 `qcom,mdss_dsi_m17_38_0c_0a_fhdp_dsc_vid`。模型是 `Blair QRD NOPMI`，`qcom,msm-id` 为 `<0x1fb 0x10000 0x242 0x10000>`，`qcom,board-id` 为 `<0x1000b 0x00>`
- `sunstone-overlay.dtbo`，461 字节，是 Makefile 里的第二条

### 事件

- 合并 Halium 片段。第一次 `merge_config.sh` 不在内核目录，失败后在内核树里重跑。
- 带上 qcacld 那条警告抑制后编完 `Image` 和 DTB。
- 确认新 DTB 含 m17 面板。没有刷入。

## 5. 从 Android 14 包抽出启动分区并打出未刷入的镜像

目标：boot 和 vendor_boot 使用这份 Android 14 包里的 ramdisk 和 cmdline，内核和 DTB 换成第 4 项的产物。DTBO 用包里的那一份。不执行 fastboot。

### 计划步骤

1. 只读拆开 zip 里的 `payload.bin`，抽出 `boot`、`vendor_boot`、`dtbo`、`vbmeta` 到 `out/halium14/stock/`。
2. 核对魔数和 header version。对照 vendor cmdline、DTB 是否仍选中 m17 面板，以及 `dtbo` 的条目顺序是否仍把 sunstone 放在索引 1。
3. 用 AOSP `mkbootimg.py` 打新的 header v3 镜像到 `out/halium14/`。boot 复用包里的 ramdisk。vendor_boot 复用包里的 vendor ramdisk 和 vendor cmdline，DTB 换成新编的。页大小 4096。地址沿用包内镜像：kernel `0x8000`，ramdisk `0x01000000`，tags `0x100`，dtb `0x01f00000`。包内地址不同时以包内为准，并写进笔记。
4. 解包新镜像，核对魔数、版本和大小（boot 小于 128 MiB，vendor_boot 小于 96 MiB）。
5. 计算 SHA256。不写分区。

### 实现笔记

2026-11-09 从 `payload.bin` 抽出 `boot`、`vendor_boot`、`dtbo`、`vbmeta` 到 `out/halium14/stock/`。`payload.bin` 解完就删了。没有刷入。

包内 boot 是 header v3，OS 14.0.0，补丁级别 2024-12，cmdline 为空。内核 44558848 字节，ramdisk 17159058 字节。vendor_boot 页大小 4096，kernel `0x8000`，ramdisk `0x01000000`，tags `0x100`，dtb `0x01f00000`。vendor cmdline 是：

`androidboot.hardware=qcom androidboot.memcg=1 androidboot.usbcontroller=4e00000.dwc3 cgroup.memory=nokmem,nosocket loop.max_part=7 msm_rtb.filter=0x237 service_locator.enable=1 swiotlb=0 pcie_ports=compat iptable_raw.raw_before_defrag=1 ip6table_raw.raw_before_defrag=1 androidboot.init_fatal_reboot_target=recovery`

vendor_boot 里的 DTB 是三段拼在一起的，分别是 Blair、Blairp、Holi 的 SoC DTB，板级 id 都是 0。面板不在这三段里。`dtbo.img` 有 28 个条目，启动器用 `msm-id` 和 `board-id` 选择，不是固定的索引 1。索引 1 是 Blairp ATP。和这台机器新 DTB 相同的条目是 03：`Blair QRD NOPMI`，`board-id <0x1000b 0x00>`，`msm-id <0x1fb 0x10000 0x242 0x10000>`。所以 vendor_boot 保留包里的 DTB、vendor ramdisk 和 cmdline，`dtbo`、`vbmeta` 也用包里的。新 `boot.img` 只换内核，ramdisk 与包内逐字节相同。

新镜像：

- `out/halium14/boot.img`，65028096 字节，小于 128 MiB。header v3，OS 14.0.0 / 2024-12，内核 47860224 字节。SHA256 `cbade73955c22ad1a2c0eef1ae98a9621d93aebf9260d8a06cd26a25cb3ae565`
- `out/halium14/vendor_boot.img`，1687552 字节，小于 96 MiB。DTB 和 vendor ramdisk 与包内逐字节相同。SHA256 `e60da5a06edebee4e6f3ba9cc35826537e8ea11c9cf1e74ad1ef835ea338650f`
- 包内 `dtbo.img` SHA256 `dd48023792fe91dbc1feded3f52bd97be0bf733dd733d4accbbed23c689ae6d4`
- 包内 `vbmeta.img` SHA256 `3b0ac2e7d8d82b586ab86390f893a41212a2ac963eebd6901b4010bcbdd18f2c`

payload 里还有 `odm`、`product`、`system`、`system_ext`、`vendor`、`vbmeta_system`。没有单独的 `super`，也没有 userdata。

### 事件

- 抽出 boot、vendor_boot、dtbo、vbmeta。
- 拆开 vendor DTB 和 28 条 dtbo，确认 sunstone 不是索引 1，板级匹配的是条目 03。
- 新 boot 只替换内核。vendor_boot 保留包内设备树。没有执行 fastboot。

## 6. 人工测试：刷入 Android 14，再换 Halium 启动镜像

目标：先让这台 sunstone 跑上与 Halium 14 同代的 vendor，再换第 5 项的启动镜像。执行前停下，等人工把手机送进刷写模式并确认可以替换 `super`。

### 计划步骤

1. 把第 2 项看到的系统镜像和根文件系统布局补成具体刷写命令，写进实现笔记。命令只写不执行。
2. 向用户说明：这一步会替换 `super`，工作区不能把 crDroid 16 装回去；userdata 上现在的 Droidian 根文件系统也会在安装 Ubuntu Touch 时被换掉。用户已确认 userdata 没有要保留的个人文件。
3. 等用户把手机送进 fastboot 或 recovery，并明确说可以刷。
4. 刷完后由用户看屏幕。没有进入系统、停在 logo 或 fastboot 时，先读日志，不连续重刷。

### 实现笔记

2026-11-09 停在这里。下面的命令没有执行。

这一步会替换 `super` 里的 crDroid 16。工作区没有 12.9 的完整安装包，`backups/2026-11-09-crdroid-12.9/` 只能写回启动分区。payload 不含 userdata，现在 userdata 上的 Droidian 根文件系统先留着。Ubuntu Touch 根文件系统等这次启动有结果后再装。

用户把手机送进 fastboot 并明确说可以刷之后，再做：

1. 把 payload 里还没抽出的 `odm`、`product`、`system`、`system_ext`、`vendor`、`vbmeta_system` 解到 `out/halium14/stock/`。
2. 进入 fastbootd，槽位保持 `_b`。
3. 把那五个逻辑分区和 `vbmeta_system` 按包内镜像写入当前槽。
4. `dtbo_b`、`vbmeta_b` 用包内镜像。`boot_b` 用 `out/halium14/boot.img`。`vendor_boot_b` 用 `out/halium14/vendor_boot.img`。
5. 重启。由用户看屏幕。没有进系统、停在 logo 或回到 fastboot 时，先读日志，不连续重刷。

### 事件

- 写出刷写顺序。没有把手机送进 fastboot，没有写分区。
- 用户进入 bootloader fastboot 后，先执行了 `fastboot reboot fastboot`。手机没有进入 fastbootd，而是启动了现在的 Droidian。当前 `boot_b` 是 Droidian 镜像，ramdisk 里没有 `fastbootd`。包内 Android 14 boot ramdisk 是 gzip，含 `system/bin/fastbootd`。分区都没有写。下一步改为先在 bootloader 写入 boot、vendor_boot、dtbo、vbmeta，再进 fastbootd 写逻辑分区。
- 2026-11-09 按这个顺序写了 `boot_b`（`out/halium14/boot.img`）、`vendor_boot_b`、`dtbo_b`、`vbmeta_b`，槽位保持 `_b`。再次 `fastboot reboot fastboot` 进入了 fastbootd。`fastboot getvar unlocked` 是 no，调整 `odm_b` 被拒绝。bootloader 里 `unlocked: yes`，`Device unlocked: true`。fastbootd 用 `ro.boot.verifiedbootstate` 是否等于 `green` 判断锁定。往 vendor cmdline 加上 `androidboot.verifiedbootstate=orange` 之后仍然是 no。把 ramdisk 里 `system/bin/fastbootd` 的比较字符串 `green` 改成 `xxxxx` 后，fastbootd 报 unlocked: yes。
- 逻辑分区：`system_b`、`system_ext_b`、`product_b`、`vendor_b` 写入成功。`odm_b` 第一次失败，super 里还占着上一套 virtual A/B 的 `*-cow`。删掉 `system_b-cow`、`system_ext_b-cow`、`product_b-cow`、`vendor_b-cow`、`odm_b-cow` 后 `odm_b` 和 `vbmeta_system_b` 写入成功。没有动 userdata。然后 `fastboot reboot`。
- 重启后进了 Android recovery：Can't load Android system. Your data may be corrupt。电脑上 adb 能看到设备但是 unauthorized，发不了清除命令。userdata 仍是上一套 Android 16 的加密文件系统，Android 14 挂不上。用户确认数据不重要，在这个界面做了 Factory reset。
- 清除后系统能启动。开机动画正常，进到锁屏后屏幕全黑，锁屏音和充电提示音都有，触摸也有效。分区刷写是成功的，黑屏发生在开机动画把显示交给锁屏之后。
- 对照包内 `boot.img` 的 `IKCONFIG` 和 `kernel/build-14/.config` 后，先把包内原版 `boot.img` 写回 `boot_b`。这次界面正常，确认黑屏来自我们编的内核，不是系统分区。这台机器的指纹在电源键上，不是屏下指纹，之前把 `FINGERPRINT_GOODIX_FOD` 当成黑屏原因是错的。
- 正在运行的原版内核是 `5.4.259-qgki-g3ad529ef5970`，2024-08-09 由小米 pangu 用 clang 11 编的。`ro.crdroid.build.version` 是 `crDroidAndroid-14.0-20241212-stone-v10.11`。我们的 `Image` 是 `5.4.283~positron/42e99ef7`，clang 21。提交 `3ad529ef5970` 不在 `crdroidandroid/android_kernel_xiaomi_sm6375` 的 `14.0` 上。cmdline 里 `androidboot.dtbo_idx=3`，面板是 `qcom,mdss_dsi_m17_38_0c_0a_fhdp_dsc_vid`。用户已开 root adb。
- 第一次黑屏的内核日志在开机动画结束后报 `esd check failed report PANEL_DEAD`。来源是 `sde_encoder_kickoff()` 里 crDroid 补丁故意在第一帧调用 `_sde_connector_report_panel_dead()`。去掉这段之后重编（`#2`，SHA256 `0177473a38c6f201c5857239f27cccba234289d10e191a9ea69de547212ee87e`）并写回 `boot_b`。截图能看到锁屏，`PANEL_DEAD` 不再出现。
- 之后屏幕亮一下又黑，是电源管理在开关屏，不是合成失败。`blank:3` 是刷新率 120/60 切换。真正灭屏是 `blank:1`。logcat 里 `Going to sleep due to power_button` 后马上 `WAKE_REASON_POWER_BUTTON`，内核对应 `PMIC input: KPDPWR`。另有 30 秒超时进 Doze，以及抬起唤醒。已执行 `svc power stayon true`，避免超时再把屏关掉。
- 用户补充：不触摸时屏幕能保持亮，一有触摸就在一两秒内闪烁然后黑。当前 `#3` 内核同样。日志里手指按下后 15 毫秒执行 `dsi_display_set_mode fps=120`，之前停在 60。软件注入的点击也会切刷新率，但面板还能画出界面。把 `settings system peak_refresh_rate` 和 `min_refresh_rate` 都写成 `60.0` 之后，显示模式停在 60Hz，不再来回切。
- `#3` 内核（SHA256 `35f5278fb781709296dee99187bc885b04b4af56d600bc38bc14428e5daa3b49`）去掉了 `sde_encoder_kickoff()` 里的 `dsi_set_backlight_control()`。锁 60Hz 之后用户仍然一触摸就闪、然后黑。刷新率切换和这条命令都不是原因。
- 15:36 到 15:51 之间 Android 没有任何灭屏、Doze 或电源事件，`mState=ON`，用户却看到触摸后黑屏。所以黑屏发生在面板，不在 Android 电源管理。内核在触摸前后只有触摸上报，没有 `PANEL_DEAD`、`blank`、modeset。tracefs 里 `sde_encoder_underrun` 也没有触发。另外 15:52:02 的一次灭屏是 `Going to sleep due to application (uid 10418)`，是桌面 Launcher3 的双击锁屏，属于正常行为，不要和这个故障混在一起。
- 时间对上的是亮度：15:45:32.123 `DisplayPowerController` 从变暗的 0.05 升回 0.26，34 毫秒后才是那次触摸手势。触摸只是把屏幕从变暗状态唤回，随后一两秒的亮度渐变才是闪烁。
- 根因在设备树。crDroid 16 的 `vendor_boot` dtb 里，这块面板有 `qcom,mdss-dsi-bl-inverted-dbv`。Android 14 原厂 `dtbo` 第 3 项没有这个属性，只有小米自己的 `qcom,mdss-dsi-bl-dcs-type-ss-ea`。crDroid 内核（`sm6375` 和 `stone` 两棵树）只认前者。少了它，`mipi_dsi_dcs_set_display_brightness()` 先发低字节，面板按高字节在前解读。544（0x0220）到面板成了 0x2002，按 11 位就是 2，近乎全黑。变暗时的 111（0x006F）成了 0x6F00，反而是亮的。这就是不碰时亮、一碰就闪然后黑。
- 不重编先做了验证：往 `/sys/class/backlight/panel0-backlight/brightness` 写 514（0x0202，两个字节相同，换不换序都一样）。用户确认屏幕正常、稳定、亮度适中。
- crDroid 16 dtb 里，正好是两块带 `ss-ea` 的 m17 面板加了 `inverted-dbv`，其它面板早就有。所以在 `dsi_panel_parse_bl_config()` 里把 `qcom,mdss-dsi-bl-dcs-type-ss-ea` 也当作 `bl_inverted_dbv`。同时把 `dsi_set_backlight_control()` 放回 `sde_encoder_kickoff()`，原版内核和 crDroid 16 内核都会按刷新率发 bc 命令。第一帧 `PANEL_DEAD` 那段仍然去掉。
- `#4` 内核 SHA256 `7fcc1d7a0e5661972ff5c702fb79c69d271b2b7bc5fe995c4e1a620a34820bfe`，写入 `boot_b`。删掉了 `peak_refresh_rate` 和 `min_refresh_rate`，`screen_off_timeout` 恢复 30000。用户解锁、滑动、开应用、拖亮度条、电源键开关屏，屏幕都稳定，亮度条平滑。显示问题解决。
- 回头清理之前的尝试。`#2` 去掉第一帧 `PANEL_DEAD` 是误判：开机动画后黑屏同样是亮度字节序，Android 正是在那时写入 544。crDroid 16 内核保留这段，所以 `sde_encoder.c` 用 `git checkout` 恢复成上游原样。内核树相对 `42e99ef7` 只剩 `dsi_panel.c` 的 `ss-ea` 修正。手机上执行 `svc power stayon false`（`stay_on_while_plugged_in` 回到 0），`screen_off_timeout` 回到 30000。`peak_refresh_rate` 是 crDroid 默认的 `Infinity`。
- `#5` 内核 SHA256 `756be6253b146699794ef892762426107b502aca570c5003611e7c66c8c6fb98`，写入 `boot_b`。开机 11.9 秒报一次 `PANEL_DEAD`，是那段补丁的预期行为，随后 `mState=ON`。用户确认显示和 `#4` 一样稳定。
