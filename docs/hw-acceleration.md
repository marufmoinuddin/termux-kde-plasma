# Hardware Acceleration

KDE Plasma on Termux renders through Mesa. Which backend you get depends on the
GPU in your device and the mode `kdestart` is launched with.

## Modes

| Mode      | Stack                                                       | Best for                                       |
|-----------|-------------------------------------------------------------|------------------------------------------------|
| `zink`    | Turnip (Vulkan) + Zink (GL-over-Vulkan)                     | Adreno 6xx / 8xx (Snapdragon 660+) — default   |
| `virgl`   | virglrenderer / ANGLE (GPU passthrough)                     | Mali, Xclipse, and devices where Zink crashes  |
| `software`| llvmpipe (CPU)                                              | Diagnostics only — confirms a driver problem   |

## What the installer does

- `zink`  → installs `mesa-zink-vulkan-icd-freedreno` (combined Adreno stack)
  and sets `GALLIUM_DRIVER=zink` plus the Turnip ICD + `TU_DEBUG=noconform`.
- `virgl` → installs `virglrenderer-android` / `angle-android` and starts a
  `virgl_test_server_android` so GL is virtualized over EGL.
- `software` → forces `LIBGL_ALWAYS_SOFTWARE=1` for troubleshooting.

## Verify acceleration

Inside the Plasma session (Konsole):

```bash
glxinfo -B | grep -iE "renderer string|direct rendering"
```

- `OpenGL renderer string: zink Vulkan ... Turnip Adreno (TM) 650` → GPU active.
- `OpenGL renderer string: llvmpipe` → you're on software rendering.

Or run a quick benchmark:

```bash
glmark2
```

Scores in the hundreds (vs. single/low double digits for llvmpipe) confirm the
GPU is doing the work.

## Black screen on Adreno 6xx/8xx? Use VirGL (important)

If Plasma launches to a **black screen** (even though `glxinfo` shows
`zink ... Adreno` working), the cause is KWin's compositor: it fails to create a
shared OpenGL context through Zink at startup:

```
kwin_scene_opengl: Creating the OpenGL rendering failed:  "Invalid QOpenGLContext::globalShareContext()"
```

This is the known Zink **compositor** fragility on Adreno. The fix that the
installer bakes in is `KWIN_COMPOSE=Q` (XRender/QPainter compositing), and the
**stable daily-driver fallback is VirGL**:

```bash
kdestart virgl
```

`kdestart virgl` routes the whole session through `virpipe`/`virgl_test_server`
which does not hit the broken shared-context path. Individual GPU-heavy apps can
still be launched on Zink/Turnip separately (e.g. `chromium-turnip.sh`).

Recommended test order on Adreno 6xx/8xx:

1. `kdestart virgl` first — confirms a stable session.
2. If you want Zink's compositor performance, try `kdestart zink`
   (`KWIN_COMPOSE=Q` is set automatically).

## Why KWin crash / black screen can still happen

KWin's OpenGL compositing can fail through Zink with a `globalShareContext`
error, silently killing the session ~1–2 minutes after start. `zink` mode sets
`KWIN_COMPOSE=Q` (XRender/QPainter compositor) to work around it. If a specific
app still breaks, use `kdestart virgl` instead — it's the stable fallback.

## Don't know your GPU?

Look up your SoC's GPU:

| Brand              | Typical SoCs                              | GPU_NAME   |
|--------------------|-------------------------------------------|------------|
| Qualcomm/Snapdragon| SD 660+ (6xx/7xx/8xx series)              | `adreno`   |
| MediaTek           | Helio / Dimensity series                  | `mali`     |
| Samsung Exynos     | Exynos 2200+ (RDNA2 graphics)             | `xclipse`  |
| Others             | older/unsupported — use `virgl`/`generic` | `others`   |

The installer auto-detects from `getprop`, and falls back to a manual prompt
if it can't tell.
