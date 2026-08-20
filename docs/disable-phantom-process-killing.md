# Disabling the Phantom Process Killer (Android 12+)

On Android 12 and newer, the system aggressively kills background processes —
including Termux services — via the **Phantom Process Killer** (PPK). This is
**not** a real out-of-memory kill and it will silently kill Plasma/PulseAudio
plugin processes mid-session.

## Make it permanent (recommended)

On a normal (non-rooted) device this survives until the developer option is
reset, and survives reboots:

```bash
adb shell device_config put activity_manager max_phantom_processes 2147483647
adb shell settings put global settings_enable_monitor_phantom_procs false
```

> The second command drives the on/off switch in **Developer options →
> "Usability" → "Kill background processes after leaving"** equivalent toggles;
> on many ROMs the Phantom Process Killer toggle lives under
> **Developer options → "Usability" → "Disable-Hidden API restrictions"** — the
> exact label varies. Both ADB commands above are the reliable route.

## Verify

```bash
adb shell device_config get activity_manager max_phantom_processes
```

Should print `2147483647`.

## If you see "Process ... was killed due to phantom"

That message confirms PPK is at work. Re-run the ADB commands above and restart
Termux.

## Rooted devices

If you have a rooted device you can also just disable Process Optimizer through
an app like **Universal GMS Doze** / **FDE.AI**, or freeze `com.google.android.gms`
optimization, but the ADB route above is sufficient and doesn't require root.
