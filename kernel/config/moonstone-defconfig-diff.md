# 运行配置相对 moonstone_defconfig

运行配置：`kernel/config/sunstone-5.4.302-running.config`，来自这台 sunstone 上的 `5.4.302-qgki-g06497b244a0e`。

defconfig：`crdroidandroid/android_kernel_xiaomi_stone` 分支 `16.0`，提交 `06497b244a0e`。内核版本字符串里的 `g06497b244a0e` 就是这个提交。defconfig 路径是 `arch/arm64/configs/moonstone_defconfig`。

用主机 gcc 把 defconfig 展开后，和运行配置相比只有编译器身份不同：运行内核是 Android clang 21.0.0（`r563880c`）加上 LTO、CFI、shadow call stack 和 RELR；用 gcc 展开时这些 clang 选项不会出现。功能选项没有另一套差异。

因此 Halium 要改的开关并不是这份运行配置相对 defconfig 漏掉的东西，而是 defconfig 自己就关着的东西。

命名空间核对：

| 选项 | 源码 | 运行配置 |
| --- | --- | --- |
| `CONFIG_UTS_NS` | 存在，默认打开 | 打开 |
| `CONFIG_NET_NS` | 存在，默认打开 | 打开 |
| `CONFIG_PID_NS` | 存在，默认打开，但 defconfig 把它关掉了 | 关闭 |
| `CONFIG_USER_NS` | 存在，默认关闭 | 关闭 |
| `CONFIG_IPC_NS` | 存在，依赖 `CONFIG_SYSVIPC` 或 `CONFIG_POSIX_MQUEUE` | 配置里没有这一行，因为 `CONFIG_SYSVIPC` 和 `CONFIG_POSIX_MQUEUE` 都关着，选项被隐藏 |
| mount namespace | 没有单独的 `CONFIG_MNT_NS`。`CONFIG_NAMESPACES` 打开时就有 `CLONE_NEWNS` | `CONFIG_NAMESPACES` 已打开 |

`kernel/config/halium-sunstone.fragment` 打开 PID、USER、IPC namespace，以及 VT、devtmpfs 和 `FHANDLE`。IPC namespace 通过先打开 `CONFIG_SYSVIPC` 才写得进去。mount namespace 不再加选项。
