#!/data/data/com.termux/files/usr/bin/bash
###############################################################################
# install.sh
# One-click installer: Native KDE Plasma on Termux via Termux:X11
#
# GPU strategy (auto-detected, never one-size-fits-all):
#   Adreno/native  : Turnip (Vulkan) + Zink (GL-over-Vulkan)
#                    -> `kdestart` (default)  [SD 870 / Adreno 650, 8 Elite / 830]
#   Mali/MediaTek/ : VirGL (virpipe) fallback
#   Xclipse/others   -> `kdestart virgl`
#   software       : llvmpipe diagnostic    -> `kdestart software`
#
# Inspired by the structure & conventions of:
#   - sabamdarif/termux-desktop
#   - LinuxDroidMaster/Termux-Desktops
# Repo: https://github.com/marufmoinuddin/termux-kde-plasma
#
# Self-contained: works from a clone OR streamed (curl | bash). Writes every
# helper into $PREFIX/bin, so it never depends on the rest of the repo at run.
###############################################################################

set -uo pipefail

# shellcheck disable=SC2034
readonly TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
readonly TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
# shellcheck disable=SC2155
readonly TERMUX_ARCH="$(uname -m)"
readonly REPO_OWNER="marufmoinuddin"
readonly REPO_NAME="termux-kde-plasma"

readonly CONFIG_DIR="${TERMUX_HOME}/.config/termux-kde-plasma"
readonly CONFIG_FILE="${CONFIG_DIR}/config"
readonly LOG_FILE="${TERMUX_HOME}/kde-plasma-install.log"
readonly MAX_INSTALL_RETRIES=3

# ANSI colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

# Tunables (overridable via env)
GPU_NAME="${GPU_NAME:-}"
KDESTART_GPU_MODE="zink"      # default accelerator mode for kdestart
XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"

###############################################################################
#
#  Logging helpers
#
###############################################################################

log_debug()  { echo -e "${C}[..]${NC} $*" | tee -a "$LOG_FILE"; }
log_warn()   { echo -e "${Y}[!!]${NC} $*" | tee -a "$LOG_FILE"; }
log_error()  { echo -e "${R}[xx]${NC} $*" | tee -a "$LOG_FILE"; }
print_success() { echo -e "${G}[✓]${NC} $*" | tee -a "$LOG_FILE"; }
print_failed()  { echo -e "${R}[☓]${NC} $*" | tee -a "$LOG_FILE"; }
print_msg()     { echo -e "${BOLD}[•]${NC} $*" | tee -a "$LOG_FILE"; }
print_warn()    { echo -e "${Y}[!!]${NC} $*" | tee -a "$LOG_FILE"; }

banner() {
    echo ""
    echo -e "  ${BOLD}═══ Native KDE Plasma for Termux ═══${NC}"
    echo -e "  Turnip+Zink (Adreno) · VirGL (Mali/MediaTek) · Termux:X11"
    echo -e "  ${C}https://github.com/${REPO_OWNER}/${REPO_NAME}${NC}"
    echo ""
}

cleanup_on_exit() {
    local code=$?
    echo ""
    if [[ $code -ne 0 ]]; then
        log_error "Installer did not finish. See $LOG_FILE."
    else
        print_success "Installer finished. Log: $LOG_FILE"
    fi
    exit "$code"
}
trap cleanup_on_exit EXIT

###############################################################################
#
#  Environment validation
#
###############################################################################

check_termux() {
    if [[ ! -f /system/build.prop ]]; then
        print_failed "Not running on Android. This installer requires Termux."
        exit 1
    fi
    local tracer_pid tracer_name
    tracer_pid=$(grep TracerPid "/proc/$$/status" 2>/dev/null | cut -d $'\t' -f 2)
    if [[ "$tracer_pid" != "0" && -n "$tracer_pid" ]]; then
        tracer_name=$(grep Name "/proc/${tracer_pid}/status" 2>/dev/null | cut -d $'\t' -f 2)
        if [[ "$tracer_name" == "proot" ]]; then
            print_failed "Must not run under PRoot. Launch natively in Termux."
            exit 1
        fi
    fi
    if [[ -z "$TERMUX_PREFIX" || "$TERMUX_PREFIX" != *"/com.termux/"* ]]; then
        print_failed "Run this inside Termux (PREFIX must point at the Termux userland)."
        exit 1
    fi
}

