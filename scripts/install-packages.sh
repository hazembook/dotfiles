#!/usr/bin/env bash
# =============================================================================
#  Install dotfiles package dependencies
#  Declarative, verbose package manager across Arch, Debian, and Termux.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$SCRIPT_DIR/packages"
INVENTORY_FILE="$PACKAGES_DIR/dotfiles-packages.yaml"
RESOLVER_SCRIPT="$PACKAGES_DIR/resolve-packages.py"

# Colors for terminal output
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install package dependencies required by this dotfiles repository.
Reads definitions declaratively from scripts/packages/dotfiles-packages.yaml.

Options:
  --cli         Force CLI profile (core shell, dev, typesetting tools)
  --desktop     Force Desktop profile (includes Wayland compositor, audio, fonts)
  --all         Alias for --desktop
  --dry-run     Inspect and print packages without installing
  --verbose, -v Show status for every declared package
  -h, --help    Show this help message
EOF
}

# Parse options
MODE=""
DRY_RUN=false
VERBOSE=false

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
        --verbose|-v)
            VERBOSE=true
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

# Detect distribution
DISTRO=""
if is_termux; then
    DISTRO="termux"
elif command -v pacman &>/dev/null; then
    DISTRO="arch"
elif command -v apt &>/dev/null; then
    DISTRO="debian"
else
    log_error "Unsupported distribution for automated package installation."
    exit 1
fi

# Detect or apply profile
PROFILE="$MODE"
if [[ -z "$PROFILE" ]]; then
    if [[ "$DISTRO" == "termux" ]]; then
        PROFILE="termux"
    elif [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" || -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        PROFILE="desktop"
    else
        PROFILE="cli"
    fi
fi

# Elevation helper (doas / sudo)
ELEVATE="$(get_elevation)"

# Determine frontend package manager command
PKG_TOOL=""
if [[ "$DISTRO" == "arch" ]]; then
    if command -v paru &>/dev/null; then
        PKG_TOOL="paru"
    elif command -v yay &>/dev/null; then
        PKG_TOOL="yay"
    else
        PKG_TOOL="pacman"
    fi
elif [[ "$DISTRO" == "debian" ]]; then
    if command -v nala &>/dev/null; then
        PKG_TOOL="nala"
    else
        PKG_TOOL="apt"
    fi
elif [[ "$DISTRO" == "termux" ]]; then
    PKG_TOOL="pkg"
fi

# Print banner
echo -e "${CYAN}================================================================================${NC}"
echo -e "${BOLD}  Hazem's Dotfiles Package Manager${NC}"
echo -e "${CYAN}================================================================================${NC}"
log_info "Detected OS       : ${BOLD}$DISTRO${NC}"
log_info "Active Profile    : ${BOLD}$PROFILE${NC}"
log_info "Package Frontend  : ${BOLD}$PKG_TOOL${NC}"
log_info "Inventory File    : ${BOLD}$INVENTORY_FILE${NC}"
echo ""

# Verify Python resolver
if ! command -v python3 &>/dev/null; then
    log_error "Python 3 is required to resolve package declarations."
    exit 1
fi

log_info "Evaluating package status against system database..."

INSPECT_OUTPUT="$(python3 "$RESOLVER_SCRIPT" \
    --file "$INVENTORY_FILE" \
    --distro "$DISTRO" \
    --profile "$PROFILE" \
    --format inspect)"

TOTAL_COUNT=0
INSTALLED_COUNT=0
MISSING_COUNT=0

INSTALLED_PKGS=()
MISSING_PKGS=()

while IFS=$'\t' read -r canonical target mod is_inst ver; do
    [[ -z "$canonical" ]] && continue
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    if [[ "$is_inst" == "1" ]]; then
        INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
        INSTALLED_PKGS+=("$target ($ver)")
        if [[ "$VERBOSE" == true ]]; then
            echo -e "  ${GREEN}[✓]${NC} $target ${BOLD}$ver${NC} (module: $mod)"
        fi
    else
        MISSING_COUNT=$((MISSING_COUNT + 1))
        MISSING_PKGS+=("$target")
        echo -e "  ${YELLOW}[+]${NC} missing: ${BOLD}$target${NC} (module: $mod)"
    fi
done <<< "$INSPECT_OUTPUT"

echo ""
echo -e "${CYAN}--- Execution Summary ----------------------------------------------------------${NC}"
echo -e "  Total evaluated   : ${BOLD}$TOTAL_COUNT${NC}"
echo -e "  Already installed : ${GREEN}$INSTALLED_COUNT${NC}"
echo -e "  Missing / To install: ${YELLOW}$MISSING_COUNT${NC}"
echo -e "${CYAN}--------------------------------------------------------------------------------${NC}"

if [[ $MISSING_COUNT -eq 0 ]]; then
    log_success "All packages for profile '${BOLD}$PROFILE${NC}' are already installed! Nothing to do."
    exit 0
fi

# Construct command line
CMD_ARRAY=()
if [[ "$DISTRO" == "arch" ]]; then
    if [[ "$PKG_TOOL" == "paru" || "$PKG_TOOL" == "yay" ]]; then
        CMD_ARRAY=("$PKG_TOOL" "-S" "--needed" "${MISSING_PKGS[@]}")
    else
        if [[ -n "$ELEVATE" ]]; then
            CMD_ARRAY=("$ELEVATE" "pacman" "-S" "--needed" "${MISSING_PKGS[@]}")
        else
            CMD_ARRAY=("pacman" "-S" "--needed" "${MISSING_PKGS[@]}")
        fi
    fi
elif [[ "$DISTRO" == "debian" ]]; then
    if [[ -n "$ELEVATE" ]]; then
        CMD_ARRAY=("$ELEVATE" "$PKG_TOOL" "install" "-y" "${MISSING_PKGS[@]}")
    else
        CMD_ARRAY=("$PKG_TOOL" "install" "-y" "${MISSING_PKGS[@]}")
    fi
elif [[ "$DISTRO" == "termux" ]]; then
    CMD_ARRAY=("pkg" "install" "-y" "${MISSING_PKGS[@]}")
fi

echo ""
log_info "Command to execute:"
echo -e "  ${BOLD}${CMD_ARRAY[*]}${NC}"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    log_info "[dry-run] Dry-run enabled. Exiting without changes."
    exit 0
fi

# Execute installation
log_info "Starting package installation..."
"${CMD_ARRAY[@]}"

log_success "Package installation completed successfully!"

# Post-install normalization hooks
if [[ "$DISTRO" == "debian" ]]; then
    mkdir -p "$HOME/.local/bin"
    if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
        ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
        log_info "Normalized: symlinked batcat -> ~/.local/bin/bat"
    fi
    if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
        log_info "Normalized: symlinked fdfind -> ~/.local/bin/fd"
    fi
fi

# Suggest mise runtime manager on standard Linux if not found (on Termux, native pkg runtimes are preferred)
if ! is_termux && ! command -v mise &>/dev/null; then
    echo ""
    log_info "Note: 'mise' (runtime manager for node, go, python) is not installed."
    echo "To install mise, run: curl https://mise.run | sh"
fi
