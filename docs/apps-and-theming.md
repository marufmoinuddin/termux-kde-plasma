# Apps & Theming Beyond the Desktop

Everything in this file was debugged live in our history — browser GPU paths,
single-app sessions, and Qt theming outside a full Plasma shell.

---

## Chromium on Termux:X11 (GPU paths)

Stock `chromium` inside the Plasma session can show a **black window** because
Chrome runs through **ANGLE → Zink → Turnip** (a double translation layer), and
the specific call `eglGetMscRateANGLE: glXGetMscRateOML` crashes the GPU process
repeatedly. Two working paths avoid it:

### Path 1 — VirGL (stable / recommended)

```bash
chromium-vgl.sh            # == GALLIUM_DRIVER=virpipe DISPLAY=:0 chromium --use-gl=desktop
```

This routes Chromium through VirGL's predictable Gallium3D path while Plasma and
other apps keep using Turnip/Zink untouched. The launcher is written to
`$PREFIX/bin/chromium-vgl.sh` if you opted into Chromium during install.

Equivalent manual command:

```bash
GALLIUM_DRIVER=virpipe DISPLAY=:0 chromium --use-gl=desktop
```

### Path 2 — Turnip via ANGLE-Vulkan (fast, WebGL can be flaky)

```bash
chromium-turnip.sh         # == chromium --use-angle=vulkan --use-vulkan=native ...
```

Bypasses Zink/OpenGL entirely so ANGLE talks Vulkan straight to Turnip
(`Chrome → ANGLE → Vulkan → Turnip`). Great raw performance, but **WebGL through
ANGLE-over-Vulkan frequently triggers context loss** on Turnip — if a page says
"WebGL is not supported / context lost," switch that tab or use the VirGL path.

### Troubleshooting order that worked

1. `--use-gl=desktop` flag first.
2. Full flags file (`--use-gl=desktop --disable-gpu-vsync --disable-frame-rate-limit
   --ignore-gpu-blocklist --disable-gpu-process-crash-limit`).
3. Software fallback for that app only: `LIBGL_ALWAYS_SOFTWARE=1 DISPLAY=:0 chromium`.
4. VirGL per-app: `GALLIUM_DRIVER=virpipe DISPLAY=:0 chromium --use-gl=desktop`.

---

## Single-app sessions with `kdapp` (no full Plasma)

Sometimes you just want Konsole/Dolphin without Plasma's process overhead
(which also keeps you safely under Android's phantom-process ceiling).

```bash
kdapp konsole
kdapp dolphin
kdapp chromium
```

`kdapp` starts a minimal **Openbox** window manager (so the app is movable and
resizable — a bare app is a tiny, non-resizable window otherwise), plus
**qt6ct** theming so the app isn't flat white.

### The `pkill` self-kill pitfall

A big gotcha from our history: a launcher script named `launch-konsole.sh` that
ran `pkill -f konsole` **killed itself**, because `pkill -f` matches the full
command line and the script's own name/path contained "konsole".

`kdapp` avoids this by only matching the exact startup invocation
(`pkill -f "exit-with-session <app>"`), never bare `<app>`. If you write your
own launcher, always keep this in mind: **never `pkill -f <app>` when the app
name appears in your script's own path or arguments.**

---

## Qt theming outside Plasma (flat white / no icons)

A Qt/KDE app (like Konsole) launched **without** Plasma's theming daemon has no
theme engine, so it renders flat white with no icons. Fix:

```bash
pkg install breeze qt6ct        # qt6ct (or qt5ct if your app is Qt5)
export QT_QPA_PLATFORMTHEME=qt6ct
DISPLAY=:1 qt6ct                # pick Style = Breeze, Icon theme = breeze
```

`kdapp` sets `QT_QPA_PLATFORMTHEME=qt6ct` automatically and installs `qt6ct`
during setup. Inside a full Plasma session this is unnecessary — Plasma handles
theming itself and provides the window decorators.

---

## Missing title bars in full Plasma

Usually a stale `ksycoca` cache:

```bash
DISPLAY=:0 kbuildsycoca6 --noincremental
```

If bars are still missing, it can be the `KWIN_COMPOSE=Q` compositor mode used
to work around the Zink crash — test with `unset KWIN_COMPOSE` before
reinstalling packages. See `docs/troubleshooting.md`.
