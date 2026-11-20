#!/usr/bin/env bash
# =============================================================================
#  Install dotfiles package dependencies
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$SCRIPT_DIR/packages"

# Colors for friendly output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}==>${NC} $*"; }
log_success() { echo -e "${GREEN}==>${NC} $*"; }
log_warn()    { echo -e "${YELLOW}==> WARNING:${NC} $*"; }
log_error()   { echo -e "${RED}==> ERROR:${NC} $*" >&2; }

is_termux() {
    [[ -n "${TERMUX_VERSION:-}" || -d "/data/data/com.termux/files/usr" ]]
}

is_nixos() {
    [[ -e "/etc/NIXOS" ]]
}

get_elevation() {
    if [[ $EUID -eq 0 ]] || is_termux; then
        echo ""
    elif command -v doas &>/dev/null; then
        echo "doas"
    elif command -v sudo &>/dev/null; then
        echo "sudo"
    else
        log_warn "Neither 'doas' nor 'sudo' found. Running commands directly."
        echo ""
    fi
}

load_packages() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_error "Package file not found: $file"
        exit 1
    fi
    # Filter comments and blank lines
    grep -vE '^\s*(#|$)' "$file" | tr '\n' ' '
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install package dependencies required by this dotfiles repository.
By default, automatically detects your environment (Termux, Desktop, or Headless).

Options:
  --cli         Force core terminal tools only (fish, starship, neovim, etc.)
  --desktop     Force core tools + desktop/Wayland environment (niri, ghostty, etc.)
  --all         Install all available packages for the detected environment
  --dry-run     Print commands and packages without installing
  -h, --help    Show this help message
EOF
}

# Parse options
MODE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cli)
            MODE="cli"
            shift
            ;;
        --desktop|--all)
            MODE="desktop"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

# Guard: NixOS check
if is_nixos; then
    log_info "NixOS detected."
    echo "Packages are managed declaratively via your nixos-config repository."
    echo "Please apply packages via: nixos-rebuild switch --flake <flake-path>"
    exit 0
fi

# Auto-detect mode if not explicitly set
if [[ -z "$MODE" ]]; then
    if is_termux; then
        MODE="cli"
        log_info "Auto-detected environment: Termux (CLI mode)"
    elif [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" || -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        MODE="desktop"
        log_info "Auto-detected environment: Graphical Desktop (Desktop mode)"
    else
        MODE="cli"
        log_info "Auto-detected environment: Headless / TTY (CLI mode)"
    fi
fi

# Elevation helper (doas / sudo)
ELEVATE="$(get_elevation)"

# --- 1. TERMUX ---
if is_termux; then
    log_info "Detected environment: Termux"
    if [[ "$MODE" == "desktop" ]]; then
        log_warn "Desktop environment requested, but running on Termux. Falling back to CLI packages."
    fi

    PKGS=$(load_packages "$PACKAGES_DIR/termux.txt")
    log_info "Target packages: $PKGS"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] pkg update && pkg install -y $PKGS"
    else
        log_info "Updating package lists..."
        pkg update
        log_info "Installing packages..."
        # shellcheck disable=SC2086
        pkg install -y $PKGS
        log_success "Termux packages successfully installed!"
    fi
    exit 0
fi

# --- 2. ARCH LINUX / CACHYOS ---
if command -v pacman &>/dev/null; then
    log_info "Detected distribution: Arch / CachyOS (pacman)"

    # Prefer AUR helper if present (for rofi-wayland, ghostty, etc.)
    AUR_HELPER=""
    if command -v paru &>/dev/null; then
        AUR_HELPER="paru"
    elif command -v yay &>/dev/null; then
        AUR_HELPER="yay"
    fi

    # Select package lists
    CLI_PKGS=$(load_packages "$PACKAGES_DIR/arch-cli.txt")
    DESKTOP_PKGS=""
    if [[ "$MODE" == "desktop" ]]; then
        DESKTOP_PKGS=$(load_packages "$PACKAGES_DIR/arch-desktop.txt")
    fi

    ALL_PKGS="$CLI_PKGS $DESKTOP_PKGS"
    log_info "Mode: $MODE"
    log_info "Target packages: $ALL_PKGS"

    if [[ "$DRY_RUN" == true ]]; then
        if [[ -n "$AUR_HELPER" ]]; then
            echo "[dry-run] $AUR_HELPER -S --needed $ALL_PKGS"
        else
            echo "[dry-run] $ELEVATE pacman -S --needed $ALL_PKGS"
        fi
    else
        log_info "Installing packages..."
        if [[ -n "$AUR_HELPER" ]]; then
            log_info "Using AUR helper: $AUR_HELPER"
            # shellcheck disable=SC2086
            $AUR_HELPER -S --needed $ALL_PKGS
        else
            # shellcheck disable=SC2086
            ${ELEVATE:+$ELEVATE }pacman -S --needed $ALL_PKGS
        fi
        log_success "Arch/CachyOS packages successfully installed!"
    fi

    # Offer/Check mise installation
    if ! command -v mise &>/dev/null; then
        echo ""
        log_info "Note: 'mise' (runtime manager) is not currently installed."
        echo "To install mise, run: curl https://mise.run | sh"
    fi
    exit 0
fi

# --- 3. DEBIAN / UBUNTU ---
if command -v apt &>/dev/null; then
    log_info "Detected distribution: Debian / Ubuntu (apt)"

    PKG_MANAGER="apt"
    if command -v nala &>/dev/null; then
        PKG_MANAGER="nala"
        log_info "Using apt frontend: nala"
    fi

    CLI_PKGS=$(load_packages "$PACKAGES_DIR/debian-cli.txt")
    log_info "Mode: $MODE"
    log_info "Target packages: $CLI_PKGS"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] ${ELEVATE:+$ELEVATE }$PKG_MANAGER update"
        echo "[dry-run] ${ELEVATE:+$ELEVATE }$PKG_MANAGER install -y $CLI_PKGS"
    else
        log_info "Updating package lists..."
        # shellcheck disable=SC2086
        ${ELEVATE:+$ELEVATE }$PKG_MANAGER update
        log_info "Installing packages..."
        # shellcheck disable=SC2086
        ${ELEVATE:+$ELEVATE }$PKG_MANAGER install -y $CLI_PKGS

        # Symlink batcat -> bat and fdfind -> fd into ~/.local/bin if needed
        mkdir -p "$HOME/.local/bin"
        if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
            ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
            log_info "Symlinked batcat -> ~/.local/bin/bat"
        fi
        if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
            ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
            log_info "Symlinked fdfind -> ~/.local/bin/fd"
        fi

        log_success "Debian/Ubuntu packages successfully installed!"
    fi

    # Offer/Check mise installation
    if ! command -v mise &>/dev/null; then
        echo ""
        log_info "Note: 'mise' (runtime manager) is not currently installed."
        echo "To install mise, run: curl https://mise.run | sh"
    fi
    exit 0
fi

# --- 4. OTHER DISTRIBUTIONS ---
log_error "Unsupported distribution for automated package installation."
echo "Please manually install the required packages listed in: $PACKAGES_DIR/"
exit 1
