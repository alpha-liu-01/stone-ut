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

源码差异和配置差异分开记，内核树继续留在 gitignore 里。配置是 `kernel/config/halium-sunstone.fragment`。源码相对 `crdroidandroid/android_kernel_xiaomi_sm6375` 的 `14.0`、提交 `42e99ef7fcd885b2e8c2ebbc7e0c700f1294c52d`，补丁在 `kernel/patches/`。浅克隆之后、展开 defconfig 之前，在内核目录执行 `git apply`，路径按克隆位置换成仓库里的 `kernel/patches/*.patch`。`git apply` 能直接吃这些文件。

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
- 亮度字节序的修改不进被忽略的内核树。导出为 `kernel/patches/0001-dsi-treat-xiaomi-ss-ea-as-inverted-dbv.patch`，基线就是上面的 `42e99ef7`。在干净树上 `git apply` 复核过，打完和现在 `third_party/android_kernel_xiaomi_sm6375/` 里的 `dsi_panel.c` 一致。

## 7. 准备 Ubuntu Touch 的 userdata 和启动镜像

目标：第 6 项的 Android 14 已经在这台 sunstone 上跑起来，显示可用。这一项在主机上做好 Ubuntu Touch 24.04 的 ext4 和配套 boot。不写分区，不重启。写入手机和看屏幕是下一次人工测试。

### 计划步骤

1. 按根文件系统里的挂载脚本核对 `android-rootfs.img` 的路径。和第 2 项从压缩包路径看出的位置不一致时，以脚本为准。
2. 把 Ubuntu 根文件系统展开成一份 ext4。镜像容量小于 userdata，只覆盖分区开头。Halium 的 `android-rootfs.img` 放进脚本要找的位置。
3. 用现有的 aarch64 静态 busybox 做 initramfs。按 `PARTNAME=userdata` 找到分区，以 ext4 挂上，`switch_root` 进 `/sbin/init`。
4. 用已经含亮度补丁的 `#5` 内核打 header v3 的 boot。不重打 `vendor_boot`，DTB 继续用槽位里现有的那份。
5. 核对镜像内容。不执行 fastboot。

### 实现笔记

2026-11-09 两个镜像都在 `out/halium14/`，不进 git。没有刷入。

第 2 项写的 `/system/var/lib/lxc/android/android-rootfs.img` 是 Halium 包里的路径。Ubuntu 根文件系统里 `/system` 是指向 `/android/system` 的符号链接。`usr/libexec/lxc-android-config/mount-android-system` 实际依次找 `/var/lib/lxc/android/android-rootfs.img`、`system.img`，以及 `/userdata/` 下的同名文件。找到 `android-rootfs.img` 就把它 loop 挂到 `/android`，这个镜像内部自带 `/system` 目录。所以镜像里放的是 `/var/lib/lxc/android/android-rootfs.img`，453488640 字节。

根文件系统的 `/init` 是 jumpercable。它还要再挂一次名为 userdata 的分区，用来放可写数据，默认这和根分区不是同一个。这次 userdata 分区本身就是 Ubuntu 根文件系统，所以 initramfs 不执行那个 `/init`，直接进入 `/sbin/init`。`vendor`、`odm` 在 `super` 的逻辑分区里，这份 initramfs 不建立 device-mapper 节点。`mount-android-partitions` 只会按分区名和 `/dev/mapper/` 去找，第一次启动时容器很可能还看不到 vendor。

展开用的是 fakeroot，不需要主机 root。`mke2fs` 用的是 `/usr/sbin/mke2fs`，不是 SDK 里的那份。压缩包的属主和权限留在镜像里。安全能力（file capabilities）这次没有保留。展开目录留在 `out/halium14/rootfs-tree/`。

产物：

- `out/halium14/userdata-ut.img`，8 GiB，ext4，卷标 `userdata`，UUID `20175c14-63c9-49f3-a991-dc8abb53545c`。空闲约 4.6 GiB，inode 用了约 7 万，共 1048576。`/usr/lib/os-release` 是 Ubuntu 24.04.5 LTS，`VARIANT=Touch`。SHA256 `5e105a81f5459d83fbcd7779a2295c91d000386e87f6050676a3f4d48f9b645b`。
- `out/halium14/boot-ut.img`，header v3，OS 14.0.0 / 2024-12。内核是 `#5`（SHA256 `756be6253b146699794ef892762426107b502aca570c5003611e7c66c8c6fb98`），ramdisk 745443 字节、lz4。整个 boot 47 MiB，小于 128 MiB。SHA256 `d7f4a8ec27235166b1e05dd3b916fb17004853a630fb99fefa8e4adf5c95a9ab`。

