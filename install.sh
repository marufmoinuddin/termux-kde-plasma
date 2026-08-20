#!/data/data/com.termux/files/usr/bin/bash
###############################################################################
# install.sh
# One-click installer: Native KDE Plasma on Termux via Termux:X11
#
# GPU acceleration:
#   - Turnip (Vulkan) + Zink (GL-over-Vulkan) : Adreno 6xx/8xx (default)
#   - VirGL fallback                           : wider device support
#   - software (llvmpipe)                      : diagnostic / no-GPU mode
#
# Inspired by the structure & conventions of sabamdarif/termux-desktop.
# Repo: https://github.com/marufmoinuddin/termux-kde-plasma
#
# This script is self-contained: it can be sourced from a clone OR streamed
# straight into bash (curl | bash). It writes every helper it needs into
# $PREFIX/bin, so it never depends on the rest of the repository at runtime.
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
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
W='\033[1;37m'; C='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

# Defaults (overridable)
GPU_NAME="${GPU_NAME:-}"
KDESTART_GPU_MODE="zink"
XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"
CHOOSE_GPU_MODE="ask"

###############################################################################
#
#  Logging helpers
#
###############################################################################

log_debug()  { echo -e "${C}[${BOLD}..${NC}${C}]${NC} $*" | tee -a "$LOG_FILE"; }
log_warn()   { echo -e "${Y}[${BOLD}!!${NC}${Y}]${NC} $*" | tee -a "$LOG_FILE"; }
log_error()  { echo -e "${R}[${BOLD}xx${NC}${R}]${NC} $*" | tee -a "$LOG_FILE"; }
print_success() { echo -e "${G}[${BOLD}✓${NC}${G}]${NC} $*" | tee -a "$LOG_FILE"; }
print_failed()  { echo -e "${R}[${BOLD}☓${NC}${R}]${NC} $*" | tee -a "$LOG_FILE"; }
print_msg()     { echo -e "${B}[${BOLD}•${NC}${B}]${NC} $*" | tee -a "$LOG_FILE"; }

banner() {
    echo ""
    echo -e "  ${BOLD}${B}═══ KDE Plasma on Termux ═══${NC}"
    echo -e "  ${W}Native desktop · Turnip/Zink/VirGL GPU${NC}"
    echo -e "  ${C}https://github.com/${REPO_OWNER}/${REPO_NAME}${NC}"
    echo ""
}

cleanup_on_exit() {
    local code=$?
    echo ""
    if [[ $code -ne 0 ]]; then
        log_error "Installer did not finish. See $LOG_FILE for details."
    else
        print_success "Installer finished. Log saved to $LOG_FILE"
    fi
    exit "$code"
}
trap cleanup_on_exit EXIT

# Print a small wait-for-keypress prompt (only when interactive).
wait_for_keypress() {
    if [[ -t 0 ]]; then
        read -r -p "Press Enter to continue..." -s
        echo ""
    fi
}

###############################################################################
#
#  Environment validation
#
###############################################################################

check_termux() {
    if [[ ! -f /system/build.prop ]]; then
        print_failed "Not running on Android. This installer only works inside Termux."
        exit 1
    fi

    local tracer_pid tracer_name
    tracer_pid=$(grep TracerPid "/proc/$$/status" 2>/dev/null | cut -d $'\t' -f 2)
    if [[ "$tracer_pid" != "0" && -n "$tracer_pid" ]]; then
        tracer_name=$(grep Name "/proc/${tracer_pid}/status" 2>/dev/null | cut -d $'\t' -f 2)
        if [[ "$tracer_name" == "proot" ]]; then
            print_failed "Must not be executed under PRoot. Run natively in Termux."
            exit 1
        fi
    fi

    if [[ -z "$TERMUX_PREFIX" || "$TERMUX_PREFIX" != *"/com.termux/"* ]]; then
        print_failed "Please run this script inside Termux (PREFIX points at the Termux userland)."
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
        log_debug "Package manager not explicitly set; using 'pkg'."
    fi
    log_debug "Package manager: $PM"
}

