#!/data/data/com.termux/files/usr/bin/bash
###############################################################################
# install.sh
# One-click installer: Native KDE Plasma on Termux via Termux:X11
# GPU: Turnip (Vulkan) + Zink (GL-over-Vulkan) for Adreno 6xx/8xx, VirGL fallback
# Repo: https://github.com/marufmoinuddin/termux-kde-plasma
###############################################################################

set -uo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOGFILE="$HOME/kde-plasma-install.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$LOGFILE"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*" | tee -a "$LOGFILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOGFILE"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOGFILE"; }

echo "" > "$LOGFILE"
log "Starting KDE Plasma installer for Termux..."

retry() {
  local n=0 max=3
  until "$@"; do
    n=$((n+1))
    if [ "$n" -ge "$max" ]; then
      err "Command failed after $max attempts: $*"
      return 1
    fi
    warn "Retrying ($n/$max): $*"
    sleep 2
  done
}

### 1. Prerequisite repos ######################################################
log "Enabling x11-repo and tur-repo..."
retry pkg install -y x11-repo tur-repo
retry pkg update -y
retry pkg upgrade -y

### 2. Core packages ############################################################
log "Installing Termux:X11, Plasma, Konsole, Dolphin, PulseAudio, dbus..."
retry pkg install -y \
  termux-x11-nightly \
  pulseaudio \
  dbus \
  plasma-desktop \
  plasma-workspace \
  plasma-integration \
  plasma-pa \
  kwin-x11 \
  kdecoration \
  breeze \
  breeze-icons \
  konsole \
  dolphin \
  kio-extras \
  kde-cli-tools

### 3. GPU driver packages #####################################################
log "Installing Mesa / Turnip / Zink / VirGL packages..."
retry pkg install -y mesa mesa-vulkan-icd-freedreno mesa-demos glmark2 virglrenderer-android

if pkg list-all 2>/dev/null | grep -q "^mesa-zink-vulkan-icd-freedreno"; then
  log "Detected Adreno 6xx-compatible combined package, installing..."
  retry pkg install -y mesa-zink-vulkan-icd-freedreno
fi

### 4. Save config ##############################################################
CONFIG_DIR="$HOME/.config/termux-kde-plasma"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config" << EOF
GPU_MODE=zink
XKB_DEFAULT_LAYOUT=us
INSTALLED_AT=$(date '+%Y-%m-%d %H:%M:%S')
EOF
ok "Config saved to $CONFIG_DIR/config"

### 5. Install launcher scripts #################################################
log "Installing launch.sh and helper commands to \$PREFIX/bin..."

cat > "$PREFIX/bin/kdestart" << 'LAUNCHEOF'
#!/data/data/com.termux/files/usr/bin/bash
###############################################################################
# kdestart - Launch native KDE Plasma via Termux:X11
# Usage: kdestart [zink|virgl|software]
###############################################################################

set -uo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOGFILE="$HOME/plasma-session.log"
CONFIG_FILE="$HOME/.config/termux-kde-plasma/config"

if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

GPU_MODE="${1:-${GPU_MODE:-zink}}"
XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOGFILE"; }

echo "" > "$LOGFILE"
log "Starting Plasma launch script (GPU mode: $GPU_MODE)"

log "Killing any existing termux-x11 / dbus / plasma processes..."
pkill -f termux-x11 2>/dev/null
pkill -f startplasma-x11 2>/dev/null
pkill -f dbus-launch 2>/dev/null
sleep 1

log "Removing stale X lock/socket files..."
rm -rf "$PREFIX/tmp/.X0-lock" "$PREFIX/tmp/.X11-unix/X0" 2>/dev/null

export XDG_RUNTIME_DIR="$HOME/.runtime"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
export DISPLAY=:0

log "Resetting PulseAudio state..."
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
    log "Forcing KWin to XRender/QPainter compositing to avoid Zink globalShareContext crash..."
    export KWIN_COMPOSE=Q
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

log "Launching termux-x11 server on display :0..."
termux-x11 :0 -xstartup "dbus-launch --exit-with-session startplasma-x11" &>>"$LOGFILE" &
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

log "Applying keyboard layout: $XKB_DEFAULT_LAYOUT"
DISPLAY=:0 setxkbmap "$XKB_DEFAULT_LAYOUT" 2>>"$LOGFILE"

if command -v glxinfo >/dev/null 2>&1; then
  RENDERER=$(DISPLAY=:0 glxinfo -B 2>>"$LOGFILE" | grep -i "OpenGL renderer" || true)
  log "Renderer detected: ${RENDERER:-unknown}"
  if echo "$RENDERER" | grep -qi "llvmpipe" && [ "$GPU_MODE" != "software" ]; then
    log "WARNING: llvmpipe (software) detected despite GPU_MODE=$GPU_MODE. Check driver install."
  fi
else
  log "glxinfo not found, skipping renderer check (install mesa-demos to enable)."
fi

log "Plasma session launch sequence complete. PID of X11 process: $X11_PID"
log "Open the Termux:X11 Android app now if it is not already connected."

wait "$X11_PID"
log "termux-x11 process exited. Session ended."
LAUNCHEOF
chmod +x "$PREFIX/bin/kdestart"
ok "Installed 'kdestart' command."

cat > "$PREFIX/bin/kdestop" << 'STOPEOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "Stopping Plasma session..."
pkill -f termux-x11 2>/dev/null
pkill -f startplasma-x11 2>/dev/null
pkill -f dbus-launch 2>/dev/null
pkill -f pulseaudio 2>/dev/null
echo "Done."
STOPEOF
chmod +x "$PREFIX/bin/kdestop"
ok "Installed 'kdestop' command."

### 6. Done ######################################################################
ok "Installation complete!"
echo ""
echo -e "${GREEN}Usage:${NC}"
echo "  kdestart          # Launch Plasma with Turnip+Zink (default)"
echo "  kdestart virgl    # Launch Plasma with VirGL fallback"
echo "  kdestart software # Launch Plasma with software rendering (diagnostic)"
echo "  kdestop           # Kill the running Plasma/X11 session"
echo ""
echo "Open the Termux:X11 Android app after running kdestart."
echo "Install it from: https://github.com/termux/termux-x11/releases"
echo ""
echo "Log files:"
echo "  ~/kde-plasma-install.log   (this installer)"
echo "  ~/plasma-session.log       (each kdestart run)"
