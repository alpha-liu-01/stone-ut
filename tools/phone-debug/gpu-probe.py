#!/usr/bin/env python3
"""Headless GPU probes for the phone (no eglinfo/glxinfo/vulkaninfo there).

  python3 gpu-probe.py egl [es2|es3|gl]
      EGL via glvnd (libEGL.so.1) on the platform in $EGL_PLATFORM, a 64x64
      pbuffer, a context of the requested API; prints the EGL and GL
      strings, the extension count, and draws: glClear to a colour plus
      glReadPixels to check the GPU really executed it, then a timed loop of
      full-pbuffer clears + glFinish.
        EGL_PLATFORM=null      libhybris (Adreno) without a window system
        EGL_PLATFORM=surfaceless __EGL_VENDOR_LIBRARY_FILENAMES=.../50_mesa.json
                               Mesa (optionally MESA_LOADER_DRIVER_OVERRIDE)
  python3 gpu-probe.py vulkan
      Instance + physical devices via libvulkan.so.1 (libvulkan1-hybris
      here): name, type, API/driver version, vendor/device id, the number
      of device extensions and a few notable ones, then creates a device and
      a queue to check that works.
"""
import ctypes
import os
import sys
import time

c_p = ctypes.c_void_p


def egl_probe(api):
    egl = ctypes.CDLL("libEGL.so.1")
    egl.eglGetDisplay.restype = c_p
    egl.eglGetDisplay.argtypes = [c_p]
    egl.eglQueryString.restype = ctypes.c_char_p
    egl.eglQueryString.argtypes = [c_p, ctypes.c_int]
    egl.eglInitialize.argtypes = [c_p, c_p, c_p]
    egl.eglChooseConfig.argtypes = [c_p, c_p, c_p, ctypes.c_int, c_p]
    egl.eglCreatePbufferSurface.restype = c_p
    egl.eglCreatePbufferSurface.argtypes = [c_p, c_p, c_p]
    egl.eglCreateContext.restype = c_p
    egl.eglCreateContext.argtypes = [c_p, c_p, c_p, c_p]
    egl.eglMakeCurrent.argtypes = [c_p, c_p, c_p, c_p]
    egl.eglGetProcAddress.restype = c_p
    egl.eglGetProcAddress.argtypes = [ctypes.c_char_p]

    d = egl.eglGetDisplay(None)
    maj, mnr = ctypes.c_int(), ctypes.c_int()
    if not d or not egl.eglInitialize(d, ctypes.byref(maj), ctypes.byref(mnr)):
        print("eglInitialize failed, error 0x%x" % egl.eglGetError())
        return 1
    for name, k in (("EGL_VENDOR", 0x3053), ("EGL_VERSION", 0x3054), ("EGL_CLIENT_APIS", 0x308D)):
        print("%-16s %s" % (name, (egl.eglQueryString(d, k) or b"").decode()))
    ext = (egl.eglQueryString(d, 0x3055) or b"").decode().split()
    print("%-16s %d extensions" % ("EGL_EXTENSIONS", len(ext)))

    EGL_OPENGL_ES_API, EGL_OPENGL_API = 0x30A0, 0x30A2
    renderable = {"es2": 0x4, "es3": 0x40, "gl": 0x8}[api]
    egl.eglBindAPI(EGL_OPENGL_API if api == "gl" else EGL_OPENGL_ES_API)
    attrs = (ctypes.c_int * 15)(0x3033, 0x1, 0x3040, renderable, 0x3024, 8, 0x3023, 8, 0x3022, 8, 0x3021, 8, 0x3038, 0, 0)
    attrs[12] = 0x3038
    cfg = c_p()
    n = ctypes.c_int()
    if not egl.eglChooseConfig(d, attrs, ctypes.byref(cfg), 1, ctypes.byref(n)) or n.value < 1:
        print("no pbuffer config for %s, error 0x%x" % (api, egl.eglGetError()))
        return 1
    surf = egl.eglCreatePbufferSurface(d, cfg, (ctypes.c_int * 5)(0x3057, 64, 0x3056, 64, 0x3038))
    cattrs = (ctypes.c_int * 3)(0x3098, 3 if api == "es3" else 2, 0x3038)
    ctx = egl.eglCreateContext(d, cfg, None, None if api == "gl" else cattrs)
    if not surf or not ctx or not egl.eglMakeCurrent(d, surf, surf, ctx):
        print("context/surface failed, error 0x%x" % egl.eglGetError())
        return 1

    def gl(name, restype, *argtypes):
        f = ctypes.CFUNCTYPE(restype, *argtypes)(egl.eglGetProcAddress(name.encode()))
        return f
    glGetString = gl("glGetString", ctypes.c_char_p, ctypes.c_uint)
    for name, k in (("GL_VENDOR", 0x1F00), ("GL_RENDERER", 0x1F01), ("GL_VERSION", 0x1F02), ("GL_SHADING_LANGUAGE", 0x8B8C)):
        print("%-16s %s" % (name, (glGetString(k) or b"").decode()))
    glext = (glGetString(0x1F03) or b"").decode().split()
    print("%-16s %d extensions" % ("GL_EXTENSIONS", len(glext)))
    glClearColor = gl("glClearColor", None, ctypes.c_float, ctypes.c_float, ctypes.c_float, ctypes.c_float)
    glClear = gl("glClear", None, ctypes.c_uint)
    glFinish = gl("glFinish", None)
    glReadPixels = gl("glReadPixels", None, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint, c_p)
    glClearColor(0.25, 0.5, 0.75, 1.0)
    glClear(0x4000)
    px = (ctypes.c_ubyte * 4)()
    glReadPixels(32, 32, 1, 1, 0x1908, 0x1401, px)
    print("%-16s %s (expected about [64, 128, 191, 255])" % ("readback", list(px)))
    t = time.monotonic()
    for i in range(2000):
        glClearColor(i % 2, 0, 0, 1)
        glClear(0x4000)
    glFinish()
    print("%-16s 2000 clears + finish in %.3f s" % ("timing", time.monotonic() - t))
    return 0