###############################################################################
#
#  File & package helpers (with retry + recovery)
#
###############################################################################

check_and_create_directory() {
    if [[ ! -d "$1" ]]; then
        mkdir -p "$1" || { log_error "Cannot create directory $1"; return 1; }
    fi
}

# idempotent, prints current value when called with no arg
print_to_config() {
    local var_name="$1"
    local var_value="${2:-${!var_name}}"
    check_and_create_directory "$CONFIG_DIR" || return 1
    if [[ -f "$CONFIG_FILE" ]] && grep -q "^${var_name}=" "$CONFIG_FILE"; then
        # shellcheck disable=SC2155
        local tmp="${CONFIG_FILE}.tmp.$$"
        sed "s|^${var_name}=.*|${var_name}=${var_value}|" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    else
        echo "${var_name}=${var_value}" >> "$CONFIG_FILE"
    fi
    log_debug "config: $var_name = $var_value"
}

read_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Never `source` raw config — old configs have unquoted timestamp lines
        # (e.g. INSTALLED_AT=2026-08-20 22:09:12) that break bash. Parse only
        # the plain one-token KEY=value keys we need.
        local _k _v
        for _k in GPU_NAME KDESTART_GPU_MODE XKB_DEFAULT_LAYOUT; do
            _v=$(grep -E "^${_k}=[^ ]+$" "$CONFIG_FILE" 2>/dev/null | head -n1 | cut -d= -f2-)
            [[ -n "$_v" ]] && eval "${_k}=\"${_v}\"" 2>/dev/null || true
        done
        log_debug "Loaded existing config from $CONFIG_FILE"
    fi
}

# Manager-agnostic install with retry + recovery. Expects a space separated list.
package_install_and_check() {
    local pack
    for pack in $1; do
        install_package_with_retry "$pack"
    done
}

install_package_with_retry() {
    local package="$1"
    local retry_count=0
    local ok=false

    while [[ $retry_count -lt $MAX_INSTALL_RETRIES && "$ok" == false ]]; do
        retry_count=$((retry_count + 1))
        print_msg "Installing package: ${C}$package${NC} (attempt $retry_count/$MAX_INSTALL_RETRIES)"

        case "$PM" in
            pacman)
                rm -f "$TERMUX_PREFIX/var/lib/pacman/db.lck"
                pacman -S --noconfirm "$package" >>"$LOG_FILE" 2>&1
                if pacman -Qi "$package" >/dev/null 2>&1; then ok=true; fi
                ;;
            apt|pkg)
                apt install "$package" -y >>"$LOG_FILE" 2>&1
                if dpkg -s "$package" >/dev/null 2>&1; then
                    ok=true
                else
                    log_warn "Install failed for $package, attempting recovery..."
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
        print_failed "Could not install package: $package"
        return 1
    fi
    print_success "Installed: $package"
}

update_package_repos() {
    print_msg "Updating package repositories..."
    case "$PM" in
        pacman)
            pacman -Syu --noconfirm >>"$LOG_FILE" 2>&1 || log_warn "repo update had issues"
            ;;
        apt|pkg)
            apt update >>"$LOG_FILE" 2>&1 || log_warn "apt update had issues"
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
    if [[ -n "$GPU_NAME" && "$GPU_NAME" != "unknown" ]]; then
        return
    fi
    # Best-effort heuristics from getprop (ro.hardware / ro.board.platform / ro.soc.model)
    local hw plat soc
    hw=$(getprop ro.hardware 2>/dev/null)
    plat=$(getprop ro.board.platform 2>/dev/null)
    soc=$(getprop ro.soc.model 2>/dev/null)
    local blob="${hw} ${plat} ${soc}"
    if echo "$blob" | grep -qEiq "adreno|sm8[0-9][0-9]|sm[0-9]+"; then
        GPU_NAME="adreno"
    elif echo "$blob" | grep -qEiq "mali|t[0-9]{3}|bifrost|valhall"; then
        GPU_NAME="mali"
    elif echo "$blob" | grep -qEiq "xclipse|xs[0-9]+"; then
        GPU_NAME="xclipse"
    fi
    if [[ -z "$GPU_NAME" || "$GPU_NAME" == "unknown" ]]; then
        GPU_NAME="unknown"
        log_warn "Unable to auto-detect GPU. You will be asked to choose manually."
    else
        log_debug "Auto-detected GPU: $GPU_NAME"
    fi
}

