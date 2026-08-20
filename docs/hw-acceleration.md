# Hardware Acceleration

KDE Plasma on Termux renders through Mesa. Which backend you get depends on the
GPU in your device and the mode `kdestart` is launched with. The installer
auto-detects your GPU and picks the right native stack for it.

## GPU strategy (auto-detected)

| GPU family                    | Native stack              | Default `kdestart` mode |
|-------------------------------|---------------------------|-------------------------|
| Adreno (Qualcomm Snapdragon 6xx/7xx/8xx) | **Turnip (Vulkan) + Zink (GL-over-Vulkan)** | `zink` |
| Mali (Arm/MediaTek/Exynos)    | **VirGL** (virpipe/ANGLE) | `virgl` |
| Xclipse (Samsung/RDNA2)       | **VirGL** (virpipe/ANGLE) | `virgl` |
| Others / unknown              | **VirGL** (conservative)  | `virgl` |

## Turnip + Zink (Adreno) — the native path

On Snapdragon 8 Elite (Adreno 830) and Snapdragon 800-series (Adreno 6xx/7xx),
the **best** performance is native Turnip + Zink:

- **Turnip** = open-source Vulkan driver for Adreno.
- **Zink** = OpenGL-over-Vulkan translator, so GL apps (Qt/KWin, browsers) ride
  on Turnip's Vulkan.

The installer installs `mesa` + `mesa-vulkan-icd-freedreno` (Turnip ICD) and
`kdestart` exports:

```
GALLIUM_DRIVER=zink
VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json
TU_DEBUG=noconform
```

> **Important:** we deliberately do **not** install the old `mesa-zink` tur
> package — it conflicts with `mesa` and ships a stale 2023 megadriver that
> breaks GL entirely (was the root cause of black screens). The correct native
> stack is `mesa` + `mesa-vulkan-icd-freedreno`.

## VirGL (Mali / MediaTek / Xclipse)

Mali & RDNA2/other GPUs lack a usable native desktop-GL path in Termux, so we
use **VirGL** (virpipe): GL calls are intercepted and passed through a
`virgl_test_server_android` to the GPU over Vulkan/EGL.

```
GALLIUM_DRIVER=virpipe
virgl_test_server_android --use-egl-surfaceless --use-gles &
```

## Modes

| Mode       | Stack                                         | Best for                                      |
|------------|-----------------------------------------------|-----------------------------------------------|
| `zink`     | Turnip + Zink (native GL-over-Vulkan)         | Adreno 6xx/7xx/8xx — best performance         |
| `virgl`    | virglrenderer / ANGLE (passthrough)           | Mali, Xclipse, others; or where Zink is bad   |
| `software` | llvmpipe (CPU)                                | Diagnostics only                              |

## Verify acceleration

Inside the Plasma session (Konsole):

```bash
glxinfo -B | grep -iE "renderer string|direct rendering"
```

- `OpenGL renderer string: zink Vulkan ... Turnip Adreno (TM) 830` → native GPU.
- `OpenGL renderer string: llvmpipe` → software fallback.

Or benchmark:

```bash
glmark2
```

Scores in the hundreds (vs. single/low double digits for llvmpipe) mean the GPU
is doing the work.

## Black screen on Adreno? Check the Mesa stack first

A black screen despite GPU detection normally means the **Mesa GL stack is
broken/mixed** (not a driver config issue). The two classic culprits:

1. The old `mesa-zink` tur package shipping a 2023 megadriver →
   `libGL error: failed to create dri screen` / `failed to load driver: swrast`.
   Fix:
   ```bash
   pkg remove -y mesa-zink
   pkg install -y mesa mesa-vulkan-icd-freedreno
   ```
2. A **Qt6/Plasma version mix** →
   `cannot locate symbol _ZN23QUntypedPropertyBinding...`.
   Fix:
   ```bash
   pkg upgrade -y
   pkg reinstall -y mesa mesa-vulkan-icd-freedreno qt6-qtbase qt6-qtdeclarative
   ```

After either, relaunch with `kdestart zink` and confirm the renderer string.
`kdestart` also sets `KWIN_COMPOSE=Q` in all plasma modes to force a stable
XRender/QPainter compositor even when KWin's GL compositor can't init.

## Don't know your GPU?

Run `other/kd-gpu-detect` (or `getprop ro.soc.model`) to check, or just let the
installer ask you at setup time.
