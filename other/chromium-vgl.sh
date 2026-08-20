#!/data/data/com.termux/files/usr/bin/bash
# chromium-vgl.sh
# Launch Chromium on VirGL (virpipe) — the stable path for Chrome on Termux:X11.
#
# Why: Zink + ANGLE + Chromium is the known-unstable combination (black window /
# GPU-process crash loop, exact error `eglGetMscRateANGLE: glXGetMscRateOML`).
# Routing just this app through VirGL keeps Plasma/KWin on Turnip+Zink while
# Chromium itself gets a predictable GL path. Confirmed working on Adreno 650.
#
# Usage:
#   chromium-vgl.sh [url]
set -uo pipefail

readonly TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
DISPLAY="${DISPLAY:-:0}"

# Chromium is a Qt/Gtk app; inherited theme only if inside a Plasma session.
# Outside Plasma, force qt6ct if present for correct icons/colors.
if command -v qt6ct >/dev/null 2>&1; then
    export QT_QPA_PLATFORMTHEME="${QT_QPA_PLATFORMTHEME:-qt6ct}"
fi

exec env GALLIUM_DRIVER=virpipe DISPLAY="$DISPLAY" "$TERMUX_PREFIX/bin/chromium" \
    --use-gl=desktop --disable-gpu-vsync --disable-frame-rate-limit \
    --ignore-gpu-blocklist --disable-gpu-process-crash-limit "$@"