class VkAppInfo(ctypes.Structure):
    _fields_ = [("sType", ctypes.c_int), ("pNext", c_p), ("pApplicationName", ctypes.c_char_p),
                ("applicationVersion", ctypes.c_uint32), ("pEngineName", ctypes.c_char_p),
                ("engineVersion", ctypes.c_uint32), ("apiVersion", ctypes.c_uint32)]


class VkInstanceCreateInfo(ctypes.Structure):
    _fields_ = [("sType", ctypes.c_int), ("pNext", c_p), ("flags", ctypes.c_uint32),
                ("pApplicationInfo", ctypes.POINTER(VkAppInfo)), ("enabledLayerCount", ctypes.c_uint32),
                ("ppEnabledLayerNames", c_p), ("enabledExtensionCount", ctypes.c_uint32),
                ("ppEnabledExtensionNames", c_p)]


class VkPhysicalDeviceProperties(ctypes.Structure):
    _fields_ = [("apiVersion", ctypes.c_uint32), ("driverVersion", ctypes.c_uint32),
                ("vendorID", ctypes.c_uint32), ("deviceID", ctypes.c_uint32),
                ("deviceType", ctypes.c_int), ("deviceName", ctypes.c_char * 256),
                ("pipelineCacheUUID", ctypes.c_ubyte * 16), ("rest", ctypes.c_ubyte * 1024)]


class VkExtensionProperties(ctypes.Structure):
    _fields_ = [("extensionName", ctypes.c_char * 256), ("specVersion", ctypes.c_uint32)]


class VkQueueCI(ctypes.Structure):
    _fields_ = [("sType", ctypes.c_int), ("pNext", c_p), ("flags", ctypes.c_uint32),
                ("queueFamilyIndex", ctypes.c_uint32), ("queueCount", ctypes.c_uint32),
                ("pQueuePriorities", ctypes.POINTER(ctypes.c_float))]