detect_package_manager() {
    # shellcheck disable=SC1091
    if [[ -f "$TERMUX_PREFIX/bin/termux-setup-package-manager" ]]; then
        source "$TERMUX_PREFIX/bin/termux-setup-package-manager"
    fi
    if [[ "${TERMUX_APP_PACKAGE_MANAGER:-}" == "apt" ]]; then
        PM="apt"
    elif [[ "${TERMUX_APP_PACKAGE_MANAGER:-}" == "pacman" ]]; then
        PM="pacman"
    else
        PM="pkg"
    fi
    log_debug "Package manager: $PM"
}

###############################################################################
#
#  Package helpers (retry + recovery)
#
###############################################################################

print_to_config() {
    local var_name="$1"
    local var_value
    var_value="${2:-${!var_name}}"
    mkdir -p "$CONFIG_DIR" || return 1
    if [[ -f "$CONFIG_FILE" ]] && grep -q "^${var_name}=" "$CONFIG_FILE"; then
        # shellcheck disable=SC2155
        local tmp="${CONFIG_FILE}.tmp.$$"
        sed "s|^${var_name}=.*|${var_name}=${var_value}|" "$CONFIG_FILE" > "$tmp" \
            && mv "$tmp" "$CONFIG_FILE"
    else
        echo "${var_name}=${var_value}" >> "$CONFIG_FILE"
    fi
    log_debug "config: $var_name = $var_value"
}

# Read only the SAFE one-token keys we need. NEVER `source` the raw config —
# legacy configs carried unquoted timestamp lines that break bash.
read_one_key() { # $1=key
    local _k="$1" _v=""
    _v=$(grep -E "^${_k}=[^ ]+$" "$CONFIG_FILE" 2>/dev/null | head -n1 | cut -d= -f2-)
    [[ -n "$_v" ]] && printf '%s' "$_v"
}
read_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        GPU_NAME="$(read_one_key GPU_NAME)"
        KDESTART_GPU_MODE="$(read_one_key KDESTART_GPU_MODE)"
        XKB_DEFAULT_LAYOUT="$(read_one_key XKB_DEFAULT_LAYOUT)"
        log_debug "Loaded saved config."
    fi
}

install_package_with_retry() {
    local package="$1" retry_count=0 ok=false
    while [[ $retry_count -lt $MAX_INSTALL_RETRIES && "$ok" == false ]]; do
        retry_count=$((retry_count + 1))
        print_msg "Installing: ${C}$package${NC} (attempt $retry_count/$MAX_INSTALL_RETRIES)"
        case "$PM" in
            pacman)
                rm -f "$TERMUX_PREFIX/var/lib/pacman/db.lck"
                pacman -S --noconfirm "$package" >>"$LOG_FILE" 2>&1
                pacman -Qi "$package" >/dev/null 2>&1 && ok=true
                ;;
            apt|pkg)
                apt install "$package" -y >>"$LOG_FILE" 2>&1
                if dpkg -s "$package" >/dev/null 2>&1; then
                    ok=true
                else
                    log_warn "Install failed for $package; recovering..."
                    {
                        dpkg --configure -a
                        apt --fix-broken install -y
                        apt install --fix-missing -y
                    } >>"$LOG_FILE" 2>&1
                fi
                ;;
        esac
    done
    if [[ "$ok" == false ]]; then
        print_failed "Could not install: $package"
        return 1
    fi
    print_success "Installed: $package"
}

package_install_and_check() {
    local pack
    for pack in $1; do
        install_package_with_retry "$pack"
    done
}

update_package_repos() {
    print_msg "Updating repositories..."
    case "$PM" in
        pacman) pacman -Syu --noconfirm >>"$LOG_FILE" 2>&1 || log_warn "upgrade issues" ;;
        apt|pkg)
            apt update >>"$LOG_FILE" 2>&1 || log_warn "apt update issues"
            apt upgrade -y >>"$LOG_FILE" 2>&1 || true
            ;;
    esac
}

