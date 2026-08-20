# termux-kde-plasma

One-click installer for native KDE Plasma on Termux via Termux:X11, with GPU acceleration through Turnip (Vulkan), Zink (OpenGL-over-Vulkan), or VirGL — tuned for Adreno-based Snapdragon devices (tested on Snapdragon 870 / Adreno 650 and Snapdragon 8 Elite / Adreno 830).

No root, no proot, no chroot — this runs KDE Plasma directly on top of native Termux for the best possible performance on Android.

## Features

- One command install: `bash install.sh`
- Automatic Turnip/Zink GPU driver setup for Adreno 6xx/8xx GPUs
- VirGL and software-rendering fallback modes for troubleshooting
- PulseAudio pre-configured correctly (fixes the common "Daemon startup failed" issue)
- KWin crash workaround for the Zink `globalShareContext` compositor bug
- Simple `kdestart` / `kdestop` commands after install — no need to remember flags
- Colored logging with retry logic for flaky package installs
- Session config persisted so your GPU mode/keyboard layout choice is remembered

## Requirements

- Android 8.0 or newer
- [Termux](https://github.com/termux/termux-app/releases) (F-Droid or GitHub build — **not** the Play Store version)
- [Termux:X11](https://github.com/termux/termux-x11/releases) app installed separately
- 3GB+ free RAM, ~3-4GB free storage
- On Android 12+: disable the Phantom Process Killer (see Troubleshooting below) to prevent Plasma processes from being silently killed in the background

## Installation

### Quick install (curl one-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/marufmoinuddin/termux-kde-plasma/main/install.sh | bash
```

### Manual install (clone first)

```bash
pkg install git -y
git clone https://github.com/marufmoinuddin/termux-kde-plasma
cd termux-kde-plasma
bash install.sh
```

## Usage

After installation, three commands are available anywhere in Termux:

```bash
kdestart          # Launch Plasma with Turnip+Zink GPU acceleration (default)
kdestart virgl    # Launch Plasma with VirGL fallback (more stable on some devices)
kdestart software # Launch Plasma with software rendering (diagnostic mode only)
kdestop           # Kill the running Plasma/Termux:X11 session
```

Open the **Termux:X11** Android app right after running `kdestart` — it will connect to display `:0` automatically once the X server socket is ready.

## GPU Mode Guide

| Mode | Best for | Notes |
|---|---|---|
| `zink` (default) | Most Adreno 6xx/8xx devices | Best raw performance; occasional compositor instability, mitigated via forced XRender compositing |
| `virgl` | Devices where Zink causes crashes/black screens | More stable, slightly lower performance |
| `software` | Diagnostics only | Confirms whether an issue is GPU-driver-related |

## Troubleshooting

**PulseAudio fails to start ("Daemon startup failed")**
`kdestart` automatically clears `~/.config/pulse` and uses a dedicated runtime path on every launch to avoid this. If it still fails, check `~/plasma-session.log`.

**Black screen / KWin crash after ~1-2 minutes**
This is a known Zink `globalShareContext` compositor bug. `kdestart` sets `KWIN_COMPOSE=Q` automatically in Zink mode to force XRender/QPainter compositing and avoid the crash. If instability persists, try `kdestart virgl`.

**Missing window title bars / borders**
Usually caused by a stale `ksycoca` cache. Run:
```bash
DISPLAY=:0 kbuildsycoca6 --noincremental
```

**Keyboard typing wrong characters**
Toggle "Hardware keyboard scancodes workaround" in the Termux:X11 app's own settings, or run `setxkbmap us` (or your layout) inside a Konsole session.

**Termux gets killed in the background**
This is Android's Phantom Process Killer (Android 12+), not a real OOM kill. Fix via ADB:
```bash
adb shell device_config put activity_manager max_phantom_processes 2147483647
```

**Verify GPU acceleration is active**
```bash
glxinfo -B | grep -iE "renderer string|direct rendering"
glmark2
```
A renderer string mentioning "Turnip" or "Adreno" (not `llvmpipe`) confirms hardware acceleration is working.

## Credits

Inspired by the structure and conventions of [sabamdarif/termux-desktop](https://github.com/sabamdarif/termux-desktop), scoped specifically to a KDE Plasma + Turnip/Zink/VirGL workflow.

## License

MIT — see [LICENSE](LICENSE).
