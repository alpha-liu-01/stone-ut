# 路线图前三项

范围是 `docs/feasibility.md` 路线图的第 1、2、3 项。这三项停在「镜像已经做出来」。不刷机，不切换槽位，不格式化，不读取 userdata 里的个人文件。

手机仍是正在运行的 crDroid 12.9（Android 16，slot `_b`）。`third_party/crDroidAndroid-14.0-20241212-stone-v10.11.zip` 只作为已经找到的 Android 14 安装包登记。本阶段不把它刷进去，也不用它替换正在运行的内核配置。

需要人工在手机上点允许、输入提权密码，或做启动测试时，立即停下。

## 1. 备份当前可启动环境

目标：导出两套槽位的启动分区，并写明怎样用 fastboot 把 slot B 写回去。刷机不在这一项里。

### 计划步骤

1. 确认 `adb devices` 里是 `stone`，并且 `su -c id` 直接返回 root。若 Magisk 弹出授权或索要密码，停下来等人工处理。
2. 再读一次槽位、crDroid 版本和内核版本，给备份目录命名。
3. 用 root 把下列分区按完整分区大小导出到仓库外的 `backups/`，不提交进 git：
   - `boot_a`、`boot_b`
   - `vendor_boot_a`、`vendor_boot_b`
   - `dtbo_a`、`dtbo_b`
   - `vbmeta_a`、`vbmeta_b`
4. 核对文件大小和魔数。`boot` 应以 `ANDROID!` 开头且 header version 为 3，`vendor_boot` 应以 `VNDRBOOT` 开头，`vbmeta` 应以 `AVB0` 开头，`dtbo` 应以 DTBO 魔数开头。
5. 为每个文件计算 SHA256，连同版本属性写成一份清单，放在备份目录里。
6. 写下 slot B 的恢复命令：先 `fastboot set_active b`，再写回 `boot_b`、`vendor_boot_b`、`dtbo_b`、`vbmeta_b`。只写命令，不执行。
7. crDroid 12.9 的完整安装包如果工作区里没有，就在清单里记为缺口。分区镜像只能恢复启动分区，不能重建已经写满的 `super`。
8. 个人数据由用户自己备份。这一项不复制 `/sdcard` 或 `/data/media`。

### 实现笔记

2026-11-09 完成分区导出。`su -c id` 直接返回 `u:r:magisk:s0`，没有提权密码。

备份目录：`backups/2026-11-09-crdroid-12.9/`。八个镜像都是整分区，大小和魔数与探针一致：boot 各 134217728 字节、header v3；vendor_boot 各 100663296 字节、header v3；dtbo 各 25165824 字节；vbmeta 各 65536 字节、`AVB0`。SHA256 在同目录的 `SHA256SUMS`。恢复命令写在 `RESTORE.txt`，没有执行。

当前系统仍是 slot `_b`，crDroid `v12.9-20260416`，内核 `5.4.302-qgki-g06497b244a0e`。

工作区里没有 crDroid 12.9 的完整安装包。这组镜像只能写回启动分区，不能重建 `super`。`third_party/crDroidAndroid-14.0-20241212-stone-v10.11.zip` 已核对：payload.bin，`post-sdk-level=34`，安全补丁 2024-12-01，指纹 `POCO/moonstone_p_global/moonstone:14/UKQ1.231003.002/V816.0.10.0.UMPMIXM`，`pre-device=moonstone,sunstone,stone`。本阶段没有打开它的 payload，也没有刷入。

个人文件没有复制。这一项仍要用户自己备份 `/sdcard`。

### 事件

- 确认设备 `stone`，root 可用。
- 第一次 `adb exec-out` 把 `dd` 的进度文本拼进了镜像。改成 `dd ... 2>/dev/null` 后重导，`vbmeta_b` 为 65536 字节且以 `AVB0` 开头。
- 八个分区导出并核对通过。
- 写下 slot B 的 fastboot 恢复命令，未执行。

## 2. 保存运行配置并编出 Halium 内核