###############################################################################
#
#  GPU detection
#
###############################################################################

detect_gpu_name() {
    if [[ -n "$GPU_NAME" && "$GPU_NAME" != "unknown" ]]; then return; fi
    local hw vulkan soc plat
    hw="$(getprop ro.hardware 2>/dev/null)"
    vulkan="$(getprop ro.hardware.vulkan 2>/dev/null)"
    soc="$(getprop ro.soc.model 2>/dev/null)"
    plat="$(getprop ro.board.platform 2>/dev/null)"
    local blob="${hw} ${vulkan} ${soc} ${plat}"
    if echo "$blob" | grep -qEiq "adreno|qcom|sm8[0-9]|sm[0-9]"; then
        GPU_NAME="adreno"
    elif echo "$blob" | grep -qEiq "mali|mt[0-9]{4}|bifrost|valhall|panfrost"; then
        GPU_NAME="mali"
    elif echo "$blob" | grep -qEiq "xclipse|xs[0-9]+|samsung.*exynos"; then
        GPU_NAME="xclipse"
    fi
    [[ -z "$GPU_NAME" ]] && GPU_NAME="unknown"
    if [[ "$GPU_NAME" == "unknown" ]]; then
        log_warn "Could not auto-detect GPU; you will be asked manually."
    else
        log_debug "Detected GPU: $GPU_NAME"
    fi
}

ask_gpu_model() {
    banner
    print_warn "Select your GPU family for the correct driver stack:"
    echo -e "\n  ${Y}1. Adreno${NC}   Qualcomm (Snapdragon) - native Turnip+Zink recommended"
    echo -e "  ${Y}2. Mali${NC}     Arm / MediaTek / Exynos - VirGL fallback"
    echo -e "  ${Y}3. Xclipse${NC}  Samsung / AMD RDNA2 - VirGL fallback"
    echo -e "  ${Y}4. Others${NC}   generic - VirGL software-ish fallback"
    echo ""
    while true; do
        read -r -p "${Y}Choice [1-4]: ${NC}" ans
        case "$ans" in
            1) GPU_NAME="adreno"; break ;;
            2) GPU_NAME="mali"; break ;;
            3) GPU_NAME="xclipse"; break ;;
            4) GPU_NAME="others"; break ;;
            *) log_warn "Enter 1-4." ;;
        esac
    done
    print_success "GPU: $GPU_NAME"
}

ask_gpu_mode() {
    # Default matches the detected hardware; allow override when interactive.
    case "$GPU_NAME" in
        adreno) KDESTART_GPU_MODE="zink" ;;
        *)      KDESTART_GPU_MODE="virgl" ;;
    esac
    # Non-interactive (curl | bash): keep the hardware-appropriate default,
    # honor a saved config, and skip the prompting menu entirely.
    if [[ ! -t 0 ]]; then
        print_success "Default GPU mode: $KDESTART_GPU_MODE (auto, non-interactive)"
        return 0
    fi
    banner
    print_warn "Default GPU mode for 'kdestart':"
    echo -e "\n  ${C}1. zink${NC}      Turnip+Zink native (Adreno 6xx/8xx) fastest"
    echo -e "  ${C}2. virgl${NC}     VirGL fallback (Mali/MediaTek/Xclipse, safer)"
    echo -e "  ${C}3. software${NC}  llvmpipe diagnostic only"
    echo ""
    while true; do
        read -r -p "${Y}Default [1-3] (recommended: ${C}${KDESTART_GPU_MODE}${Y}): ${NC}" ans
        case "${ans:-$KDESTART_GPU_MODE}" in
            zink|1) KDESTART_GPU_MODE="zink"; break ;;
            virgl|2) KDESTART_GPU_MODE="virgl"; break ;;
            software|3) KDESTART_GPU_MODE="software"; break ;;
            *) log_warn "Enter zink/virgl/software or 1-3." ;;
        esac
    done
    print_success "Default GPU mode: $KDESTART_GPU_MODE"
}

