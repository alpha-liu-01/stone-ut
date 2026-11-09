# Redmi Note 12 5G：可能比 Galaxy Tab S6 Lite 更适合第一次移植 Droidian

[Análise do Xiaomi Redmi Note 12 5G: Um celular de médio porte barato com 120 Hz e brilho de quatro dígitos - Notebookcheck.info](https://images.openai.com/static-rsc-4/yzWMpaK_GYDcjVkQi7tV6gB1fUYpVBGjMt9PMy8hxWw2sa1fC6H2o5KXPzwY0MhCBz_-Nd1jXShFX_ZxOrVvkwV3XWpZo3WHLmW8iL8_FxsxoIi61EYnefb54gojjZLF8N8q_LkgWUbLsEsH6CXaXeK7UhI9Dt6IuV8lKd2OZ6w?purpose=inline)

## Redmi Note 12 5G

sunstone · SM4375 · Snapdragon 4 Gen 1

初步结论：我更推荐它作为你的第一台 Halium 实验机。

尤其是考虑到你已经解锁 Bootloader、成功安装并长期使用 crDroid，这比从一台原厂 Android 设备开始有明显优势。

我查到了几个相当有利的情况，也发现一个可能会影响移植难度的问题。

首先确认：你这台是 Redmi Note 12 5G，并非 4G 版本，因为骁龙 4 Gen 1 对应 5G 机型。

| 项目           | Redmi Note 12 5G              |
| ------------ | ----------------------------- |
| 设备代号         | `sunstone`，统一设备树为 `stone`     |
| SoC          | Snapdragon 4 Gen 1（SM4375）    |
| CPU          | 2× Cortex-A78 + 6× Cortex-A55 |
| GPU          | Adreno 619                    |
| 内核           | Qualcomm Android 5.4 系列       |
| 内存 / 存储      | 你的配置为 8GB / 128GB             |
| 原厂 Android   | Android 12                    |
| Treble       | 是                             |
| crDroid      | 官方支持                          |
| Ubuntu Touch | 未查到该型号的现成官方移植                 |
| Droidian     | 未查到该型号的现成官方移植                 |

规格和设备树信息可以在小米官方与 crDroid 源码中交叉验证。

[image](https://www.google.com/s2/favicons?domain=https://www.mi.com\&sz=32)

Xiaomi UK+2



## 一、crDroid 的官方支持比你想象的还完善

你记得没错。我在 crDroid 官方下载站查到了两个相关设备条目：

[image](https://www.google.com/s2/favicons?domain=https://crdroid.net\&sz=32)

[crDroid 12 — gemstone](https://crdroid.net/gemstone/12?utm_source=chatgpt.com)

Redmi Note 12 5G / POCO X5，Android 16 分支。官方页面列出的版本是 12.12，2026 年 9 月构建。

[image](https://www.google.com/s2/favicons?domain=https://crdroid.net\&sz=32)

[crDroid 官方设备列表](https://crdroid.net/downloads?utm_source=chatgpt.com)

还列有旧的 `stone` 统一设备支持，包含 Android 14 和 Android 15 分支。

截至 2026 年 11 月 8 日，官方下载列表显示 `gemstone` 最近一次构建为 11 月 7 日；`stone` 旧分支的最后构建是 2025 年 10 月 10 日。

[image](https://www.google.com/s2/favicons?domain=https://crdroid.net\&sz=32)

Download crDroid for supported devices+1



这很重要：你有的不只是一套能启动的第三方 ROM，而是一套持续维护、公开设备配置和内核源码的 Android 移植基础。

我没有确认到 Redmi Note 12 5G 出现在 LineageOS 官方支持列表中，所以不能把 crDroid 仓库里 `lineage_stone.mk` 的存在当作 LineageOS 官方支持的证据。

不过对 Halium 来说，这并不重要。成熟的 crDroid 设备树一样可以作为起点。

## 二、找到了完整的设备树、内核和 Vendor 仓库

这部分比是否有 LineageOS 官方支持更有意义。

[android_device_xiaomi_stone](https://github.com/crdroidandroid/android_device_xiaomi_stone?utm_source=chatgpt.com)

统一设备树，包含 BoardConfig、分区定义、HAL manifest、设备初始化和相关配置。

[android_kernel_xiaomi_stone](https://github.com/crdroidandroid/android_kernel_xiaomi_stone?utm_source=chatgpt.com)

Android 5.4 内核源码。你可以基于这里的配置制作 Halium kernel patch。

[proprietary_vendor_xiaomi-stone](https://github.com/crdroidandroid/proprietary_vendor_xiaomi-stone?utm_source=chatgpt.com)

设备专属 vendor 组件仓库，对研究硬件服务及 Halium 依赖很有帮助。

我还检查了 crDroid 的 `BoardConfig.mk`，发现了几项非常关键的细节：

| 配置            | 实际值                      | 对移植的影响              |
| ------------- | ------------------------ | ------------------- |
| Kernel        | 5.4                      | 需要移植 Halium 的内核配置   |
| Defconfig     | `moonstone_defconfig`    | 有明确的构建入口            |
| Kernel source | `kernel/xiaomi/sm6375`   | 使用统一 Qualcomm 内核    |
| Boot header   | v3                       | 需要正确封装启动镜像          |
| 分区            | A/B + Dynamic Partitions | 刷机流程不能按传统单分区设备处理    |
| Vendor boot   | 独立存在                     | 需要保留匹配的模块及启动配置      |
| AVB           | 已启用相应构建配置                | 必须处理启动验证            |
| Wi-Fi 驱动      | `qca_cld3`               | 可以优先尝试普通 Linux 网络接口 |

这些不是推测，而是现有 crDroid 设备树明确写出的配置。

[image](https://www.google.com/s2/favicons?domain=https://raw.githubusercontent.com\&sz=32)

GitHub+1



这使得 AI Agent 可以从一开始就准确分析内核、分区和构建方式，而不必从零逆向硬件。

不过，它也意味着一个限制：不能简单使用普通的 `fastboot flash boot` 操作，就认为完成了 Droidian 安装。

正确做法是先确认当前活动 slot、`vendor_boot`、DTB/DTBO 和内核模块的关系，确保能够恢复现有的 crDroid 环境。

## 三、为什么它可能比 Galaxy Tab S6 Lite 更容易？

最大的区别不是 CPU 性能，而是 GPU。

[Redmi Note 12 5G | Xiaomi Nederland | Beste & nieuwste prijs om te kopen](https://images.openai.com/static-rsc-4/XVW-C2R9Fw-310bY4a8XnvvtWZ5vjLNVDsx3ilsQxc9YFqymyfEwVLs7xcpXOTuucTVEwnyb9gIMx7KTuq2YjDDLegFbBQjYZy6GgtmFq8oNFNCTWZGUX4r3a6Kdm_wpO2ssg8rwWnmmj4dWQsoPBEqek3lSa3-XerA4lDNRhZY?purpose=inline)

Redmi Note 12 5G

Adreno 619 · Qualcomm

[Buy the Samsung Galaxy S6 Lite  (WiFi ) with S-Pen  (2024 Model) 10.4" Tablet ... ( SM-P620NZAEXNZ ) online - PBTech.co.nz](https://images.openai.com/static-rsc-4/8334Lm8lQStyV6NbCPPuC2QSoLCEkihbkqPM75d2ewp_Vbt6S32pb5gbQAlI1J0-88swG4cBW1klEm6AUWJiYrPyqdskZ2QGvA1Spd678SfPORz-QswnumPzpgLq2CSdrhdRoYeh_iplm2ke0dlF9etbDEw1ddUGFpFOul6ybuA?purpose=inline)

Tab S6 Lite 2024

Mali-G68 · Samsung

对于 Droidian，Redmi 的优势主要有三个。

1\. Qualcomm 图形栈有比较成熟的 Halium 移植经验。

Droidian 和 Ubuntu Touch 社区长期适配过大量 Adreno 设备。Android HWC、EGL、libhybris 等组件都具有可以参考的现成实现。

但不能把 Adreno 619 的驱动与其他 Snapdragon 机型完全等同。

2\. Adreno 619 有开源 Mesa Freedreno/Turnip 生态。

这使得未来尝试原生 Linux 图形栈具有吸引力。不过，旧 Android 5.4 内核是否具备对应的 DRM/MSM、KGSL 兼容条件，仍然需要检查。

不能因为 Mesa 支持 Adreno 619，就认定目前的 crDroid 内核可以直接运行 KWin。

3\. 手机屏幕与 Phosh 更匹配。

这一点和你之前的平板判断正好相反。

Tab S6 Lite 的硬件形态更适合真正的桌面 Linux；Redmi Note 12 的硬件生态和屏幕形态却更适合现阶段以 Phosh 为中心的 Droidian。

所以它比较适合首先证明 Halium 的图形、触摸和硬件加速整条路径能够工作。

## 四、不过还有一个重要障碍：Android 版本太新

这里需要谨慎。

Redmi Note 12 5G 原厂搭载 Android 12，而目前 crDroid 已发展到 Android 16 分支。

UBports 官方移植文档列出了不同 Halium 版本所对应的 Android 系统基线，当前文档中的表格列到 Halium 13（Android 13）。

[image](https://www.google.com/s2/favicons?domain=https://docs.ubports.com\&sz=32)

UBports documentation



因此，不能因为你当前安装了 crDroid 12，就直接使用它的 Android 16 运行环境构建 Ubuntu Touch。

有两个不同的概念：

- Android 16 的 crDroid 用户空间： 可以被新的 Android ROM 正常使用。
- Halium 兼容的 Android vendor/HAL 环境： 需要有与 Halium GSI 对应的基线。

它们不一定能直接搭配。

我更倾向于从这台设备的 Android 12 或 Android 13 vendor 基线开始，特别是如果你可以找到旧版本 crDroid 或其他 Android 13 ROM 的完整构建源码。

这可能比直接修改最新的 Android 16 分支更省事。

具体能否复用，需要先核对设备上实际使用的 vendor API，而不是只看 ROM 的 Android 版本。

## 五、Droidian 和 Ubuntu Touch，哪个更容易？

从你这个项目的目标来看，我更推荐先做 Droidian，然后再移植 Ubuntu Touch。

| 比较项目              | Droidian        | Ubuntu Touch      |
| ----------------- | --------------- | ----------------- |
| 共享 Halium 技术      | 是               | 是                 |
| 复用 Android vendor | 是               | 是                 |
| 常规用户空间            | Debian          | Ubuntu Touch      |
| 默认界面              | Phosh           | Lomiri            |
| 软件包生态             | Debian APT      | Ubuntu Touch 生态   |
| 第一阶段目标            | Shell、Phosh、SSH | Shell、Lomiri、系统服务 |
| 适配完成后共享内核成果       | 可以              | 可以                |

UBports 官方确认 Ubuntu Touch 构建在 Halium GSI 基础上，设备移植主要由系统 rootfs、Halium 和厂商驱动三部分组成。

[image](https://www.google.com/s2/favicons?domain=https://docs.ubports.com\&sz=32)

UBports 文档



因此，如果你先完成 Droidian 所需要的内核改动、vendor 兼容和基本硬件服务，这部分成果很可能能够帮助 Ubuntu Touch 移植。

但并不是直接换一个 rootfs 就能完成全部工作。

尤其是 Lomiri、音频服务、电源管理、Ubuntu Touch 的设备配置和 OTA 安装流程，仍有独立的适配内容。

我会将二者的开发顺序设计为：

crDroid / Android 12–13 Vendor 基线

Halium Kernel + Android Container

Droidian

Debian + Phosh

先移植

Ubuntu Touch

Ubuntu + Lomiri

第二阶段

## 六、我对这台机器的移植工时估算

基于现在已经确认的设备树和内核资源，我会这样安排人工开发预算。

| 目标                       | 估计人工工时     |
| ------------------------ | ---------- |
| 核实 vendor 基线、分区、构建环境     | 2–4 小时     |
| 编译及适配 Halium kernel      | 3–8 小时     |
| 启动 Droidian Debian Shell | 4–12 小时    |
| Phosh 显示、触摸、GPU 加速       | 6–20 小时    |
| Wi-Fi、音频、充电、基础休眠         | 8–24 小时    |
| Ubuntu Touch 初步启动        | 额外 6–20 小时 |

这里假设 Halium 对所选择的 vendor 基线能够兼容，并且不需要你自行开发新的 HWC 或 libhybris 适配。如果遇到这种上游兼容性问题，时间可能增加到数周。

对你来说，我认为合理的首个目标是：

累计 15–25 小时人工工作量以内，让 Redmi Note 12 5G 启动 Droidian、进入 Phosh，并验证触摸与 GPU 加速。

这是一个值得挑战的目标，并不是保证可以完成的时间。

## 七、你现在可以先在 crDroid 上做什么？

在决定安装任何东西之前，建议先运行以下只读命令。

Redmi Note 12 Droidian 移植预检

&#x20;复制

adb shell getprop ro.product.device\
adb shell getprop ro.product.vendor.device\
adb shell getprop ro.vendor.build.version.sdk\
adb shell getprop ro.vendor.api_level\
adb shell getprop ro.treble.enabled\
adb shell getprop ro.boot.slot_suffix\
adb shell getprop ro.boot.dynamic_partitions\
adb shell uname -a\
adb shell ls -l /dev/kgsl-3d0 /dev/dri /dev/graphics\
adb shell cat /proc/bus/input/devices

重点看 `ro.vendor.build.version.sdk`、内核版本，以及 `/dev/kgsl-3d0` 和 `/dev/dri` 的情况。个别路径不存在或权限不足不代表 GPU 无法工作。

另外，因为你已经使用 crDroid，应该先保存当前版本对应的 `boot.img`、`vendor_boot.img`、`dtbo.img` 和安装包，并确认 A/B slot 与恢复流程。不要直接拿别的版本的 GSI 或 boot image 覆盖正在使用的系统。

## 八、两台设备放在一起，我会怎么选？

| 维度          | Redmi Note 12 5G | Tab S6 Lite 2024 |
| ----------- | ---------------- | ---------------- |
| 成熟第三方 ROM   | 很好               | 很好               |
| 内核          | 5.4              | 5.10             |
| GPU         | Adreno 619       | Mali-G68         |
| 内存          | 8GB              | 4GB              |
| Halium 社区参考 | Qualcomm 更丰富     | Exynos 相对有限      |
| Phosh 使用体验  | 更适合              | 可以，但需适配大屏        |
| KDE 桌面使用价值  | 低                | 高                |
| 电磁笔需求       | 无                | S Pen            |
| 初次移植风险      | 相对较低             | 相对较高             |
| 值得长期投入      | 中高               | 高                |

如果目的是第一次完整走通 Halium → Droidian → Ubuntu Touch 这条移植工作流，我选 Redmi Note 12 5G。

它的优势是 Qualcomm 平台、成熟的源码基础、8GB 内存，以及你已经验证过的 crDroid 环境。即使最后只得到一个能运行 Phosh 的实验机，这次移植也能帮助你积累非常有价值的 Halium 工具链和设备适配经验。

如果目的是获得一台真正值得长期使用的 Linux 设备，我仍然更看好 Galaxy Tab S6 Lite 2024。

最合理的做法可能是拿 Redmi Note 12 作为第一台实验机，验证 Agent 能否自动处理 70%–80% 的重复工作；随后将成功的配置、脚本和排错经验复用到 Galaxy Tab S6 Lite 上。

还有一个值得强调的结果：目前没有确认到 Redmi Note 12 5G 的现成 Droidian 或 Ubuntu Touch 官方移植。这意味着如果你真的完成了移植，它可能不只是一次个人实验，还能为 `sunstone` 及共享 `stone` 设备树的平台社区增加一个新的 Linux 系统选择。