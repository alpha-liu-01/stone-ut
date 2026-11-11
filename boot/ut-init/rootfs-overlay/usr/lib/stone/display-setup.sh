#!/bin/sh
# Smooth 120 Hz on stone; runs before lightdm (stone-display-setup.service).
#
# 1. lomiri-system-compositor (Mir's android2 platform, real_hwc2_wrapper.cpp,
#    RealHwc2Wrapper::set()) blocks after every HWC present until the
#    *previous* frame's present fence signals ("FIXME: is needed at all?").
#    Qualcomm's composer signals it a vsync late, so every frame costs two
#    vsyncs: 60 Hz on the 120 Hz panel. A copy of graphics-android2.so.16 with
#    that sync_wait() timeout changed from -1 to 0 (one instruction) is
#    bind-mounted over the original. Back pressure still comes from Mir's
#    three framebuffers, each guarded by the present fence of the frame after
#    it. Only done when the installed file is the exact build the patch was
#    made for; any other build (package update) is left alone and logged.
# 2. GPU: msm-adreno-tz sees the GPU ~60% busy while Lomiri scrolls (CPU, GPU
#    and the system compositor work one after another) and keeps it at its
#    lowest clock, 266 MHz, which takes ~16 ms per frame. mod_percent=200 makes
#    it count busy time double, so it ramps under that load and still drops
#    back when idle. (On Android, the QTI perf HAL raises the floors on touch.)
# 3. Refresh rate: if /etc/stone/refresh-rate says 60, switch the panel to its
#    60 Hz mode before the system compositor starts (Mir reads the rate once,
#    at start, and paces all clients by it). Default: 120 Hz.
# 4. System Settings > Brightness gets a "Refresh rate" section: a copy of the
#    stock page with a Loader for /usr/share/stone/settings/RefreshRate.qml is
#    bind-mounted over it, only when the stock page is the exact version the
#    copy was made from (otherwise the page is left alone and logged).
LIB=/usr/lib/aarch64-linux-gnu/mir1/server-platform/graphics-android2.so.16
STOCK_SHA=146cf674cde6fe8590f8150b0f7120a17083e7ef32724be38f7752b30dbdb18b
PATCHED_SHA=bc58bdfd7c258787d2291f489d08dfa7fa973356283147cdabcbf6c70e07347d
PATCH_OFFSET=247860          # 0x3c834: mov w1,#-1 (01 00 80 12) -> mov w1,#0 (01 00 80 52)
RUN=/run/stone-display
GPU=/sys/class/kgsl/kgsl-3d0/devfreq
RATE_FILE=/etc/stone/refresh-rate
PAGE=/usr/share/lomiri-system-settings/qml-plugins/brightness/PageComponent.qml
PAGE_STOCK_SHA=c7bd6ca81f0743aea02538ff33ba9b2ec6b25db5cc96d5b565b3485312404c42
PAGE_COPY=/usr/share/stone/settings/brightness-PageComponent.qml

log() { echo "stone-display-setup: $*"; }

patch_compositor() {
    if mountpoint -q "$LIB"; then
        log "compositor: already patched"
        return
    fi
    sum=$(sha256sum < "$LIB" | cut -d' ' -f1)
    if [ "$sum" != "$STOCK_SHA" ]; then
        log "compositor: $LIB is not the build the patch was made for ($sum); left alone, 60 Hz frame pacing"
        return
    fi
    mkdir -p "$RUN"
    cp "$LIB" "$RUN/graphics-android2.so.16"
    printf '\001\000\200\122' | dd of="$RUN/graphics-android2.so.16" bs=1 seek=$PATCH_OFFSET conv=notrunc status=none
    if [ "$(sha256sum < "$RUN/graphics-android2.so.16" | cut -d' ' -f1)" != "$PATCHED_SHA" ]; then
        log "compositor: patched copy has the wrong checksum; not used"
        rm -f "$RUN/graphics-android2.so.16"
        return
    fi
    mount --bind "$RUN/graphics-android2.so.16" "$LIB" && log "compositor: present-fence wait removed"
}

gpu_governor() {
    i=0
    while [ ! -w "$GPU/mod_percent" ] && [ $i -lt 50 ]; do sleep 0.2; i=$((i + 1)); done
    if echo 200 > "$GPU/mod_percent" 2>/dev/null; then
        log "gpu: msm-adreno-tz mod_percent=200"
    else
        log "gpu: $GPU/mod_percent not available"
    fi
}

refresh_rate() {
    rate=$(cat "$RATE_FILE" 2>/dev/null)
    [ "$rate" = 60 ] || return 0
    # The composer comes up with the Android container; give it 30 s.
    i=0
    while [ $i -lt 60 ]; do
        if python3 -I /usr/lib/stone/display-mode.py set 60 >/dev/null 2>&1; then
            log "refresh rate: 60 Hz ($RATE_FILE)"
            return
        fi
        sleep 0.5; i=$((i + 1))
    done
    log "refresh rate: display config service not available; staying at 120 Hz"
}

settings_page() {
    if mountpoint -q "$PAGE"; then
        log "settings: brightness page already replaced"
        return
    fi
    sum=$(sha256sum < "$PAGE" | cut -d' ' -f1)
    if [ "$sum" != "$PAGE_STOCK_SHA" ]; then
        log "settings: $PAGE is not the version the copy was made from ($sum); no refresh rate section"
        return
    fi
    mount --bind "$PAGE_COPY" "$PAGE" && log "settings: refresh rate section added to Brightness"
}

patch_compositor
gpu_governor
refresh_rate
settings_page
exit 0