###############################################################################
#
#  Install stages
#
###############################################################################

install_base_repos() {
    print_msg "Enabling x11-repo and tur-repo..."
    package_install_and_check "x11-repo tur-repo"
    update_package_repos
}

install_core_packages() {
    print_msg "Installing Termux:X11 + Plasma + core apps..."
    package_install_and_check \
        "termux-x11-nightly pulseaudio dbus \
         plasma-desktop plasma-workspace plasma-integration plasma-pa \
         kwin-x11 kdecoration breeze kf6-breeze-icons \
         konsole dolphin kio-extras kde-cli-tools \
         xorg-xrandr xorg-setxkbmap openbox qt6ct"
}

install_gpu_packages() {
    # The native Adreno stack is mesa + mesa-vulkan-icd-freedreno (Turnip),
    # driven via Zink (GALLIUM_DRIVER=zink). NEVER install the old/conflicting
    # `mesa-zink` tur package (it conflicts with `mesa` and ships a 2023
    # megadriver that breaks GL - was the root cause of black screens).
    case "$GPU_NAME" in
        adreno)
            print_msg "GPU: Adreno - installing native Turnip + Zink (mesa + freedreno ICD)..."
            package_install_and_check \
                "mesa mesa-vulkan-icd-freedreno mesa-vulkan-icd-swrast \
                 vulkan-loader-generic mesa-demos glmark2"
            ;;
        mali|xclipse|others)
            print_msg "GPU: $GPU_NAME - installing Mesa + VirGL fallback..."
            package_install_and_check \
                "mesa mesa-vulkan-icd-swrast \
                 virglrenderer virglrenderer-android angle-android \
                 vulkan-loader-generic mesa-demos glmark2"
            ;;
        *) # unknown: conservative - mesa + swrast so software mode always works
            print_msg "GPU: unknown - installing generic Mesa stack..."
            package_install_and_check \
                "mesa mesa-vulkan-icd-swrast vulkan-loader-generic mesa-demos glmark2"
            ;;
    esac
}

###############################################################################
#
#  Generate launcher helpers
#
###############################################################################

create_kdestart() {
    local f="$TERMUX_PREFIX/bin/kdestart"
    print_msg "Writing $BOLD$f$NC"
    cat > "$f" <<'LAUNCHEOF'
#!/data/data/com.termux/files/usr/bin/bash
# kdestart - Launch KDE Plasma (full desktop) or a single app via Termux:X11
# Usage:
#   kdestart                        full Plasma, saved/default GPU mode
#   kdestart zink|virgl|software    full Plasma with a specific GPU mode
#   kdestart --konsole              Konsole-only lightweight Openbox session
#   kdestart --app <name>           any single app lightweight Openbox session
#   kdestart --nogpu                full Plasma without the GPU env
#   kdestart --help
set -uo pipefail

readonly TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
readonly TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
readonly CONFIG_FILE="$TERMUX_HOME/.config/termux-kde-plasma/config"

_load_key() { # $1=key -> value (only clean one-token assignments, no eval, no source)
    local _k="$1" _v=""
    _v=$(grep -E "^${_k}=[^ ]+$" "$CONFIG_FILE" 2>/dev/null | head -n1 | cut -d= -f2-)
    [[ -n "$_v" ]] && printf '%s' "$_v"
}
if [[ -f "$CONFIG_FILE" ]]; then
    KDESTART_GPU_MODE="$(_load_key KDESTART_GPU_MODE)"
    GPU_MODE="$(_load_key GPU_MODE)"
    XKB_DEFAULT_LAYOUT="$(_load_key XKB_DEFAULT_LAYOUT)"
fi
XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"

log(){ echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG_FILE"; }

# Refuse under proot
TRACER_PID=$(grep TracerPid "/proc/$$/status" 2>/dev/null | cut -d $'\t' -f 2)
if [[ "$TRACER_PID" != "0" && -n "$TRACER_PID" ]]; then
    TRACER_NAME=$(grep Name "/proc/${TRACER_PID}/status" 2>/dev/null | cut -d $'\t' -f 2)
    [[ "$TRACER_NAME" == "proot" ]] && { echo "kdestart must not run under PRoot." >&2; exit 1; }
fi

# --- Argument parsing -------------------------------------------------------
MODE="plasma"; APP="konsole"; GPU_ARG=""
usage() {
    cat <<'HELP'
kdestart                        full Plasma, saved/default GPU mode
kdestart zink|virgl|software    full Plasma with a specific GPU mode
kdestart --konsole              Konsole-only lightweight Openbox session
kdestart --app <name>           any single app lightweight Openbox session
kdestart --nogpu                full Plasma without the GPU env
kdestart --help                 this help
HELP
    exit 0
}
case "${1:-}" in
    --help|-h)  usage ;;
    --konsole)  MODE="app"; APP="konsole" ;;
    --app)      MODE="app"; shift; APP="${1:-}" ;;
    --nogpu)    GPU_ARG="software" ;;
    zink|virgl|software) GPU_ARG="$1" ;;
    *) [[ -n "${1:-}" ]] && { echo "kdestart: unknown '$1' (try --help)" >&2; exit 1; } ;;