class VkDeviceCI(ctypes.Structure):
    _fields_ = [("sType", ctypes.c_int), ("pNext", c_p), ("flags", ctypes.c_uint32),
                ("queueCreateInfoCount", ctypes.c_uint32), ("pQueueCreateInfos", ctypes.POINTER(VkQueueCI)),
                ("enabledLayerCount", ctypes.c_uint32), ("ppEnabledLayerNames", c_p),
                ("enabledExtensionCount", ctypes.c_uint32), ("ppEnabledExtensionNames", c_p),
                ("pEnabledFeatures", c_p)]


def ver(v):
    return "%d.%d.%d" % (v >> 22, (v >> 12) & 0x3ff, v & 0xfff)


def vulkan_probe():
    vk = ctypes.CDLL("libvulkan.so.1")
    n = ctypes.c_uint32()
    vk.vkEnumerateInstanceExtensionProperties(None, ctypes.byref(n), None)
    iexts = (VkExtensionProperties * n.value)()
    vk.vkEnumerateInstanceExtensionProperties(None, ctypes.byref(n), iexts)
    print("instance extensions (%d): %s" % (n.value, " ".join(e.extensionName.decode() for e in iexts)))
    app = VkAppInfo(0, None, b"gpu-probe", 1, b"none", 1, (1 << 22) | (1 << 12))
    ci = VkInstanceCreateInfo(1, None, 0, ctypes.pointer(app), 0, None, 0, None)
    inst = c_p()
    r = vk.vkCreateInstance(ctypes.byref(ci), None, ctypes.byref(inst))
    print("vkCreateInstance:", r)
    if r != 0:
        return 1
    vk.vkEnumeratePhysicalDevices(inst, ctypes.byref(n), None)
    devs = (c_p * n.value)()
    vk.vkEnumeratePhysicalDevices(inst, ctypes.byref(n), devs)
    print("physical devices:", n.value)
    types = {0: "other", 1: "integrated GPU", 2: "discrete GPU", 3: "virtual GPU", 4: "CPU"}
    for pd in devs:
        p = VkPhysicalDeviceProperties()
        vk.vkGetPhysicalDeviceProperties(c_p(pd), ctypes.byref(p))
        print("  %s (%s), API %s, driver 0x%x, vendor 0x%x device 0x%x" % (
            p.deviceName.decode(), types.get(p.deviceType, p.deviceType), ver(p.apiVersion),
            p.driverVersion, p.vendorID, p.deviceID))
        m = ctypes.c_uint32()
        vk.vkEnumerateDeviceExtensionProperties(c_p(pd), None, ctypes.byref(m), None)
        dexts = (VkExtensionProperties * m.value)()
        vk.vkEnumerateDeviceExtensionProperties(c_p(pd), None, ctypes.byref(m), dexts)
        names = [e.extensionName.decode() for e in dexts]
        notable = [x for x in names if any(k in x for k in ("swapchain", "external_memory", "android", "dynamic_rendering", "timeline", "maintenance4", "synchronization2"))]
        print("  device extensions: %d; %s" % (m.value, " ".join(notable)))
        prio = (ctypes.c_float * 1)(1.0)
        q = VkQueueCI(2, None, 0, 0, 1, prio)
        dci = VkDeviceCI(3, None, 0, 1, ctypes.pointer(q), 0, None, 0, None, None)
        dev = c_p()
        r = vk.vkCreateDevice(c_p(pd), ctypes.byref(dci), None, ctypes.byref(dev))
        print("  vkCreateDevice:", r)
        if r == 0:
            queue = c_p()
            vk.vkGetDeviceQueue(dev, 0, 0, ctypes.byref(queue))
            print("  queue:", hex(queue.value or 0), " vkDeviceWaitIdle:", vk.vkDeviceWaitIdle(dev))
            vk.vkDestroyDevice(dev, None)
    vk.vkDestroyInstance(inst, None)
    return 0


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "egl"
    sys.exit(vulkan_probe() if what == "vulkan" else egl_probe(sys.argv[2] if len(sys.argv) > 2 else "es3"))
