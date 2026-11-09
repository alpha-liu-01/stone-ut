/* Halium 12 has no libapexsupport. Vendor libbinder only needs the four
 * LLNDK symbols. These binaries are not inside an APEX, so report that. */
struct AApexInfo;

int AApexInfo_create(struct AApexInfo **info) {
    if (info) {
        *info = 0;
    }
    return 1; /* AAPEXINFO_NO_APEX */
}

void AApexInfo_destroy(struct AApexInfo *info) {
    (void)info;
}

const char *AApexInfo_getName(const struct AApexInfo *info) {
    (void)info;
    return "";
}

long long AApexInfo_getVersion(const struct AApexInfo *info) {
    (void)info;
    return 0;
}

__attribute__((used, section(".note.android.ident"), aligned(4)))
static const struct {
    int namesz;
    int descsz;
    int type;
    char name[8];
    int api;
} android_note = {
    8,
    4,
    1,
    "Android",
    35,
};