ask_gpu_model() {
    banner
    print_warn "Select your device GPU to configure the correct driver stack."
    echo -e "\n  ${Y}1. Adreno${NC} (Qualcomm / Snapdragon)"
    echo -e "  ${Y}2. Mali${NC}   (Arm / MediaTek / many Exynos)"
    echo -e "  ${Y}3. Xclipse${NC} (Samsung / AMD RDNA2)"
    echo -e "  ${Y}4. Others${NC}  (generic / unstable hardware accel)"
    echo ""
    while true; do
        read -r -p "${Y}Enter your choice [1-4]: ${NC}" ans
        case "$ans" in
            1) GPU_NAME="adreno"; break ;;
            2) GPU_NAME="mali"; break ;;
            3) GPU_NAME="xclipse"; break ;;
            4) GPU_NAME="others"; break ;;
            *) log_warn "Invalid input, enter a number 1-4." ;;
        esac
    done
    print_success "GPU: $GPU_NAME"
}

ask_gpu_mode() {
    if [[ "$CHOOSE_GPU_MODE" != "ask" ]]; then
        return
    fi
    banner
    print_warn "Choose the default GPU acceleration mode for 'kdestart'."
    echo -e "\n  ${C}1. zink${NC}     - Turnip(Vulkan)+Zink(GL) : best perf on Adreno 6xx/8xx (default)"
    echo -e "  ${C}2. virgl${NC}    - VirGL fallback         : more stable, slightly slower"
    echo -e "  ${C}3. software${NC} - llvmpipe              : diagnostic only, no GPU"
    echo ""
    while true; do
        read -r -p "${Y}Enter your choice [1-3] (default 1): ${NC}" ans
        case "${ans:-1}" in
            1|zink) KDESTART_GPU_MODE="zink"; break ;;
            2|virgl) KDESTART_GPU_MODE="virgl"; break ;;
            3|software) KDESTART_GPU_MODE="software"; break ;;
            *) log_warn "Invalid input, enter 1, 2 or 3." ;;
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
    print_msg "Installing Termux:X11, Plasma, and core desktop apps..."
    package_install_and_check \
        "termux-x11-nightly pulseaudio dbus \
         plasma-desktop plasma-workspace plasma-integration plasma-pa \
         kwin-x11 kdecoration breeze breeze-icons \
         konsole dolphin kio-extras kde-cli-tools \
         xorg-xrandr xkeyboard-config openbox qt6ct"
}

install_gpu_packages() {
    case "$GPU_NAME" in
        adreno)
            print_msg "GPU: Adreno — installing Turnip + Zink + VirGL stack..."
            # Zink/Turnip for individual apps; VirGL for the compositor/session.
            # History: on Adreno 6xx/8xx the Zink compositor (globalShareContext)
            # crashes → black screen, so VirGL is the stable daily driver. Always
            # install both so `kdestart virgl` works as the stable fallback.
            package_install_and_check \
                "mesa mesa-zink-vulkan-icd-freedreno mesa-vulkan-icd-freedreno \
                 vulkan-loader-generic mesa-demos glmark2 \
                 virglrenderer virglrenderer-android angle-android"
            ;;
        mali)
            print_msg "GPU: Mali — installing Mesa + VirGL (Mali GLES lacks desktop GL)..."
            package_install_and_check \
                "mesa virglrenderer virglrenderer-android angle-android mesa-demos glmark2"
            ;;
        xclipse|others)
            print_msg "GPU: $GPU_NAME — installing Mesa + VirGL/ANGLE fallback..."
            package_install_and_check \
                "mesa virglrenderer virglrenderer-android angle-android mesa-demos glmark2"
            ;;
        *)
            print_msg "Installing generic Mesa stack..."
            package_install_and_check "mesa mesa-demos glmark2 virglrenderer-android"
            ;;
    esac
}

