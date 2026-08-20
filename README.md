# termux-kde-plasma

One-click installer for **native** KDE Plasma on Termux — no root, no proot, no
chroot. It runs Plasma directly on top of Termux's own userland and renders
through **Termux:X11**, with GPU acceleration via **Turnip (Vulkan) + Zink
(GL-over-Vulkan)**, **VirGL**, or software fallback.

Tuned and tested for Adreno-based Snapdragon devices (Snapdragon 870 / Adreno
650, Snapdragon 8 Elite / Adreno 830), with graceful fallbacks for Mali,
Xclipse, and unknown GPUs.

---

## Features

- **One command install**: `curl -fsSL ... | bash` — fully self-contained.
- **Automatic GPU setup** — detects your SoC (`adreno`/`mali`/`xclipse`/`other`)
  with a manual fallback prompt, then installs the right Mesa driver stack.
- **Selectable, remembered GPU mode** (`zink`/`virgl`/`software`) persisted to
  `~/.config/termux-kde-plasma/config`.
- **`kdestart` / `kdestop` helper commands** installed to `$PREFIX/bin` — no flags
  to remember; option parsing + bash/zsh completions included.
- **PulseAudio fixed out of the box** (clears stale config, sets a clean runtime
  dir) — resolves the common *"Daemon startup failed"*.
- **KWin crash workaround** for the Zink `globalShareContext` bug.
- **Colored logging + package retry with recovery** for flaky repo/network
  installs; detects both `apt`/`pkg` and `pacman` package managers.
- **Docs & helpers** mirroring the structure of `sabamdarif/termux-desktop`.

---

## Requirements

- Android 8.0 or newer
- [Termux](https://github.com/termux/termux-app/releases) — **F-Droid or GitHub
  build** (not the sandboxed Play Store build)
- [Termux:X11](https://github.com/termux/termux-x11/releases) app installed
- ~3GB free RAM and ~3–4GB free storage
- Android 12+: disable the Phantom Process Killer — otherwise Plasma gets
  silently killed in the background → see
  [docs/disable-phantom-process-killing.md](docs/disable-phantom-process-killing.md)

---

## Installation

### Quick install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/marufmoinuddin/termux-kde-plasma/main/install.sh | bash
```

The script is self-contained: it writes every helper it needs into `$PREFIX/bin`,
so streaming it with `curl | bash` behaves identically to running it from a clone.

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

After install, these commands are available anywhere in Termux:

```bash
kdestart           # Launch Plasma with Turnip+Zink (your saved default)
kdestart virgl     # Launch with VirGL fallback
kdestart software  # Launch with software rendering (diagnostic)
kdestart --nogpu   # Launch without the GPU env
kdestart --help    # Show usage
kdestop            # Stop the Plasma / Termux:X11 session
```

Run `kdestart`, then open the **Termux:X11** Android app — it connects to
display `:0` automatically.

---

## GPU modes

| Mode       | Stack                                        | Best for                                       |
|------------|----------------------------------------------|------------------------------------------------|
| `zink`     | Turnip + Zink (GL-over-Vulkan)               | Adreno 6xx / 8xx — default, best performance   |
| `virgl`    | virglrenderer / ANGLE                        | Mali, Xclipse, or where Zink is unstable       |
| `software` | llvmpipe                                     | Diagnostics only                               |

See [docs/hw-acceleration.md](docs/hw-acceleration.md) for verification commands
(`glxinfo`, `glmark2`) and the "why is it still llvmpipe?" checklist.

---

## Repository layout

```
install.sh               # One-click self-contained installer
enable-hw-acceleration   # Reusable GPU-env module (sourced by launchers)
completion/
  bash/kdestart          # bash completion
  zsh/_kdestart          # zsh completion
docs/
  hw-acceleration.md     # GPU modes, verification, driver notes
  disable-phantom-process-killing.md
  troubleshooting.md     # every issue we hit, with fixes
other/
  setup-bash             # optional bash env tweaks
```

---

## Troubleshooting

TL;DR cover of the most common issues — full detail in
[docs/troubleshooting.md](docs/troubleshooting.md):

| Symptom                                    | Fix |
|--------------------------------------------|-----|
| `$DISPLAY is not set` / empty black screen | Clear stale `~/.config/pulse` + X lock; open Termux:X11 app; try `kdestart virgl` |
| "Daemon startup failed" (PulseAudio)       | `kdestart` auto-clears pulse config + runtime dir |
| Black screen / crash after ~1–2 min        | Zink `globalShareContext` bug → `kdestart` sets `KWIN_COMPOSE=Q`; else `kdestart virgl` |
| Missing window title bars                  | `DISPLAY=:0 kbuildsycoca6 --noincremental` |
| Keyboard types wrong chars                 | Toggle "Hardware keyboard scancodes workaround" in Termux:X11 settings; or `setxkbmap us` |
| Background kill / phantom process          | [Phantom Process Killer](docs/disable-phantom-process-killing.md) — Android 12+ |
| "Software rendering" despite `zink`        | Install combined `mesa-zink-vulkan-icd-freedreno` (Adreno 6xx+) |

Log files:

- `~/kde-plasma-install.log` — installer output
- `~/plasma-session.log` — each `kdestart` run

---

## Credits

Inspired by the structure and conventions of
[sabamdarif/termux-desktop](https://github.com/sabamdarif/termux-desktop),
scoped specifically to a KDE Plasma + Turnip/Zink/VirGL workflow.

## License

MIT — see [LICENSE](LICENSE).