esac
[[ "$MODE" == "app" && -z "$APP" ]] && { echo "kdestart: --app needs a name" >&2; exit 1; }

readonly DISPLAY_NUM=0
GPU_MODE="${GPU_ARG:-${KDESTART_GPU_MODE:-${GPU_MODE:-zink}}}"
LOG_FILE="$TERMUX_HOME/plasma-session.log"
[[ "$MODE" == "app" ]] && LOG_FILE="$TERMUX_HOME/kdestart-app-session.log"

: > "$LOG_FILE"
log "Starting $( [[ "$MODE" == "app" ]] && echo "single-app ($APP)" || echo "Plasma" ) (GPU: $GPU_MODE)"

# 1. Kill stale session (only specific patterns; never bare $APP -> self-kill pitfall)
pkill -f termux-x11 2>/dev/null
pkill -f startplasma-x11 2>/dev/null
pkill -f dbus-launch 2>/dev/null
pkill -f "exit-with-session $APP" 2>/dev/null
sleep 1

# 2. Clean stale X files
rm -f "$TERMUX_PREFIX/tmp/.X0-lock" "$TERMUX_PREFIX/tmp/.X1-lock" \
      "$TERMUX_PREFIX/tmp/.X11-unix/X0" "$TERMUX_PREFIX/tmp/.X11-unix/X1" 2>/dev/null

# 3. Core X env (XDG_RUNTIME_DIR mirrors termux-desktop's tx11start: $TERMUX_PREFIX/tmp)
export DISPLAY=":$DISPLAY_NUM"
export XDG_RUNTIME_DIR="$TERMUX_PREFIX/tmp"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export XAUTHORITY="${TERMUX_PREFIX}/tmp/.Xauthority"
[[ "$MODE" == "app" ]] && command -v qt6ct >/dev/null 2>&1 && export QT_QPA_PLATFORMTHEME=qt6ct

ensure_kwin_breeze_theme() {
    local kwinrc="$TERMUX_HOME/.config/kwinrc"
    mkdir -p "$TERMUX_HOME/.config"
    if grep -q '^\[org\.kde\.kdecoration2\]$' "$kwinrc" 2>/dev/null && \
       grep -q '^theme=Breeze$' "$kwinrc" 2>/dev/null; then
        return 0
    fi
    cat >> "$kwinrc" <<'KWINRC'

[org.kde.kdecoration2]
library=org.kde.breeze
theme=Breeze
KWINRC
}

apply_termux_x11_preferences() {
    # Termux:X11 fullscreen can hide the top strip (titlebars/menu) behind the
    # Android app chrome on some devices/ROMs. Disable it unless the user
    # explicitly opts out, so Plasma starts with the full visible surface.
    case "${TERMUX_KDE_PLASMA_FULLSCREEN:-false}" in
        1|true|yes|on)
            log "Termux:X11 fullscreen override enabled by user; skipping preference repair."
            return 0
            ;;
    esac
    if command -v termux-x11-preference >/dev/null 2>&1; then
        termux-x11-preference "fullscreen"="false" >>"$LOG_FILE" 2>&1 || true
        log "Requested Termux:X11 windowed mode (fullscreen=false)."
    else
        log "termux-x11-preference not found; skipping fullscreen repair."
    fi
}