###############################################################################
#
#  Generate helper commands (kdestart / kdestop)
#
###############################################################################

create_kdestart() {
    local f="$TERMUX_PREFIX/bin/kdestart"
    print_msg "Writing $BOLD$f$NC"
    cat > "$f" <<'LAUNCHEOF'
#!/data/data/com.termux/files/usr/bin/bash
# kdestart - Launch native KDE Plasma via Termux:X11
# Usage: kdestart [zink|virgl|software|--nogpu|--help]
set -uo pipefail

readonly TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
readonly TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
readonly LOG_FILE="$TERMUX_HOME/plasma-session.log"
readonly CONFIG_FILE="$TERMUX_HOME/.config/termux-kde-plasma/config"
readonly DISPLAY_NUM=0

# Load persisted defaults — but NEVER `source` the raw file. Old configs
# contained unquoted timestamp lines (e.g. `INSTALLED_AT=2026-08-20 22:09:12`)
# that bash would word-split and choke on (": command not found"). We parse
# only the specific plain `KEY=value` keys we need, never eval arbitrary content.
_load_key() { # $1=key → outputs value if a clean ONE-TOKEN assignment exists
    local _k="$1" _v=""
    _v=$(grep -E "^${_k}=[^ ]+$" "$CONFIG_FILE" 2>/dev/null | head -n1 | cut -d= -f2-)
    [[ -n "$_v" ]] && printf '%s' "$_v"
}
if [[ -f "$CONFIG_FILE" ]]; then
    KDESTART_GPU_MODE="$(_load_key KDESTART_GPU_MODE)"
    GPU_MODE="$(_load_key GPU_MODE)"                     # legacy key
    XKB_DEFAULT_LAYOUT="$(_load_key XKB_DEFAULT_LAYOUT)"
fi
GPU_MODE="${1:-${KDESTART_GPU_MODE:-${GPU_MODE:-zink}}}"
XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"

log(){ echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG_FILE"; }

# Refuse to run under proot
TRACER_PID=$(grep TracerPid "/proc/$$/status" 2>/dev/null | cut -d $'\t' -f 2)
if [[ "$TRACER_PID" != "0" && -n "$TRACER_PID" ]]; then
    TRACER_NAME=$(grep Name "/proc/${TRACER_PID}/status" 2>/dev/null | cut -d $'\t' -f 2)
    if [[ "$TRACER_NAME" == "proot" ]]; then
        echo "kdestart must not run under PRoot." >&2; exit 1
    fi
fi

case "${1:-}" in
    --help|-h)
        echo "kdestart [zink|virgl|software]   Launch Plasma via Termux:X11"
        echo "  --help        show this help"
        exit 0;;
esac

: > "$LOG_FILE"
log "Starting Plasma (GPU mode: $GPU_MODE)"

# 1. Kill stale session
pkill -f termux-x11 2>/dev/null
pkill -f startplasma-x11 2>/dev/null
pkill -f dbus-launch 2>/dev/null
sleep 1

# 2. Clean stale X files
rm -rf "$TERMUX_PREFIX/tmp/.X${DISPLAY_NUM}-lock" \
       "$TERMUX_PREFIX/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null

# 3. Core X environment
export DISPLAY=":${DISPLAY_NUM}"
export XDG_RUNTIME_DIR="$TERMUX_HOME/.runtime"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export XAUTHORITY="${TERMUX_PREFIX}/tmp/.Xauthority"

# 4. PulseAudio (fixes "Daemon startup failed")
termux-wake-lock 2>/dev/null || true
pulseaudio --kill 2>/dev/null
sleep 1
rm -rf "$TERMUX_HOME/.config/pulse"
mkdir -p "$TMPDIR/pulse"; chmod 700 "$TMPDIR/pulse"
export PULSE_RUNTIME_PATH="$TMPDIR/pulse"
unset PULSE_SERVER
pulseaudio --start --exit-idle-time=-1 --disable-shm=1 \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    >>"$LOG_FILE" 2>&1
sleep 2
export PULSE_SERVER=127.0.0.1
pulseaudio --check >/dev/null 2>&1 \
    && log "PulseAudio started." || log "WARN: PulseAudio did not start."

# 5. GPU acceleration env
NOGPU=0
if [[ "$GPU_MODE" == "--nogpu" ]]; then NOGPU=1; GPU_MODE=software; fi
case "$GPU_MODE" in
    zink)
        export GALLIUM_DRIVER=zink
        export MESA_NO_ERROR=1
        export MESA_GL_VERSION_OVERRIDE=4.3COMPAT
        export MESA_GLES_VERSION_OVERRIDE=3.2
        export VK_ICD_FILENAMES="$TERMUX_PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json"
        export TU_DEBUG=noconform
        export MESA_VK_WSI_PRESENT_MODE=immediate
        export vblank_mode=0
        mkdir -p "$TERMUX_HOME/.cache/mesa_shader_cache"
        export MESA_SHADER_CACHE_DIR="$TERMUX_HOME/.cache/mesa_shader_cache"
        # Avoid Zink globalShareContext KWin crash
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
        log "VirGL configured."
        ;;
    software)
        export LIBGL_ALWAYS_SOFTWARE=1
        export GALLIUM_DRIVER=llvmpipe
        log "Software (llvmpipe) mode - diagnostics only."
        ;;
    *)
        echo "Unknown GPU_MODE '$GPU_MODE'. Use zink, virgl, software, or --nogpu." >&2
        exit 1;;
