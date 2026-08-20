# Apps & Theming Beyond the Desktop

Everything here was debugged live — browser GPU paths, single-app sessions, and
Qt theming outside a full Plasma shell.

## Chromium on Termux:X11 (GPU paths)

Stock `chromium` inside the Plasma session can show a **black window** because
Chrome runs through **ANGLE → Zink → Turnip** (double translation), and the call
`eglGetMscRateANGLE: glXGetMscRateOML` crashes the GPU process. Two working paths:

### Path 1 — VirGL (stable / recommended)

```bash
chromium-vgl.sh            # == GALLIUM_DRIVER=virpipe DISPLAY=:0 chromium --use-gl=desktop
```

Routes Chromium through VirGL's predictable path while Plasma keeps native
Turnip/Zink. Installed to `$PREFIX/bin/chromium-vgl.sh` if you opted in.

Equivalent manual command:

```bash
GALLIUM_DRIVER=virpipe DISPLAY=:0 chromium --use-gl=desktop
```

### Path 2 — Turnip via ANGLE-Vulkan (fast, WebGL can be flaky)

```bash
chromium-turnip.sh         # == chromium --use-angle=vulkan --use-vulkan=native ...
```

Bypasses Zink/OpenGL so ANGLE talks Vulkan straight to Turnip
(`Chrome → ANGLE → Vulkan → Turnip`). Great raw speed, but **WebGL through
ANGLE-over-Vulkan frequently triggers context loss** on Turnip — switch to the
VirGL launcher for WebGL-heavy pages.

### Troubleshooting order that worked

1. `--use-gl=desktop` first.
2. Full flags file (`--use-gl=desktop --disable-gpu-vsync --disable-frame-rate-limit
   --ignore-gpu-blocklist --disable-gpu-process-crash-limit`).
3. Per-app software: `LIBGL_ALWAYS_SOFTWARE=1 DISPLAY=:0 chromium`.
4. VirGL per-app: `GALLIUM_DRIVER=virpipe DISPLAY=:0 chromium --use-gl=desktop`.

## Single-app sessions with `kdestart --konsole` / `kdestart --app`

Sometimes you just want Konsole/Dolphin without Plasma's process overhead (also
keeps you safely under Android's phantom-process ceiling):

```bash
kdestart --konsole          # Konsole in a light Openbox session
kdestart --app dolphin      # any single app
kdestart --app chromium
```

These start a minimal **Openbox** window manager (movable/resizable — a bare app
is a tiny, non-resizable window), plus **qt6ct** theming. GPU mode still applies
from your saved config or a prefix argument (`kdestart --konsole virgl`).

### The `pkill` self-kill pitfall

A launcher named `launch-konsole.sh` that ran `pkill -f konsole` **killed
itself** because `pkill -f` matches the full command line and the script's own
name contained "konsole". `kdestart` avoids this by matching only the exact
`-xstartup` invocation (`pkill -f "exit-with-session <app>"`), never bare
`<app>`. Rule: **never `pkill -f <app>` when the app name appears in your
script's own path or arguments.**

## Qt theming outside Plasma (flat white / no icons)

A Qt/KDE app launched without Plasma's theming daemon has no theme engine →
flat white, no icons. Fix:

```bash
pkg install breeze qt6ct        # qt6ct (or qt5ct for Qt5 apps)
export QT_QPA_PLATFORMTHEME=qt6ct
DISPLAY=:1 qt6ct                # pick Style = Breeze, Icon theme = breeze
```

`kdestart --konsole`/`--app` sets `QT_QPA_PLATFORMTHEME=qt6ct` automatically.
Inside full Plasma it's unnecessary — Plasma handles theming + decorators.
