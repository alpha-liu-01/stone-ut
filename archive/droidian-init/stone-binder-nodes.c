/* Add binder, hwbinder and vndbinder to a mounted binderfs. No libc. */

struct binderfs_device {
    char name[256];
    unsigned int major;
    unsigned int minor;
};

static long syscall4(long nr, long a, long b, long c, long d)
{
    register long x0 __asm__("x0") = a;
    register long x1 __asm__("x1") = b;
    register long x2 __asm__("x2") = c;
    register long x3 __asm__("x3") = d;
    register long x8 __asm__("x8") = nr;

    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x3), "r"(x8) : "memory");
    return x0;
}

static long syscall3(long nr, long a, long b, long c)
{
    register long x0 __asm__("x0") = a;
    register long x1 __asm__("x1") = b;
    register long x2 __asm__("x2") = c;
    register long x8 __asm__("x8") = nr;

    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x8) : "memory");
    return x0;
}

static void add_device(int ctl, const char *name)
{
    struct binderfs_device dev;
    unsigned int i;

    for (i = 0; i < sizeof(dev); i++)
        ((char *)&dev)[i] = 0;
    for (i = 0; name[i] && i < sizeof(dev.name) - 1; i++)
        dev.name[i] = name[i];
    /* BINDER_CTL_ADD, sizeof(struct binderfs_device) == 264 */
    syscall3(29, ctl, 0xc1086201L, (long)&dev);
}

void _start(void)
{
    static const char path[] = "/dev/binderfs/binder-control";
    long ctl;

    ctl = syscall4(56, -100, (long)path, 2, 0);
    if (ctl >= 0) {
        add_device((int)ctl, "binder");
        add_device((int)ctl, "hwbinder");
        add_device((int)ctl, "vndbinder");
        syscall3(57, ctl, 0, 0);
    }
    syscall3(93, 0, 0, 0);
    for (;;)
        ;
}