# 4. PulseAudio
termux-wake-lock 2>/dev/null || true
pulseaudio --kill 2>/dev/null; sleep 1
rm -rf "$TERMUX_HOME/.config/pulse"
mkdir -p "$TMPDIR/pulse"; chmod 700 "$TMPDIR/pulse"
export PULSE_RUNTIME_PATH="$TMPDIR/pulse"
unset PULSE_SERVER
pulseaudio --start --exit-idle-time=-1 --disable-shm=1 \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    >>"$LOG_FILE" 2>&1
sleep 2
export PULSE_SERVER=127.0.0.1
if pulseaudio --check >/dev/null 2>&1; then log "PulseAudio started."; else log "WARN: PulseAudio did not start."; fi

# 5. GPU env (native zink/turnip for adreno; virgl fallback; software diagnostic)
case "$GPU_MODE" in
    zink)
        export GALLIUM_DRIVER=zink
        export MESA_NO_ERROR=1
        export MESA_GL_VERSION_OVERRIDE=4.3COMPAT
        export MESA_GLES_VERSION_OVERRIDE=3.2
        # Turnip Vulkan ICD (Adreno) - native path
        export VK_ICD_FILENAMES="$TERMUX_PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json"
        export TU_DEBUG=noconform
        export MESA_LOADER_DRIVER_OVERRIDE=zink
        export MESA_VK_WSI_PRESENT_MODE=immediate
        export vblank_mode=0
        mkdir -p "$TERMUX_HOME/.cache/mesa_shader_cache"
        export MESA_SHADER_CACHE_DIR="$TERMUX_HOME/.cache/mesa_shader_cache"
        # KWin's GL compositor fails through Zink on this hardware -> force
        # XRender/QPainter so Plasma renders (applies to ALL plasma modes).
        export KWIN_COMPOSE=Q
        log "Zink + Turnip configured."
        ;;
    virgl)
        export GALLIUM_DRIVER=virpipe
        export MESA_NO_ERROR=1
        export MESA_GL_VERSION_OVERRIDE=4.3COMPAT
        export MESA_GLES_VERSION_OVERRIDE=3.2
        export LIBGL_DRI3_DISABLE=1
        export VIRGL_GPU_NUM=1
        pkill -f virgl_test_server 2>/dev/null
        virgl_test_server_android --use-egl-surfaceless --use-gles >/dev/null 2>&1 &
        export KWIN_COMPOSE=Q
        log "VirGL configured."
        ;;
    software)
        export GALLIUM_DRIVER=llvmpipe
        export LIBGL_ALWAYS_SOFTWARE=1
        log "Software (llvmpipe) mode - diagnostics."
        ;;
    *) echo "Unknown GPU_MODE '$GPU_MODE'." >&2; exit 1 ;;
esac

# 6. Session to start
if [[ "$MODE" == "app" ]]; then
    XSTARTUP="dbus-launch --exit-with-session sh -c 'openbox & sleep 1 && $APP --nofork'"
    log "Launching termux-x11 with Openbox + $APP..."
else
    XSTARTUP="dbus-launch --exit-with-session startplasma-x11"
    log "Launching termux-x11 with Plasma..."
fi
termux-x11 ":$DISPLAY_NUM" -xstartup "$XSTARTUP" >>"$LOG_FILE" 2>&1 &
X11_PID=$!

# Ask Termux:X11 to show the full surface area so Plasma titlebars/panel are
# not hidden under the app chrome on devices that launch in fullscreen mode.
sleep 2
apply_termux_x11_preferences

# 7. Wait for X socket
SOCKET="$TERMUX_PREFIX/tmp/.X11-unix/X${DISPLAY_NUM}"
for i in $(seq 1 20); do
    [[ -e "$SOCKET" ]] && { log "X socket ready after ${i}s."; break; }
    sleep 1