目标：把正在运行的内核配置留在仓库里，相对 `moonstone_defconfig` 写出差异，打开 Halium 需要的开关，并用能编过这份 crDroid 5.4 树的 clang 编出内核。产物不刷入。

### 计划步骤

1. 把 `/proc/config.gz` 解压后放进 `kernel/config/sunstone-5.4.302-running.config`。
2. 取 `crdroidandroid/android_kernel_xiaomi_stone` 的 `16.0` 分支，读出 `moonstone_defconfig`。内核树放在仓库外或 gitignore 的目录，不把整棵内核提交进 `stone-ut`。
3. 对照运行配置和 defconfig，写差异说明。重点是命名空间、VT、devtmpfs、`FHANDLE`、binder、KGSL、显示和 Wi-Fi。
4. 在这棵 5.4 源码的 Kconfig 里核对 `CONFIG_IPC_NS` 和 mount namespace。运行配置里没有 `CONFIG_IPC_NS` 这一行，先确认是选项不存在，还是被关掉了。
5. 增加一份 Halium 配置片段，至少打开 `CONFIG_PID_NS`、`CONFIG_USER_NS`、`CONFIG_VT`、`CONFIG_DEVTMPFS`、`CONFIG_FHANDLE`。IPC 和 mount namespace 按第 4 步的核对结果处理，不凭空加一个源码里不存在的选项。
6. 工具链跟运行内核走。该内核由 Android clang 21.0.0 编出。优先找 crDroid 16 / AOSP 用来编 `kernel/xiaomi/sm6375` 的 clang，而不是 Droidian 文档里的 clang 14。
7. 用 `moonstone_defconfig` 加上这份片段编译 `Image` 和本机要用的 DTB。编译失败就停在错误上，不改用另一套 defconfig 碰运气。
8. 确认编出的 DTB 仍包含并可选中 `qcom,mdss_dsi_m17_38_0c_0a_fhdp_dsc_vid`。

### 实现笔记

运行配置在 `kernel/config/sunstone-5.4.302-running.config`。内核树是 `crdroidandroid/android_kernel_xiaomi_stone` 的 `16.0`，提交 `06497b244a0e`，和运行内核版本字符串里的 `g06497b244a0e` 相同。树放在 `third_party/android_kernel_xiaomi_stone/`，不进 git。

用主机 gcc 展开 `moonstone_defconfig` 后，和运行配置的差别只在编译器身份：运行内核是 Android clang 21.0.0（`r563880c`）的 LTO、CFI、shadow call stack 和 RELR。说明见 `kernel/config/moonstone-defconfig-diff.md`。

`CONFIG_IPC_NS` 在 `init/Kconfig` 里存在，依赖 `CONFIG_SYSVIPC` 或 `CONFIG_POSIX_MQUEUE`。运行配置把这两项都关了，所以整行被隐藏。mount namespace 没有单独开关，`CONFIG_NAMESPACES` 已经打开。

片段是 `kernel/config/halium-sunstone.fragment`。展开后的配置在 `kernel/config/sunstone-halium.config`，其中 `CONFIG_SYSVIPC`、`CONFIG_IPC_NS`、`CONFIG_PID_NS`、`CONFIG_USER_NS`、`CONFIG_VT`、`CONFIG_DEVTMPFS`、`CONFIG_DEVTMPFS_MOUNT`、`CONFIG_FHANDLE` 都为 y。

本机没有 AOSP clang `r563880c`。编译器用 Ubuntu clang 21.1.8，`CROSS_COMPILE` 指向 kernel.org 的 gcc 13.3.0 nolibc（`third_party/toolchain/`），链接器是 `ld.lld`。clang 21.1.8 把 `drivers/staging/qcacld-3.0/core/dp/htt/htt_h2t.c` 的枚举转换当成错误；续编时加了 `KCFLAGS=-Wno-implicit-enum-enum-cast`。之后 `Image` 和 DTB 编完，链接只有栈帧大小警告。

产物：