esac
if [[ "$NOGPU" -eq 1 ]]; then export LIBGL_ALWAYS_SOFTWARE=1; fi

# 6. Start Termux:X11 and wait for socket
log "Launching termux-x11 on display :$DISPLAY_NUM..."
termux-x11 ":$DISPLAY_NUM" -xstartup "dbus-launch --exit-with-session startplasma-x11" >>"$LOG_FILE" 2>&1 &
X11_PID=$!
SOCKET="$TERMUX_PREFIX/tmp/.X11-unix/X${DISPLAY_NUM}"
for i in $(seq 1 20); do
    [[ -e "$SOCKET" ]] && { log "X socket ready after ${i}s."; break; }
    sleep 1
done
if [[ ! -e "$SOCKET" ]]; then
    log "ERROR: X socket never appeared. See $LOG_FILE."
    exit 1
fi
sleep 2

# 7. Keyboard layout
export DISPLAY=":$DISPLAY_NUM"
setxkbmap "$XKB_DEFAULT_LAYOUT" 2>>"$LOG_FILE" \
    && log "Keyboard layout: $XKB_DEFAULT_LAYOUT"

# 8. Best-effort renderer check
if command -v glxinfo >/dev/null 2>&1; then
    RENDERER=$(DISPLAY=:$DISPLAY_NUM glxinfo -B 2>>"$LOG_FILE" | grep -i "OpenGL renderer" || true)
    log "Renderer: ${RENDERER:-unknown}"
    if echo "$RENDERER" | grep -qi "llvmpipe" && [[ "$GPU_MODE" != "software" ]]; then
        log "WARN: llvmpipe detected despite GPU mode $GPU_MODE."
    fi
fi