done
[[ -e "$SOCKET" ]] || { log "ERROR: X socket never appeared. See $LOG_FILE."; exit 1; }
sleep 2

# 8. Keyboard
export DISPLAY=":$DISPLAY_NUM"
command -v setxkbmap >/dev/null 2>&1 && setxkbmap "$XKB_DEFAULT_LAYOUT" 2>>"$LOG_FILE" \
    && log "Keyboard layout: $XKB_DEFAULT_LAYOUT"

# 9. Renderer check (best-effort)
if command -v glxinfo >/dev/null 2>&1; then
    RENDERER=$(DISPLAY=:$DISPLAY_NUM glxinfo -B 2>>"$LOG_FILE" | grep -i "OpenGL renderer" || true)
    log "Renderer: ${RENDERER:-unknown}"
fi

log "Open the Termux:X11 Android app now to see $( [[ "$MODE" == "app" ]] && echo "$APP" || echo "Plasma" )."
wait "$X11_PID"
log "termux-x11 exited. Session ended."
LAUNCHEOF
    chmod +x "$f"
    print_success "Installed 'kdestart'."
}

create_kdestop() {
    local f="$TERMUX_PREFIX/bin/kdestop"
    print_msg "Writing $BOLD$f$NC"
    cat > "$f" <<'STOPEOF'
#!/data/data/com.termux/files/usr/bin/bash
# kdestop - stop Termux:X11 / Plasma / PulseAudio
readonly TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
pkill -f termux-x11 2>/dev/null
pkill -f startplasma-x11 2>/dev/null
pkill -f dbus-launch 2>/dev/null
pkill -f virgl_test_server 2>/dev/null
rm -f "$TERMUX_PREFIX/tmp/.X0-lock" "$TERMUX_PREFIX/tmp/.X11-unix/X0" 2>/dev/null
termux-wake-unlock 2>/dev/null || true
echo "Plasma session stopped."
STOPEOF
    chmod +x "$f"
    print_success "Installed 'kdestop'."
}

create_completions() {
    if [[ ! -d "$TERMUX_PREFIX/etc/bash_completion.d" ]]; then
        mkdir -p "$TERMUX_PREFIX/etc/bash_completion.d"
    fi
    cat > "$TERMUX_PREFIX/etc/bash_completion.d/kdestart" <<'BCOMP'
#!/data/data/com.termux/files/usr/bin/bash
_kdestart_completions() {
    local cur
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    # shellcheck disable=SC2207
    COMPREPLY=($(compgen -W "zink virgl software --konsole --app --nogpu --help" -- "$cur"))
}
complete -F _kdestart_completions kdestart
BCOMP
    print_success "Bash completion for kdestart written."
}

install_optional_browser() {
    # Only prompt when interactive; skip silently otherwise
    if [[ ! -t 0 ]]; then print_msg "Non-interactive: skipping optional Chromium."; return 0; fi
    banner
    echo ""
    echo -e "  ${BOLD}Optional: ${Y}Chromium${NC} + GPU launchers (from our history):"
    echo -e "    ${C}chromium-vgl.sh${NC}    VirGL - stable for Chrome on Termux:X11"
    echo -e "    ${C}chromium-turnip.sh${NC} Turnip via ANGLE-Vulkan - fast, WebGL can be flaky"
    echo ""
    while true; do
        read -r -p "${Y}Install Chromium + launchers? [y/N]: ${NC}" ans
        case "${ans,,}" in
            y|yes) break ;;
            n|no|"") print_msg "Skipping Chromium."; return 0 ;;
            *) log_warn "Enter y or n." ;;
        esac
    done

    package_install_and_check "chromium"

    cat > "$TERMUX_PREFIX/bin/chromium-vgl.sh" <<'VGL'
