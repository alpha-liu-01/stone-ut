# GasTube crashes a few seconds after launch: hard-coded libhybris offsets

Seen on: Xiaomi Redmi Note 12 5G (stone), Ubuntu Touch 24.04-2.x, Halium 14, GasTube `gastube.alphaliu01` 0.9.5 from the OpenStore. The same build works on a OnePlus 6 and a Nothing Phone (1).

## Summary

GasTube's `linux/ubuntu_touch_present.cc` edits private fields of libhybris' `WaylandNativeWindow` at fixed offsets: the swap-queue `std::deque` at `+0x138`, `m_lastBuffer` at `+0x198` and the buffer list at `+0xd8`. In the libhybris build on this phone those members are elsewhere. For example, the deque is at `+0x108`, so the app's `+0x138` is the deque's *finish* iterator. `prepare_swap_queue()` / `pop_swap_queue()` then rewrite the wrong words, and the next `finishSwap()` inside libhybris dereferences garbage: **SIGSEGV**.

This libhybris build also already checks for an empty queue in `finishSwap()`, which is the libhybris bug the workaround exists for. On this build the workaround is not needed, and it is what crashes.

It is not specific to this device. libhybris is the stock UBports package; nothing in this port changes it. Any device that gets this libhybris build should crash the same way.

## The crash

From the app's own fatal-signal handler (journal, `journalctl --user`):

```
gastube: frame n=43 ...
gastube: mediahub window-destroy uuid=
gastube: fatal SIGSEGV
gastube(_Z15on_fatal_signali+0xc8)[0x4087a4]
linux-vdso.so.1(__kernel_rt_sigreturn+0x0)
/usr/lib/aarch64-linux-gnu/libhybris//eglplatform_wayland.so(_ZN19WaylandNativeWindow10finishSwapEv+0x88)
/lib/aarch64-linux-gnu/libEGL_libhybris.so.0(+0x4e90)
gastube(gastube_gated_egl_swap+0x120)
libflutter_linux_gtk.so(+0x5011a0)
libglib-2.0.so.0 ... g_main_loop_run
libgtk-3.so.0(gtk_main+0xa4)
gastube(gastube_ubuntu_touch_main+0x9a8)
```

Earlier in the same run:

```
present: eglSwapBuffersWithDamageEXT gated via /lib/aarch64-linux-gnu/libEGL_libhybris.so.0
present: dropped 8 destroyed buffers from the swap queue
```

It crashes the same way on every launch, about 3 s in. systemd: `Main process exited, code=killed, status=11/SEGV`.

The `mediahub window-destroy uuid=` line (empty uuid) just before the crash is not the cause. No media-hub session was ever opened in that run (media-hub-server logged nothing for the app).

## The libhybris build

```
libhybris 0.1.0+git20260624+7079712-0ubports1+0~20261028125224.2+ubports24.04.2~1.gbp37a1b3
/usr/lib/aarch64-linux-gnu/libhybris/eglplatform_wayland.so  SHA256 e35cd4c9953019ba…
```

`WaylandNativeWindow::finishSwap()` is at `0x5190` in that file. The start of the function (aarch64, `x19` = `this`):

```
51fc: ldr  x0, [x19, #280]     ; 0x118 = queue.start._M_cur   -> deque at +0x108
5200: add  x22, x19, #0x118
5204: ldr  x1, [x19, #312]     ; 0x138 = queue.finish._M_cur
5208: cmp  x1, x0
520c: b.eq 5360                ; queue empty -> separate path (the empty() check)
5210: ldr  x1, [x19, #296]     ; 0x128 = queue.start._M_last
5214: add  x21, x19, #0x108
5218: ldr  x20, [x0]           ; *start._M_cur  <- the faulting instruction (+0x88)
...
5234: ldr  w0, [x20, #192]     ; buffer->busy at +0xc0 (unchanged)
```

So in this build:

| Member | `ubuntu_touch_present.cc` assumes | This build |
|---|---|---|
| swap queue `std::deque` | `kNativeQueue = 0x138` | **`0x108`** (`0x138` is its finish iterator) |
| empty-queue handling in `finishSwap()` | none ("does queue.front() without checking empty()") | **checked** (start == finish → own path) |
| buffer `busy` | `+0xc0` | `+0xc0` |
| `m_bufList`, `m_lastBuffer` | `0xd8`, `0x198` | moved as well: `destroyBuffer()` reads `+0xd0` and `+0x160`. Not mapped further. |

With `kNativeQueue = 0x138`, the app reads its "start" from `+0x148` and its "finish" from `+0x168`. `pop_swap_queue()` writes `+0x148…+0x160`, and the "cleared" paths write NULL to `+0x198` and through the stale slot. That is what "dropped 8 destroyed buffers" did right before the crash.

## Why the other phones work (to check)

Most likely they run a libhybris build with the old layout: an older OTA, or another channel. Please compare on them:

```
dpkg-query -W libhybris
sha256sum /usr/lib/aarch64-linux-gnu/libhybris/eglplatform_wayland.so
```

If they show the same version as above and still work, the layout question needs another look. The disassembly above is from the stone phone's file.

## Suggested fix (in GasTube)

1. **Do not touch the queue when libhybris already handles an empty queue.** That is this build and newer, which is the real fix of the bug the workaround targets. Keep the resize serialisation (`g_hybris_window`, the deferred `wl_egl_window_resize`); it does not depend on any offset.
2. **Never write through offsets that have not been validated.** Before using the deque at an assumed offset, check the libstdc++ invariants, and turn the workaround off for the session (one log line) if any fails:
   - `start._M_first <= start._M_cur < start._M_last`;
   - `start._M_last - start._M_first == 0x200` (the chunk size for a pointer element);
   - the same for `finish`;
   - `start._M_node <= finish._M_node`, both inside `[_M_map, _M_map + _M_map_size)`.

   On the stone phone the words the app takes for "start" and "finish" (`+0x148`, `+0x168`) are the real deque's `finish._M_last` and a member after the deque, not an iterator pair. So these checks would very likely catch it. They were not run on the device.
3. Better still, choose the layout by library identity: a small table keyed by the `eglplatform_wayland.so` build ID (`NT_GNU_BUILD_ID`) or its SHA256. Use the workaround only for known old builds, and use nothing for unknown ones.

## How to verify

On an affected phone: launch GasTube, and it crashes within about 3 s. With the workaround disabled (or validated away), the journal should show no `present: dropped … destroyed buffers` / `cleared stale empty swap queue` lines, and the app should keep running through the start-up probe and through entering and leaving fullscreen (the case the workaround was written for).

Logs: `journalctl --user -b | grep -v "dconf will not work"`. The fatal-signal handler prints the backtrace there.
