# Troubleshooting

Worked through live against Snapdragon 8 Elite (Adreno 830) and Snapdragon 870
(Adreno 650). Symptom → cause → fix, from most to least common.

## Black screen (Plasma launches, no desktop)

This is far and away the most common failure. In order, check:

### 1. Broken/mixed Mesa GL stack (most common)

Symptom in `~/plasma-raw.log` or a live `startplasma-x11`:

```
libGL error: failed to create dri screen
libGL error: failed to load driver: swrast
kwin_scene_opengl: Creating the OpenGL rendering failed: "Invalid QOpenGLContext::globalShareContext()"
```

Cause: the old `mesa-zink` tur package shipped a 2023 megadriver that clobbers
the whole GL path. Fix (bash):

```bash
pkg remove -y mesa-zink
apt --fix-broken install -y
pkg install -y mesa mesa-vulkan-icd-freedreno mesa-vulkan-icd-swrast
# verify DRI drivers now exist + are current
ls -la "$PREFIX/lib/dri/"
```

### 2. Qt6/Plasma version mix

Symptom:

```
cannot locate symbol "_ZN23QUntypedPropertyBindingC1EP23QPropertyBindingPrivate"
```

Cause: Plasma plugins built against a newer Qt6 than installed (partial
upgrade / forced install mixed versions). Fix:

```bash
pkg clean
pkg update -y
pkg upgrade -y
pkg reinstall -y mesa mesa-vulkan-icd-freedreno qt6-qtbase qt6-qtdeclarative
```

### 3. GL compositor (even with good drivers)

The `Invalid QOpenGLContext::globalShareContext()` line can persist even with a
correct driver — KWin's GL compositor fails through Zink on Adreno. `kdestart`
sets `KWIN_COMPOSE=Q` (XRender/QPainter) in all plasma modes to work around it.
If you're launching manually, add `export KWIN_COMPOSE=Q`.

## "$DISPLAY is not set" / X server never appears

1. **Stale X lock/socket** — `kdestart` clears `.X0-lock` + `.X11-unix/X0`.
2. **Missing `XDG_RUNTIME_DIR`** — `kdestart` sets it explicitly.
3. **Termux:X11 app not ready** — open the Android app once before launching.
4. **Stale registration** — force-stop + clear cache on Termux and Termux:X11.

## PulseAudio "Daemon startup failed"

`kdestart` clears `~/.config/pulse` and uses a dedicated `PULSE_RUNTIME_PATH`
under `$TMPDIR` each launch. Verify with `pactl info` and check
`~/plasma-session.log`.

## Missing window title bars / borders

Usually a stale `ksycoca` cache ("package corruption" that isn't):

```bash
DISPLAY=:0 kbuildsycoca6 --noincremental
```

If titlebars still don't appear, `kdestart` now also runs
`kbuildsycoca6 --noincremental` before `startplasma-x11`, matching the final
repair step from the tutorial. If you want to test whether the compositor
workaround is what is flattening decorations, try:

```bash
TERMUX_KDE_PLASMA_KWIN_COMPOSE=unset kdestart
```

## Keyboard types wrong characters

- Toggle **"Hardware keyboard scancodes workaround"** in the Termux:X11 app
  settings (opposite of its current state), then relaunch the app.
- For a scrambled layout: `setxkbmap us` (or your layout).
- If input freezes after app-switch, tap **Alt** once to wake focus.

`kdestart` auto-runs `setxkbmap "$XKB_DEFAULT_LAYOUT"` when `setxkbmap` is
installed (part of `xorg-setxkbmap`).

## Termux gets killed in the background

Android's **Phantom Process Killer** (Android 12+), not a real OOM kill. See
[disable-phantom-process-killing.md](disable-phantom-process-killing.md).

## Log files

- `~/kde-plasma-install.log` — installer output
- `~/plasma-session.log` — each `kdestart` run
- `~/kdestart-app-session.log` — each `kdestart --app` run
