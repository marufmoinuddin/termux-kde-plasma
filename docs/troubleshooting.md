# Troubleshooting

## "$DISPLAY is not set" / X server never appears

This is the most common failure and almost always one of:

1. **Stale X lock or socket** — `kdestart` removes `$PREFIX/tmp/.X0-lock` and the
   `$PREFIX/tmp/.X11-unix/X0` socket on every launch. If you're running an old
   manual script, make sure it clears both.
2. **Missing `XDG_RUNTIME_DIR`** — `kdestart` sets it explicitly. Without it the
   X server sometimes fails to register the display socket.
3. **Termux:X11 app not opened/ready** — the Android app must be launched at
   least once so it can accept the connection on display `:0`.
4. **Stale X server registration** — force-stop and clear cache on both Termux
   and Termux:X11 in Android app settings, then retry.

## PulseAudio "Daemon startup failed"

`kdestart` clears `~/.config/pulse` and sets a dedicated `PULSE_RUNTIME_PATH`
under `$TMPDIR` on each launch. If you still see it, check `~/plasma-session.log`
and confirm no other PulseAudio instance is holding the runtime dir.

## Black screen / KWin crash after ~1–2 minutes

The Zink `globalShareContext` compositor bug. `zink` mode sets `KWIN_COMPOSE=Q`.
If it persists, switch to `kdestart virgl`.

## Missing window title bars / borders

Usually a stale `ksycoca` cache after package updates:

```bash
DISPLAY=:0 kbuildsycoca6 --noincremental
```

## Keyboard types wrong characters

- Toggle **"Hardware keyboard scancodes workaround"** in the Termux:X11 app's
  own settings (opposite of its current state), then relaunch the app.
- For a fully scrambled layout, force the layout inside the session:
  ```bash
  setxkbmap us   # or your layout code
  ```
- If input freezes after switching apps, tap **Alt** once to wake focus.

`kdestart` auto-runs `setxkbmap "$XKB_DEFAULT_LAYOUT"` (default `us`).

## "Software rendering in use" despite `zink`

1. Confirm the ICD exists: `ls $PREFIX/share/vulkan/icd.d/`
2. Confirm the renderer: `glxinfo -B | grep -i renderer` → should say `zink`/
   `Turnip`, not `llvmpipe`.
3. On Adreno 6xx+, install the **combined** package
   `mesa-zink-vulkan-icd-freedreno` rather than separate mesa/vulkan ICDs.

## Termux gets killed in the background

Phantom Process Killer (Android 12+). See
[disable-phantom-process-killing.md](disable-phantom-process-killing.md).

## Log files

- `~/kde-plasma-install.log` — installer output
- `~/plasma-session.log` — each `kdestart` run
