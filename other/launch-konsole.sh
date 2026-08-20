#!/data/data/com.termux/files/usr/bin/bash
###############################################################################
# launch-konsole.sh
# Lightweight launcher: Konsole ONLY (no Plasma shell/desktop) via Termux:X11
# GPU: Turnip (Vulkan) + Zink (GL-over-Vulkan) for Adreno 6xx, VirGL fallback
# Last-known-good baseline + PulseAudio "Daemon startup failed" workaround fixed
###############################################################################

set -uo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOGFILE="$HOME/konsole-session.log"
GPU_MODE="${1:-zink}"   # usage: ./launch-konsole.sh [zink|virgl|software]

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOGFILE"; }

echo "" > "$LOGFILE"
log "Starting Konsole-only launch script (GPU mode: $GPU_MODE)"

### 1. Clean up any previous stale session ###################################
log "Killing any existing termux-x11 / dbus / konsole processes..."
pkill -f termux-x11 2>/dev/null
pkill -f "exit-with-session konsole" 2>/dev/null
pkill -f dbus-launch 2>/dev/null
sleep 1

log "Removing stale X lock/socket files..."
rm -rf "$PREFIX/tmp/.X0-lock" "$PREFIX/tmp/.X11-unix/X0" 2>/dev/null

### 2. Core environment ########################################################
export XDG_RUNTIME_DIR="$HOME/.runtime"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
export DISPLAY=:0
export QT_QPA_PLATFORMTHEME=qt6ct

log "Resetting PulseAudio state (fixes 'Daemon startup failed')..."
pulseaudio --kill 2>/dev/null
sleep 1
rm -rf ~/.config/pulse
mkdir -p "$TMPDIR/pulse"
chmod 700 "$TMPDIR/pulse"
export PULSE_RUNTIME_PATH="$TMPDIR/pulse"

unset PULSE_SERVER
log "Starting PulseAudio server..."
pulseaudio --start --exit-idle-time=-1 --disable-shm=1 \
  --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
  &>>"$LOGFILE"
sleep 2
export PULSE_SERVER=127.0.0.1

if pactl info &>>"$LOGFILE"; then
  log "PulseAudio started successfully."
else
  log "WARNING: PulseAudio failed to start. Check $LOGFILE."
fi

### 3. GPU acceleration selection ##############################################
case "$GPU_MODE" in
  zink)
    log "Configuring Turnip + Zink (Adreno hardware acceleration)..."
    export GALLIUM_DRIVER=zink
    export VK_ICD_FILENAMES="$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json"
    export TU_DEBUG=noconform
    export MESA_VK_WSI_PRESENT_MODE=immediate
    export vblank_mode=0
    export MESA_SHADER_CACHE_DIR="$HOME/.cache/mesa_shader_cache"
    mkdir -p "$MESA_SHADER_CACHE_DIR"
    ;;
  virgl)
    log "Configuring VirGL fallback renderer..."
    export GALLIUM_DRIVER=virpipe
    export VIRGL_GPU_NUM=1
    ;;
  software)
    log "Forcing software rendering (llvmpipe) — diagnostic mode only."
    export LIBGL_ALWAYS_SOFTWARE=1
    ;;
  *)
    log "Unknown GPU_MODE '$GPU_MODE'. Valid options: zink, virgl, software."
    exit 1
    ;;
esac

### 4. Keyboard layout sanity default ##########################################
export XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"

### 5. Start the Termux:X11 server with Openbox + Konsole ####################
log "Launching termux-x11 server on display :0 with Openbox + Konsole..."
termux-x11 :0 -xstartup "dbus-launch --exit-with-session sh -c 'openbox & sleep 1 && konsole --nofork'" &>>"$LOGFILE" &
X11_PID=$!

log "Waiting for X server socket to appear..."
for i in $(seq 1 20); do
  if [ -e "$PREFIX/tmp/.X11-unix/X0" ]; then
    log "X server socket detected after ${i}s."
    break
  fi
  sleep 1
done

if [ ! -e "$PREFIX/tmp/.X11-unix/X0" ]; then
  log "ERROR: X server socket never appeared. Check $LOGFILE for details."
  exit 1
fi

sleep 2

### 6. Apply keyboard layout inside the session ###############################
log "Applying keyboard layout: $XKB_DEFAULT_LAYOUT"
DISPLAY=:0 setxkbmap "$XKB_DEFAULT_LAYOUT" 2>>"$LOGFILE"

### 7. Verify GPU renderer (best-effort, non-fatal) ############################
if command -v glxinfo >/dev/null 2>&1; then
  RENDERER=$(DISPLAY=:0 glxinfo -B 2>>"$LOGFILE" | grep -i "OpenGL renderer" || true)
  log "Renderer detected: ${RENDERER:-unknown}"
  if echo "$RENDERER" | grep -qi "llvmpipe" && [ "$GPU_MODE" != "software" ]; then
    log "WARNING: llvmpipe (software) detected despite GPU_MODE=$GPU_MODE. Check driver install."
  fi
else
  log "glxinfo not found, skipping renderer check (install mesa-demos to enable)."
fi

log "Konsole launch sequence complete. PID of X11 process: $X11_PID"
log "Open the Termux:X11 Android app now if it is not already connected."
log "Closing the Konsole window will end this session automatically."

wait "$X11_PID"
log "termux-x11 process exited. Session ended."
