/* Reboot into the bootloader. No libc. */
void _start(void)
{
    register long x0 __asm__("x0") = 0xfee1dead;
    register long x1 __asm__("x1") = 0x28121969;
    register long x2 __asm__("x2") = 0xA1B2C3D4;
    register long x3 __asm__("x3");
    register long x8 __asm__("x8") = 142;
    static const char cmd[] = "bootloader";

    x3 = (long)cmd;
    __asm__ volatile("svc #0" : : "r"(x0), "r"(x1), "r"(x2), "r"(x3), "r"(x8) : "memory");
    for (;;)
        ;
}
