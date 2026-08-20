# termux-kde-plasma

One-click installer for **native** KDE Plasma on Termux — no root, no proot, no
chroot. Runs Plasma directly on Termux's own userland, rendered through
**Termux:X11** with hardware acceleration.

**GPU-aware by design:** auto-detects your SoC and installs the right stack —
native **Turnip + Zink** for Adreno (Snapdragon 8 Elite / 800-series and other
Adreno), **VirGL** for Mali/MediaTek/Xclipse. One command, no fiddling.

Inspired by the structure of
[sabamdarif/termux-desktop](https://github.com/sabamdarif/termux-desktop) and
[LinuxDroidMaster/Termux-Desktops](https://github.com/LinuxDroidMaster/Termux-Desktops),
scoped tightly to a KDE Plasma + Turnip/Zink/VirGL + Termux:X11 workflow.

---

## Features

- **One command install**: `curl -fsSL ... | bash` — fully self-contained.
- **GPU auto-detect** (`getprop`): Adreno → native Turnip+Zink; Mali/Xclipse →
  VirGL; manual fallback prompt.
- **Selectable, persisted GPU mode** (`zink`/`virgl`/`software`) saved to
  `~/.config/termux-kde-plasma/config`.
- **`kdestart` / `kdestop` helpers** installed to `$PREFIX/bin`, with bash + zsh
  completions.
- **`kdestart --konsole` / `--app <name>`** — single-app lightweight Openbox
  sessions with theming, no full Plasma.
- **PulseAudio fixed out of the box** (clears stale config, clean runtime dir).
- **Compositor workaround** (`KWIN_COMPOSE=Q`) in all plasma modes so Plasma
  renders even when KWin's GL compositor can't init on the GPU. You can test the
  guide's decoration fix path with `TERMUX_KDE_PLASMA_KWIN_COMPOSE=unset`.
- **apt / pkg / pacman** with retry + recovery.
- **Optional Chromium** launchers (`chromium-vgl.sh` / `chromium-turnip.sh`).

---

## Requirements

- Android 8.0 or newer
- [Termux](https://github.com/termux/termux-app/releases) — **F-Droid or GitHub
  build** (not the sandboxed Play Store build)
- [Termux:X11](https://github.com/termux/termux-x11/releases) app
- ~3GB free RAM, ~3–4GB free storage
- Android 12+: disable the Phantom Process Killer →
  [docs/disable-phantom-process-killing.md](docs/disable-phantom-process-killing.md)

---

## Installation

### Quick install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/marufmoinuddin/termux-kde-plasma/main/install.sh | bash
```

Self-contained: it writes every helper into `$PREFIX/bin`, so streaming behaves
identically to running from a clone.

### Manual (clone first)

```bash
pkg install git -y
git clone https://github.com/marufmoinuddin/termux-kde-plasma
cd termux-kde-plasma
bash install.sh
```

> Open the Termux:X11 Android app once before first launch so it can accept the
> connection.

---

## Usage

```bash
kdestart             # Launch Plasma with your saved default mode (zink on Adreno)
kdestart zink        # Launch Plasma on native Turnip+Zink
kdestart virgl       # Launch Plasma on VirGL (Mali/MediaTek/Xclipse, or fallback)
kdestart software    # Launch Plasma with software rendering (diagnostic)
kdestart --konsole   # Konsole-only lightweight Openbox session
kdestart --app dolphin  # Launch any single app in a light Openbox session
kdestart --nogpu     # Launch Plasma without the GPU env
kdestart --help
kdestop              # Stop the Plasma / Termux:X11 session
chromium-vgl.sh      # Chromium on VirGL (if installed)
chromium-turnip.sh   # Chromium on Turnip via ANGLE-Vulkan (if installed)
```

Run `kdestart`, then open the **Termux:X11** app — it connects to display `:0`.

---

## GPU modes

| GPU              | Recommended mode | Stack                                      |
|------------------|------------------|--------------------------------------------|
| Adreno (SD 6xx/7xx/8xx) | `zink`    | Turnip (Vulkan) + Zink (GL-over-Vulkan)     |
| Mali / Xclipse / others | `virgl`    | virglrenderer / ANGLE passthrough           |
| Any (diagnostic) | `software`       | llvmpipe                                    |

The installer chooses the default based on detection; override any time with a
positional argument (`kdestart virgl`). Details & verification in
[docs/hw-acceleration.md](docs/hw-acceleration.md).

---

## Troubleshooting

The full playbook (worked through on Adreno 830 + Adreno 650) is in
[docs/troubleshooting.md](docs/troubleshooting.md). Quick hits:

| Symptom                                          | Fix |
|--------------------------------------------------|-----|
| Black screen, `failed to create dri screen`      | Remove old `mesa-zink`; reinstall `mesa mesa-vulkan-icd-freedreno` |
| Black screen, `cannot locate symbol _ZN23QUntyped...` | Qt6/Plasma version mix → `pkg upgrade` + reinstall Qt6/Plasma |
| `globalShareContext` compositor error            | Already handled by `KWIN_COMPOSE=Q` in `kdestart` |
| `$DISPLAY is not set`                            | `kdestart` cleans lock/socket + sets `XDG_RUNTIME_DIR` |
| PulseAudio "Daemon startup failed"               | Auto-clears `~/.config/pulse` + clean runtime dir |
| Missing title bars                               | `DISPLAY=:0 kbuildsycoca6 --noincremental` |
| Keyboard wrong chars                             | Toggle scancodes in Termux:X11 settings, or `setxkbmap us` |
| Background kill / phantom process                | [Disable Phantom Process Killer](docs/disable-phantom-process-killing.md) |

---

## Repository layout

```
install.sh               # One-click self-contained installer
enable-hw-acceleration   # Reusable GPU-env module (sourced by launchers)
completion/
  bash/kdestart          # bash completion
  zsh/_kdestart          # zsh completion
docs/
  hw-acceleration.md     # GPU strategy, verification, driver notes
  disable-phantom-process-killing.md
  troubleshooting.md     # the full black-screen/debug playbook
  apps-and-theming.md    # Chromium GPU paths, --konsole, pkill pitfall, Qt theming
other/
  setup-bash             # optional bash env tweaks
  kd-gpu-detect          # standalone GPU detection helper
  chromium-vgl.sh        # Chromium on VirGL (also generated by install.sh)
  chromium-turnip.sh     # Chromium on Turnip via ANGLE-Vulkan
```

---

## Credits

- [sabamdarif/termux-desktop](https://github.com/sabamdarif/termux-desktop) —
  installer structure, retry/recovery, config model, GPU-env module.
- [LinuxDroidMaster/Termux-Desktops](https://github.com/LinuxDroidMaster/Termux-Desktops) —
  native Termux:X11 launch patterns (`am start`, `PULSE_SERVER`/`XDG_RUNTIME_DIR`).

## License

MIT — see [LICENSE](LICENSE).
