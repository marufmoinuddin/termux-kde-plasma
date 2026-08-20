#!/data/data/com.termux/files/usr/bin/bash
# chromium-turnip.sh
# Launch Chromium directly on Turnip via ANGLE's native Vulkan backend.
#
# Why: to use the real GPU without the Zink/OpenGL detour, make ANGLE speak
# Vulkan straight to Turnip:  Chrome -> ANGLE -> Vulkan -> Turnip.
# NOTE: ANGLE-over-Vulkan's WebGL path is flaky on many drivers (context loss).
# If you hit WebGL issues, use chromium-vgl.sh instead — WebGL is more reliable
# through the GL backend.
#
# Usage:
#   chromium-turnip.sh [url]
set -uo pipefail

readonly TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
DISPLAY="${DISPLAY:-:0}"

if command -v qt6ct >/dev/null 2>&1; then
    export QT_QPA_PLATFORMTHEME="${QT_QPA_PLATFORMTHEME:-qt6ct}"
fi

exec env DISPLAY="$DISPLAY" "$TERMUX_PREFIX/bin/chromium" \
    --use-angle=vulkan --use-vulkan=native \
    --enable-features=Vulkan,VaapiVideoDecoder \
    --enable-gpu-rasterization --enable-zero-copy \
    --ignore-gpu-blocklist "$@"
