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

## Verifying acceleration

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