log "Open the Termux:X11 Android app now to see Plasma."
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
# kdestop - stop Termux:X11 / Plasma / PulseAudio session
readonly TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
pkill -f termux-x11 2>/dev/null
pkill -f startplasma-x11 2>/dev/null
pkill -f dbus-launch 2>/dev/null
pkill -f virgl_test_server 2>/dev/null
# PulseAudio has --exit-idle-time=-1 and --start on demand; leave it but release lock
rm -f "$TERMUX_PREFIX/tmp/.X0-lock" "$TERMUX_PREFIX/tmp/.X11-unix/X0" 2>/dev/null
termux-wake-unlock 2>/dev/null || true
echo "Plasma session stopped."
STOPEOF
    chmod +x "$f"
    print_success "Installed 'kdestop'."
}

create_completions() {
    # bash completion for kdestart
    if [[ ! -d "$TERMUX_PREFIX/etc/bash_completion.d" ]]; then
        mkdir -p "$TERMUX_PREFIX/etc/bash_completion.d"
    fi
    cat > "$TERMUX_PREFIX/etc/bash_completion.d/kdestart" <<'BCOMP'
#!/data/data/com.termux/files/usr/bin/bash
_kdestart_completions() {
    local cur
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=($(compgen -W "zink virgl software --nogpu --help" -- "$cur"))
}
complete -F _kdestart_completions kdestart
BCOMP
    print_success "Wrote bash completion for kdestart."
}

create_kdapp() {
    local f="$TERMUX_PREFIX/bin/kdapp"
    print_msg "Writing $BOLD$f$NC"
    cat > "$f" <<'KAPPEOF'
#!/data/data/com.termux/files/usr/bin/bash
# kdapp - launch ONE app in a lightweight Termux:X11 session (no full Plasma).
# Adds a minimal Openbox window manager (resize/move) + qt6ct theming.
#   kdapp konsole | kdapp dolphin | kdapp chromium
# PITFALL: never `pkill -f <app>` here — the script could match its own args
# and self-kill (the launch-konsole.sh bug). Match the -xstartup pattern only.
set -uo pipefail

readonly TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
readonly TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
readonly LOG_FILE="$TERMUX_HOME/kdapp-session.log"
readonly APP="${1:-konsole}"

: > "$LOG_FILE"
log(){ echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG_FILE"; }
log "Starting single-app session: $APP"

pkill -f "exit-with-session $APP" 2>/dev/null
pkill -f "termux-x11 :1" 2>/dev/null
sleep 1
rm -f "$TERMUX_PREFIX/tmp/.X1-lock" "$TERMUX_PREFIX/tmp/.X11-unix/X1" 2>/dev/null

export DISPLAY=:1
export XDG_RUNTIME_DIR="$TERMUX_HOME/.runtime"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

if command -v qt6ct >/dev/null 2>&1; then
    export QT_QPA_PLATFORMTHEME=qt6ct
fi

pulseaudio --kill 2>/dev/null; sleep 1
rm -rf "$TERMUX_HOME/.config/pulse"
mkdir -p "$TMPDIR/pulse"; chmod 700 "$TMPDIR/pulse"
export PULSE_RUNTIME_PATH="$TMPDIR/pulse"
unset PULSE_SERVER
pulseaudio --start --exit-idle-time=-1 --disable-shm=1 \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    >>"$LOG_FILE" 2>&1
sleep 1
export PULSE_SERVER=127.0.0.1

log "Launching termux-x11 :1 with Openbox + $APP..."
termux-x11 :1 -xstartup \
    "dbus-launch --exit-with-session sh -c 'openbox & sleep 1 && $APP --nofork'" \
    >>"$LOG_FILE" 2>&1 &
X11_PID=$!

SOCKET="$TERMUX_PREFIX/tmp/.X11-unix/X1"
for i in $(seq 1 20); do
    [[ -e "$SOCKET" ]] && { log "X socket ready after ${i}s."; break; }
    sleep 1
done
[[ -e "$SOCKET" ]] || { log "ERROR: X socket never appeared ($SOCKET)."; exit 1; }
sleep 2

log "Open the Termux:X11 app (display :1) to see $APP."
wait "$X11_PID"
log "Session ended."
KAPPEOF
    chmod +x "$f"
    print_success "Installed 'kdapp' (single-app launcher)."
}

# Optional: Chromium + the per-backend launchers worked out in our history.
install_optional_browser() {
    banner
    echo ""
    echo -e "  ${BOLD}Optional: ${Y}Chromium browser${NC}"
    echo -e "  Install Chromium plus launch helpers for the two GPU paths we debugged:"
    echo -e "    ${C}chromium-vgl.sh${NC}    VirGL (stable, default for Chrome on Termux:X11)"
    echo -e "    ${C}chromium-turnip.sh${NC} Turnip via ANGLE-Vulkan (fast, WebGL can be flaky)"
    echo ""
    while true; do
        read -r -p "${Y}Install Chromium + launchers? [y/N]: ${NC}" ans
        case "${ans,,}" in
            y|yes) break ;;
            n|no|"") print_msg "Skipping Chromium."; return 0 ;;
            *) log_warn "Invalid input, enter y or n." ;;
        esac
    done

    package_install_and_check "chromium"

    local vgl="$TERMUX_PREFIX/bin/chromium-vgl.sh"
    cat > "$vgl" <<'VGL'
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
    chmod +x "$vgl"

    local ntv="$TERMUX_PREFIX/bin/chromium-turnip.sh"
    cat > "$ntv" <<'NTV'
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
    chmod +x "$ntv"
    print_success "Installed Chromium + chromium-vgl.sh / chromium-turnip.sh."
}