手机现在仍是第 6 项的 Android 14，槽位 `_b`，`boot_b` 是 `#5` 内核加 Android ramdisk。`vendor_boot_b`、`dtbo_b`、`vbmeta`、`super` 不动。下一次人工测试才写入；用户把手机送进 fastboot 并确认可以覆盖 userdata 之后：

1. `fastboot flash userdata out/halium14/userdata-ut.img`
2. `fastboot flash boot_b out/halium14/boot-ut.img`
3. `fastboot reboot`，由用户看屏幕。

没有进系统、停在 logo 或回到 fastboot 时，先读日志，不连续重刷。回到 Android 14 时，`boot_b` 写回 `out/halium14/boot.img`，userdata 还要在 recovery 里重新格式化成加密 f2fs。

### 事件

- 按挂载脚本改了 `android-rootfs.img` 的落点，不再用 `/system/var/...`。
- 做成 8 GiB 的 ext4 和 47 MiB 的 boot。没有执行 fastboot，没有重启。
- 2026-11-09 用户把手机送进 fastboot。`current-slot` 是 `b`，`unlocked: yes`。`fastboot flash userdata` 先报 `Invalid sparse file format at header magic`，随后把 raw ext4 分成 5 段发出，每段 Writing 都是 OKAY，总时间 90.9 秒。`boot_b` 写入 `out/halium14/boot-ut.img` 也是 OKAY。槽位仍是 `_b`。`vendor_boot`、`dtbo`、`vbmeta`、`super` 没有动。然后 `fastboot reboot`。由用户看屏幕。
- 手机停在 Redmi 第一屏，USB 上没有任何设备，用户手动回到 fastboot。随后写入的 `boot-ut-logs.img`（先挂 ext4 再开 ACM 串口）同样停在第一屏，主机内核日志（`journalctl -k` 可读）里也没有任何枚举。
- 根因在 ramdisk 的目录骨架，不在内核。header v3 启动时 bootloader 把 vendor ramdisk 和 boot ramdisk 拼在一起解开。Droidian 那次用的是 crDroid 16 的 `vendor_boot`，它的 vendor ramdisk 自带完整 Android 根目录（`proc`、`sys`、`dev`、`tmp` 等）。现在槽位里的 Android 14 `vendor_boot` 只有 `first_stage_ramdisk/` 和 `lib/`；我们的 busybox cpio 也只有 `bin/` 和 `init`。于是 `/proc`、`/sys`、`/dev` 三个挂载点都不存在，挂载全部失败，也没有 `/dev/console`。没有 `/sys/class/block` 就找不到 userdata，init 进了看不见的 `sh`；没有 `/sys/class/udc` 日志镜像也开不了 USB。Android 14 自己的 boot ramdisk 带有这些目录，所以同一个内核加同一个 `vendor_boot` 能进 Android。Droidian 能进第二屏，是因为碰巧借到了 crDroid 16 vendor ramdisk 的目录。内核驱动不是原因：vendor ramdisk 里的 UFS、时钟、pinctrl 模块在 `#5` 里都是内建的。
- 修正：`build-boot-image.sh` 在 cpio 里放入 `proc`、`sys`、`dev`、`tmp`、`config`、`newroot` 等目录，并用 fakeroot 做出 `dev/console`、`dev/null`，不需要主机 root。init 在挂载前也会 `mkdir -p`。init 失败时不再进静默 shell，而是开 `0525:a4a7`（产品名 `boot-fail`）串口循环送出报告和 dmesg；`switch_root` 前把 initramfs 的报告和 dmesg 写到 userdata 根目录的 `stone-initramfs-report.txt`、`stone-initramfs-dmesg.txt`。
- 新的 `boot-ut.img`（ramdisk 746261 字节，lz4，SHA256 `76fcd43d0d52bb51968e8bf36ab7a5dcc8e8a87542f6df10e81b4a5c880a701b`）写入 `boot_b` 并重启，槽位 `_b`，其它分区没动。离开 fastboot 后 90 秒内主机没有看到任何 USB 设备，也没有 `boot-fail` 串口。UT 的 `usb-moded` 默认模式可能根本不开 gadget，所以这还不能区分「systemd 已经起来」和「init 仍然失败」。
- 另打了 `out/halium14/boot-ut-disk.img`（SHA256 `151292b6fc31de170b487da1936b6a3656773eec30d444c05750a606027406df`），尚未写入：读写挂上 userdata 让 ext4 回放，把 `journalctl -b -1`、全部 journal、启动列表和 dmesg 写到 `/stone-logs/`，再把 userdata 只读导出成 U 盘（`1d6b:0104`，`stone-userdata`）。根文件系统的 journal 是持久的（有 `/var/log/journal`，没有 volatile 覆盖）。
- 用户确认仍停在 Redmi 第一屏，并回到 fastboot。写入 `boot-ut-disk.img`，离开 fastboot 8 秒后出现 `1d6b:0104` U 盘，主机 `udisksctl` 只读挂上 `/dev/sdb`（103.5G，卷标 userdata）。说明修正后的 ramdisk 在 `#5` 内核上能跑，USB gadget 也能用。
- `stone-initramfs-report.txt` 存在：init 在内核 2.0 秒找到 `/dev/sda19`、挂上 ext4 并 `switch_root`。`journalctl --list-boots` 只列出 10 月 12 日打包时的那次启动，因为手机时钟是 1970 年，新的 journal 排在前面被忽略。按 1970 年的修改时间找到这次启动写下的 journal 文件，用主机的 `journalctl --file` 读出：systemd 正常运行，2.5 秒 journal 落盘、`local-fs.target` 达成。`mount-android-partitions` 报 `Hmm... can't guess a partition for /android/vendor`。随后 `lxc-android-config.service` 的 start-post 等到 93 秒超时，`systemd-udev-trigger` 排在它之后才开始。没有 vendor 就没有 Android 容器和 hwcomposer，Lomiri 画不出来；内核没有 fbcon，cmdline 也没有 `splash`，Plymouth 不启动。所以屏幕一直是 bootloader 的 Redmi 图。
- 这就是前面记下的已知缺口：`vendor`、`odm` 在 `super` 的逻辑分区里。`common.sh` 的 `find_partition_path` 先找 `/dev/mapper/<名字>` 和 `/dev/mapper/<名字>_b`。新增 `boot/ut-init/stone-dynparts.py`：按 liblp 格式读 `super` 的几何信息和 metadata slot 1（`_b`），跳过 `_a` 和 `-cow`，用 `dmsetup create --readonly --noudevsync`（`DM_DISABLE_UDEV=1`）建出 `/dev/mapper/vendor_b`、`odm_b` 等。init 在把 `/proc`、`/sys`、`/dev` 移进新根之后、`switch_root` 之前，`chroot` 进 Ubuntu 根文件系统用它自带的 `python3` 和 `dmsetup` 执行，结果写到 userdata 根目录的 `stone-dynparts.txt`。在主机上用按同一格式构造的假 `super` 和假 `dmsetup` 验证过表的解析。
- vendor cmdline 末尾有 `ro`，`/` 没有 fstab 项时 systemd 会按它重新挂成只读。boot 镜像 header 的 cmdline 加上 `rw splash`。
- `boot-ut-trace.img`（cmdline 另加 `printk.devkmsg=on`，SHA256 `a5b9b86e658deaf4461caf868c216071227e136a18d9c7521fe18c3503c51773`）：`switch_root` 进 `/stone/init-wrapper`，它在后台每 3 秒把 dmesg、进程表、systemd 任务、失败单元和本次 journal 写到 `/stone-logs/live/` 并 sync，然后 `exec` systemd。约 3 分钟后自己重启进 bootloader。新的 `boot-ut-disk.img`（SHA256 `ba5880a379d4d7c2e776be91c82f028fd8480498607c596519e88339418f6109`）在主机弹出 U 盘后也会自己回 bootloader。两者都带 `reboot-bootloader`（无 libc，`reboot(..., "bootloader")`）。正常启动用的 `boot-ut.img` 同样带 dynparts 和 `rw splash`，SHA256 `012d829f9ccacd7c2e3ff8e8a1312d175b0d4406486cc19ec8a83fac8ad871f4`。都还没写入。
- 第一次 trace：`stone-dynparts.py` 正确读出 `super`（`/dev/sda8`，LP metadata 10.2，3 个 slot），但 chroot 里 `PATH` 还是 initramfs 的 `/bin`，找不到 `/usr/sbin/dmsetup`。改成绝对路径并显式设 `PATH`。`init-disk` 里的 `chmod 644 stone-logs/*` 去掉了 `live/` 目录的执行位，改成 `chmod -R a+rX`，并把只有 root 能读的 lightdm 日志一起复制出来。
- 教训：在主机上用 `udisksctl power-off` 弹出手机 U 盘会把主机 USB 口 1-9 断电，恢复要 root，只能重插线。以后只用 udisks 的 `Drive.Eject`（gdbus 调用）。
- vendor 映射成功后容器进入 RUNNING。`#5` 内核没有 `SECURITY_SELINUX_BOOTPARAM`，cmdline 关不掉 SELinux；也没有 AppArmor，UT 的应用隔离无从加载。`kernel/config/halium-sunstone.fragment` 加上 `SECURITY_SELINUX_BOOTPARAM`、`SECURITY_APPARMOR`、`USB_CONFIGFS_RNDIS`，打出 `#6`（存为 `out/halium14/Image-6`；`#5` 存为 `Image-5`）。boot cmdline 改为 `rw splash selinux=0 security=apparmor apparmor=1`，trace 另加 `printk.devkmsg=on`。手机上确认 SELinux 已关闭、AppArmor 已初始化。`#6`、`#7` 都还没在 Android 14 上测过。
- vendor 的 `vndservicemanager` 在 `Access::Access()` 里 `CHECK(selinux_status_open)` 失败就 abort。改用系统的 servicemanager 不行：系统 libbinder 的 parcel 头是 `SYST`（0x53595354），vendor 客户端发的是 `VNDR`（0x564e4452），系统那份服务不了 `/dev/vndbinder`。新增 `boot/ut-init/stone-vendor-fixups.py`：每次启动在 chroot 里只读挂上 `/dev/mapper/vendor_b`，核对 `bin/vndservicemanager` 的 SHA256（`bf6653db5e1384920732aa2f64a0de2abc297341d4b7775f950d0556b21b4a4f`，crDroid 10.11）和原字节，把文件偏移 0x6128 的 `tbnz`（`8001f837`，`selinux_status_open` 失败分支）和 0x6134 的 `cbnz`（`c0030035`，`getcon` 失败分支）换成 NOP `1f2003d5`，写到 halium overlay。其余 SELinux 调用在 SELinux 关闭时返回「允许」，`getpidcon` 借 AppArmor 的标签能用。手机上输出 `bin/vndservicemanager: patched 2 sites`。
- halium overlay：`mount-halium-overlay.service` 在 `mount-android-partitions` 之后、lxc 之前，把 `/android/system/halium`、`/android/system/ubuntu`、`/opt/halium-overlay/`、`/usr/share/halium-overlay/` 下的每个文件绑定到 `/` 下的同一路径（目标必须存在）。UT 镜像本身没有 `/usr/share/halium-overlay`。新增 `boot/ut-init/rootfs-overlay/`，init 每次启动先删掉旧的 `/usr/share/halium-overlay`，再把整棵树复制进根文件系统。
- 打开 vendor 的 `vndservicemanager` 后，所有 vndbinder 事务都失败（`transaction failed 29201/-22`，binder.c 第 3324 行）。vendor 的 servicemanager 设了 `FLAT_BINDER_FLAG_TXN_SECURITY_CTX`，5.4 上只有 AppArmor 时 secid 为 0，`security_secid_to_secctx` 返回 -EINVAL，binder 直接让事务失败。`kernel/patches/0002-binder-send-without-secctx-when-lsm-has-none.patch`：返回 -EINVAL 或 -EOPNOTSUPP 时不带安全上下文继续发送，接收方拿不到 SID，回退到 `getpidcon()`。打出 `#7`：`kernel/build-14/arch/arm64/boot/Image`，47999488 字节，SHA256 `0ac98a87c24ad8dc64219de411bd7f1c8bd2f286906600eafd031ff5fd0a2c40`，`#7 SMP PREEMPT Mon Nov 9 18:22:33 EST 2026`。之后 composer 注册了 `display.qservice` 并保持运行。
- USB：`CONFIG_USB_DUMMY_HCD=y` 让 `dummy_udc.0` 先于 `4e00000.dwc3` 注册，usb-moded 选错了控制器，主机上看不到设备。overlay 里加 `etc/default/usb-moded.d/stone-sunstone.conf`（`CONTROLLER=4e00000.dwc3`）和 `etc/usb-moded/91-stone-sunstone.ini`（`gadget_udc_device = 4e00000.dwc3`）。vendor 的 `init.qcom.usb.rc` 会建 `g1/configs/b.1`，和 usb-moded 的 `c.1` 冲突（EBUSY），用 overlay 换成只有注释的空文件。usb-moded 带 `-r` 运行时进 developer_mode：RNDIS 地址 10.15.19.82，udhcpd 发地址，`usb-moded-ssh` 监听 10.15.19.82:8022。构建时把主机的 `~/.ssh/id_ed25519.pub`（可用 `SSH_PUBKEY` 指定）放进 overlay 的 `home/phablet/.ssh/authorized_keys`，公钥不进仓库。内核没有 f_mtp，`mtp.mtp` 不存在；`ethaddr`、`wceis` 报错只是 Mer 的属性名，不影响 RNDIS。
- trace 镜像另带 `/etc/sudoers.d/stone-trace`（phablet 免密 sudo），正常镜像启动时会删掉这个文件。`stone-init-wrapper` 改成前 3 分钟每 3 秒快照，之后每 30 秒，20 分钟后回 bootloader；`sudo /stone/reboot-bootloader` 可立刻回。phablet 用户在 `/var/lib/extrausers`，属于 sudo 组，密码未知。
- 调试：手机上 USC（Mir 1.8.2，graphics-android2）在 Adreno 619 上初始化 EGL，认出 1080x2400 屏，转圈动画能画出来，lightdm 也拉起了 greeter。但 `lomiri --mode=full-greeter`（phablet 的用户服务 `lomiri-full-greeter.service`）在 `mirserver: Starting` 后约 0.5 秒段错误。从 ports.ubuntu.com 下了 noble 的 arm64 gdb 放到 `/tmp/gdb`，开 core dump 后回溯：`strchr` ← `strstr` ← Android `/system/lib64/libEGL.so` 的 `egl_display_t::initialize`（+0x18d14，`ldr x0,[x20,#0x30]`，读扩展字符串）。限制 glvnd 只用 hybris 后仍崩，和 Mesa 无关。
- 根因：拿正常运行的 USC 的 `egl_display_t` 对比，`+0x00` 是 `_dpy` 魔数，`+0x08` 是句柄，`+0x10` 是状态 1（已初始化），`+0x18`…`+0x30` 指向 "Qualcomm Inc."、"1.5"、"OpenGL_ES" 和扩展串。Lomiri 那份状态是 0，这几格是未初始化的堆数据：Adreno 自己的 `eglInitialize` 失败了，Android libEGL 随后对没赋值的扩展指针调用 `strstr`。USC 以 root 运行，Lomiri 以 phablet 运行，而 `/dev/kgsl-3d0`、`/dev/ion` 都是 `crw------- root root`。UT 移植通常按 Android 的 `ueventd.rc` 生成 udev 规则，这里还没有。
- 修正：新增 `tools/ueventd-to-udev.py`，把 `/system/etc/ueventd.rc` 和 `/vendor/etc/ueventd.rc` 的 `/dev` 项转成 udev 规则。用户和组写数字 AID（UT 里这些组叫 `android_*`，Android 的名字解析不了），`oem_NNNN` 直接取数字，用 `ENV{DEVNAME}` 匹配完整路径，后面的文件覆盖前面的。结果是 `boot/ut-init/rootfs-overlay/etc/udev/rules.d/70-sunstone.rules`，249 条。在手机上装进去并 `udevadm trigger --action=add`，`/dev/kgsl-3d0` 变成 0666、`/dev/ion` 变成 0664（属主 system）。重启 lightdm 后 `lomiri --mode=full-greeter` 保持运行，没有新的 core，日志里有 `Last frame took 66 ms to render`，lomiri-polkit-agent 也注册上了。
- 仍未解决、不阻塞：apparmor.service 在 5.4 上加载 profile 失败；mediaextractor、qcrilNrd 反复崩溃；bluebinder 失败；主机侧 libgbinder 客户端报 parcel 头 0x6e0061；lomiri-push-service 起不来 `com.ubports.SystemImage`（Permission denied）；没有 f_mtp。
- 当前镜像（都是 `#7` 内核，带上面全部修正，前面各条里的镜像 SHA256 都已过时）：`boot-ut.img` `40050592a624254a98b59bb52c3d60225237349ed70cda45b60647461ba79d71`，`boot-ut-trace.img` `c1edcee521aa0220382bdff3fa4581969153bf8f9949a15d78811ca059caebc1`，`boot-ut-disk.img` `13102777c80e72f8e134b135bb666f26d99b184c627ff88208494d640deeed81`。手机此刻跑的是上一版 trace 镜像，udev 规则是在线装进 `/etc/udev/rules.d/` 的，下次由用户看屏幕。
- 用户回到 fastboot 后写入带 udev 规则的 trace 镜像。冷启动后 15 秒有 SSH，`/dev/kgsl-3d0` 已是 0666，Lomiri 正常运行、没有 core。`mirscreencast -m /run/mir_socket -n 1` 能截一帧 1080x2400 RGBA（要加 `GLIBC_TUNABLES=glibc.rtld.optional_static_tls=4194304`，否则 hybris 的 `q.so` 报 static TLS 不够；phablet 用户也能截）。画面是 Lomiri 首次启动向导的「Language」页，状态栏有 Wi-Fi、电量和时钟。触摸屏 `fts_ts`（`event3`）、电源键、音量键都被 USC 打开，Lomiri 日志有 `Input device added: "fts_ts" ... TouchScreen`。
- `apparmor.service` 失败的原因：`ExecStartPre` 的 `wipe-aa-cache-on-channel-switch.py`（lxc-android-config）在不是 system-image 安装的系统上返回 1。手动 `apparmor.systemd reload` 可以加载 159 个 profile。overlay 加 `etc/systemd/system/apparmor.service.d/stone-no-system-image.conf`，把 `ExecStartPre` 改成 `-` 前缀忽略失败，服务变为 active。
- 展开根文件系统时 tar 按名字映射属主，用了主机的 ID：`messagebus` 106→995（`dbus-daemon-launch-helper` 失去 messagebus 组，系统总线激活一律 Permission denied，lomiri-push-service 起不来），`clickpkg` 107→102（`/usr/share/click` 下预装应用 5847 项变成 crontab 组），`syslog` 103→992（`/var/log`），`systemd-journal` 105→109（`/var/log/journal` 变成 rtkit 组），`/var/lib/usermetrics` 104→991。另外 `ping`（`cap_net_raw`）和 `gst-ptp-helper`（`cap_net_bind_service,cap_net_admin,cap_sys_nice`）的文件能力丢了。手机上按压缩包的数字 ID 修正了 5850 项（保留 setuid 位）并补回两个能力，`com.ubports.SystemImage` 能激活，lomiri-push-service 变为 active，phablet 能 ping。`build-userdata-image.sh` 改用 `tar --numeric-owner`，mke2fs 之后用 `debugfs ea_set` 写入压缩包里的 `security.capability`。重建的 `userdata-ut.img` SHA256 `382c9ff049bae13168a6dca8d42600446bba9fae15e8861df0f06b487a3ae551`，用 debugfs 核对过属主和能力，没有写入（手机上的 userdata 已就地修好）。
- 用户服务 `audiosystem-passthrough-qti`（IQcRilAudio，通话音频）找到 hwbinder 服务管理器后以状态 2 退出，留到通话阶段再查。
- 当前镜像：`boot-ut.img` `7817dbfd45d4fa86b8a977f6504ba11ceb66aabc64b0b7b1c3884ea4596ef264`，`boot-ut-trace.img` `5da875e07435848fb10dc3213a949eb4c4856c1849a7e792d14582fdce580365`，`boot-ut-disk.img` `3c1123f228b93116dbe94f325fa731ac3e34ef9826299535985601d01faebd02`。`boot_b` 已写入正常的 `boot-ut.img`（没有免密 sudo，不会 20 分钟后自动重启）。启动 73 秒时 Lomiri 在跑、AppArmor active、没有失败的系统单元，截图仍是向导第一页。usb-moded 的 `-r` 来自根文件系统配置，正常镜像下 phablet 仍可用公钥 SSH 到 10.15.19.82:8022。下一步由用户在屏幕上操作向导、测试触摸。手机时钟仍是 1970 年。
- 2026-11-09 用户确认 Ubuntu Touch 已经进到桌面：显示、触摸、GPU、亮度、充电感应、振动正常，adb 连着（`stone`）。Wi-Fi、蓝牙、SIM、相机、声音和内置存储容量未好。Halium 14 这条线到此为止，剩下的记在 `docs/roadmap-hardware.md`。