#!/data/data/com.termux/files/usr/bin/bash
# chromium-vgl.sh - Chromium on VirGL (stable for Termux:X11)
set -uo pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
DISPLAY="${DISPLAY:-:0}"
command -v qt6ct >/dev/null 2>&1 && export QT_QPA_PLATFORMTHEME=qt6ct
exec env GALLIUM_DRIVER=virpipe DISPLAY="$DISPLAY" "$PREFIX/bin/chromium" \
    --use-gl=desktop --disable-gpu-vsync --disable-frame-rate-limit \
    --ignore-gpu-blocklist --disable-gpu-process-crash-limit "$@"
VGL
    chmod +x "$TERMUX_PREFIX/bin/chromium-vgl.sh"

    cat > "$TERMUX_PREFIX/bin/chromium-turnip.sh" <<'NTV'
#!/data/data/com.termux/files/usr/bin/bash
# chromium-turnip.sh - Chromium on Turnip via ANGLE-Vulkan (fast; WebGL flaky)
set -uo pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
DISPLAY="${DISPLAY:-:0}"
command -v qt6ct >/dev/null 2>&1 && export QT_QPA_PLATFORMTHEME=qt6ct
exec env DISPLAY="$DISPLAY" "$PREFIX/bin/chromium" \
    --use-angle=vulkan --use-vulkan=native \
    --enable-features=Vulkan,VaapiVideoDecoder \
    --enable-gpu-rasterization --enable-zero-copy \
    --ignore-gpu-blocklist "$@"
NTV
    chmod +x "$TERMUX_PREFIX/bin/chromium-turnip.sh"
    print_success "Chromium + chromium-vgl.sh / chromium-turnip.sh installed."
}

###############################################################################
#
#  Finish / usage
#
###############################################################################

print_usage() {
    banner
    print_success "KDE Plasma installed for GPU: ${GPU_NAME:-auto}. Default mode: $KDESTART_GPU_MODE"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "    ${G}kdestart${NC}               Launch Plasma with ${C}${KDESTART_GPU_MODE}${NC} (default)"
    echo -e "    ${G}kdestart zink${NC}          Launch Plasma on native Turnip+Zink"
    echo -e "    ${G}kdestart virgl${NC}         Launch Plasma on VirGL"
    echo -e "    ${G}kdestart software${NC}      Launch Plasma with software rendering (diagnostic)"
    echo -e "    ${G}kdestart --konsole${NC}     Konsole-only lightweight Openbox session"
    echo -e "    ${G}kdestart --app name${NC}    Launch ONE app in a light Openbox session"
    echo -e "    ${G}kdestart --nogpu${NC}       Launch without GPU env"
    echo -e "    ${G}kdestop${NC}               Stop the Plasma/X11 session"
    echo -e "    ${G}chromium-vgl.sh${NC}        Chromium on VirGL (if installed)"
    echo -e "    ${G}chromium-turnip.sh${NC}     Chromium on Turnip via ANGLE-Vulkan (if installed)"
    echo ""
    echo -e "  Open the ${BOLD}Termux:X11${NC} app after running kdestart."
    echo -e "  Get Termux:X11: ${C}https://github.com/termux/termux-x11/releases${NC}"
    echo ""
    echo -e "  Install log: ${Y}$LOG_FILE${NC}"
    echo -e "  Session log: ${Y}$TERMUX_HOME/plasma-session.log${NC}"
}

###############################################################################
#
#  Main
#
###############################################################################

main() {
    banner
    : > "$LOG_FILE"
    log_debug "KDE Plasma installer for Termux ($TERMUX_ARCH)"

    check_termux
    detect_package_manager
    read_config
    detect_gpu_name
    if [[ "$GPU_NAME" == "unknown" ]]; then ask_gpu_model; fi
    ask_gpu_mode

    install_base_repos
    install_core_packages
    install_gpu_packages

    print_to_config "GPU_NAME" "$GPU_NAME"
    print_to_config "KDESTART_GPU_MODE" "$KDESTART_GPU_MODE"
    print_to_config "XKB_DEFAULT_LAYOUT" "$XKB_DEFAULT_LAYOUT"

    create_kdestart
    create_kdestop
    create_completions
    install_optional_browser

    print_usage
}

main "$@"