###############################################################################
#
#  Finish / usage
#
###############################################################################

print_usage() {
    banner
    print_success "KDE Plasma installed & configured for GPU: $GPU_NAME"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "    ${G}kdestart${NC}           Launch Plasma with ${C}${KDESTART_GPU_MODE}${NC} (default)"
    echo -e "    ${G}kdestart virgl${NC}     Launch with VirGL fallback"
    echo -e "    ${G}kdestart software${NC}  Launch with software rendering (diagnostic)"
    echo -e "    ${G}kdestart --nogpu${NC}   Launch without GPU env"
    echo -e "    ${G}kdestop${NC}            Stop the Plasma/X11 session"
    echo -e "    ${G}kdapp konsole${NC}      Launch ONE app (Konsole) in a light session"
    echo -e "    ${G}chromium-vgl.sh${NC}    Chromium on VirGL (if Chromium installed)"
    echo -e "    ${G}chromium-turnip.sh${NC} Chromium on Turnip via ANGLE-Vulkan (if installed)"
    echo ""
    echo -e "  Open the ${BOLD}Termux:X11${NC} Android app after running kdestart."
    echo -e "  Get Termux:X11: ${C}https://github.com/termux/termux-x11/releases${NC}"
    echo ""
    echo -e "  Install log: ${B}$LOG_FILE${NC}"
    echo -e "  Session log: ${B}$TERMUX_HOME/plasma-session.log${NC}"
}

###############################################################################
#
#  Main
#
###############################################################################

main() {
    banner
    : > "$LOG_FILE"
    log_debug "Starting KDE Plasma installer for Termux ($TERMUX_ARCH)"

    check_termux
    detect_package_manager
    read_config
    detect_gpu_name
    if [[ "$GPU_NAME" == "unknown" ]]; then
        ask_gpu_model
    fi
    ask_gpu_mode

    install_base_repos
    install_core_packages
    install_gpu_packages

    # Persist choices
    print_to_config "GPU_NAME" "$GPU_NAME"
    print_to_config "KDESTART_GPU_MODE" "$KDESTART_GPU_MODE"
    print_to_config "XKB_DEFAULT_LAYOUT" "$XKB_DEFAULT_LAYOUT"

    create_kdestart
    create_kdestop
    create_completions
    create_kdapp

    # Optional Chromium + GPU launchers (asked only when interactive)
    install_optional_browser

    print_usage
}

main "$@"