- `kernel/build/arch/arm64/boot/Image`，48402944 字节
- `kernel/build/arch/arm64/boot/dts/vendor/xiaomi/moonstone.dtb`，441127 字节，含 `m17_38_0c_0a`，与当前 `vendor_boot_b` 里的 DTB 逐字节相同
- 同时编出 `moonstone-overlay.dtbo` 和 `sunstone-overlay.dtbo`，各 461 字节。Makefile 里 sunstone 是第二条，对应 `dtbo_idx=1`

没有刷入。

### 事件

- 克隆内核 `16.0` @ `06497b244a0e`。
- 展开 defconfig，确认功能选项与运行配置一致，差异只来自 gcc 和 clang。
- 核对 IPC 与 mount namespace 的 Kconfig。
- 第一次完整编译在 qcacld 的 `-Werror,-Wimplicit-enum-enum-cast` 停下。
- 关掉这一条警告后续编，`Image` 与 DTB 生成。

## 3. 打出 header v3 的 boot 和 vendor_boot

目标：用第 2 项的内核做出一对还没刷入的镜像。DTB 放在 boot 里。DTBO 继续用现有镜像，索引保持 1。

### 计划步骤

1. 从已备份的 `boot_b` 读出 header v3 的页大小、cmdline 和现有 DTB。从 `vendor_boot_b` 读出 vendor ramdisk 和 vendor cmdline。
2. 新内核如果仍是单体、没有 `.ko`，vendor ramdisk 复用 `vendor_boot_b` 里的那一份，不把 Android 16 的第一阶段 ramdisk 换成空 ramdisk。
3. 用新的 `Image` 和对应 DTB 打包 boot，header version 3，页大小 4096。
4. 打包与之配对的 vendor_boot，header version 3。
5. 不重新生成 DTBO。刷写说明里写明实验时要一起带上备份的 `dtbo_b`，并且 `dtbo_idx` 仍是 1。
6. 检查产物魔数、header version，以及文件小于对应分区（boot 128 MiB，vendor_boot 96 MiB）。
7. 产物放在 gitignore 的输出目录。不执行 fastboot。

### 实现笔记

当前 `boot_b` 的 DTB 不在 boot 里。`unpack_bootimg` 看到 boot 只有内核和 1576326 字节的 ramdisk，cmdline 为空。DTB 在 `vendor_boot_b` 里，441127 字节，加载地址 `0x01f00000`。vendor cmdline 以 `androidboot.hardware=qcom` 开头。所以新镜像按这个布局打，而不是把 DTB 塞进 boot。

`out/halium/boot.img`：header v3，新 `Image`（内核 48402944 字节），复用 `boot_b` 的 ramdisk，OS 16.0.0 / 2026-04，cmdline 为空。49987584 字节，小于 128 MiB 分区。

`out/halium/vendor_boot.img`：header v3，页大小 4096，复用 `vendor_boot_b` 的 vendor ramdisk（23817365 字节）和同一条 vendor cmdline，DTB 用新编的 `moonstone.dtb`。地址与现有镜像一致：kernel `0x8000`，ramdisk `0x01000000`，tags `0x100`，dtb `0x01f00000`。24264704 字节，小于 96 MiB 分区。

没有重新打包 DTBO。实验刷写时要带上备份的 `dtbo_b.img`，`dtbo_idx` 保持 1。

SHA256：

- boot.img `576b4637ab69cb97bef64e5f0b207d27076c11c990b800456bcf84467264f54f`
- vendor_boot.img `5ef01b41c7c6509ad18633848483cc21e3758b75dcef1c20a0dd10eccb6f09d5`

没有执行 fastboot，没有切换槽位。

### 事件

- 拆开备份的 `boot_b` 和 `vendor_boot_b`，确认 DTB 在 vendor_boot。
- 用 AOSP `mkbootimg.py` 打出一对 header v3 镜像。当前 main 分支的脚本在 import GKI 签名模块时失败，把这个 import 挪到只有 header v4 签名才执行的路径。
- 解包新镜像，核对魔数、版本、地址和分区大小。
