#!/usr/bin/env bash
# =============================================================================
#  Hazem's Dotfiles Link Manager
#  Symlink configuration files and directories into $HOME.
# =============================================================================
set -euo pipefail

DOTS="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/backups/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# Terminal styling
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

format_path() {
    local p="$1"
    if [[ "$p" == "$HOME"* ]]; then
        echo "~${p#"$HOME"}"
    else
        echo "$p"
    fi
}

is_termux() {
    [[ -n "${TERMUX_VERSION:-}" || -d "/data/data/com.termux/files/usr" ]]
}

# Delegate --packages early if passed as first argument
if [[ "${1:-}" == "--packages" || "${1:-}" == "-p" ]]; then
    shift
    exec "$DOTS/scripts/install-packages.sh" "$@"
fi

# =============================================================================
#  Managed Symlink Definitions
#  Format: "type|src_relative_to_DOTS|target_absolute"
# =============================================================================
COMMON_LINKS=(
    "file|bash/.bashrc|$HOME/.bashrc"
    "file|fish/config.fish|$HOME/.config/fish/config.fish"
    "dir|nvim|$HOME/.config/nvim"
    "dir|doom|$HOME/.config/doom"
    "dir|fastfetch|$HOME/.config/fastfetch"
    "file|tmux/.tmux.conf|$HOME/.tmux.conf"
    "file|tmux.conf.local|$HOME/.tmux.conf.local"
    "file|git/config|$HOME/.config/git/config"
    "file|atuin/config.toml|$HOME/.config/atuin/config.toml"
)

DESKTOP_LINKS=(
    "dir|niri|$HOME/.config/niri"
    "dir|noctalia|$HOME/.config/noctalia"
    "file|ghostty/config|$HOME/.config/ghostty/config"
    "file|alacritty/alacritty.toml|$HOME/.config/alacritty/alacritty.toml"
    "dir|alacritty/themes|$HOME/.config/alacritty/themes"
    "dir|rofi|$HOME/.config/rofi"
    "file|zed/settings.json|$HOME/.config/zed/settings.json"
    "file|zed/keymap.json|$HOME/.config/zed/keymap.json"
    "file|opencode/opencode.json|$HOME/.config/opencode/opencode.json"
    "file|opencode/cli.json|$HOME/.config/opencode/cli.json"
    "file|opencode/AGENTS.md|$HOME/.config/opencode/AGENTS.md"
    "dir|opencode/agents|$HOME/.config/opencode/agents"
)

TERMUX_LINKS=(
    # Add Termux-only links here if needed, e.g.:
    # "file|termux/termux.properties|$HOME/.termux/termux.properties"
)

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Symlink dotfiles into \$HOME.

Options:
  --check, -c           Inspect and verify status of all managed symlinks
  --dry-run, -n         Simulate actions without modifying the filesystem
  --verbose, -v         Display detailed status for every managed target
  --cli                 Use CLI profile (Common shell & dev tools)
  --desktop             Use Desktop profile (Common + Wayland GUI tools)
  --packages, -p [...]  Install package dependencies via scripts/install-packages.sh
  -h, --help            Show this help message
EOF
}

# =============================================================================
#  Option Parsing & Profile Detection
# =============================================================================
CHECK_MODE=false
DRY_RUN=false
VERBOSE=false
PROFILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check|-c)
            CHECK_MODE=true
            shift
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --cli)
            PROFILE="cli"
            shift
            ;;
        --desktop)
            PROFILE="desktop"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$PROFILE" ]]; then
    if is_termux; then
        PROFILE="termux"
    else
        PROFILE="desktop"
    fi
fi

ACTIVE_LINKS=("${COMMON_LINKS[@]}")
if [[ "$PROFILE" == "termux" ]]; then
    ACTIVE_LINKS+=("${TERMUX_LINKS[@]}")
elif [[ "$PROFILE" == "desktop" ]]; then
    ACTIVE_LINKS+=("${DESKTOP_LINKS[@]}")
fi

print_banner() {
    echo -e "${BOLD}================================================================================${NC}"
    echo -e "  ${BOLD}Hazem's Dotfiles Link Manager${NC}"
    echo -e "${BOLD}================================================================================${NC}"
    echo -e "==> Detected OS       : $(is_termux && echo 'termux' || echo 'linux')"
    echo -e "==> Active Profile    : $PROFILE"
    echo -e "==> Target Home       : $(format_path "$HOME")"
    echo -e "==> Dotfiles Root     : $(format_path "$DOTS")"
}

init_submodules() {
    if [[ ! -f "$DOTS/tmux/.tmux.conf" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[dry-run] Would initialize git submodules (tmux)..."
            return 0
        fi
        log_info "Initializing git submodules (tmux)..."
        git -C "$DOTS" submodule update --init --recursive
    fi
}

check_links() {
    local broken=0
    local healthy=0
    local total=0

    echo ""
    log_info "Evaluating managed symlinks in $(format_path "$HOME")..."

    for entry in "${ACTIVE_LINKS[@]}"; do
        ((total++)) || true
        IFS='|' read -r kind rel_src target <<< "$entry"
        local src="$DOTS/$rel_src"
        local formatted_target="$(format_path "$target")"

        if [[ -L "$target" ]]; then
            local dest
            dest="$(readlink "$target")"
            if [[ "$dest" == "$src" ]]; then
                if [[ -e "$target" ]]; then
                    ((healthy++)) || true
                    if [[ "$VERBOSE" == true ]]; then
                        echo -e "  ${GREEN}[✓]${NC} $rel_src -> $formatted_target"
                    fi
                else
                    ((broken++)) || true
                    echo -e "  ${RED}[!] BROKEN:${NC} $formatted_target -> $dest (source file missing in repository)"
                fi
            else
                ((broken++)) || true
                echo -e "  ${YELLOW}[~] DIVERGED:${NC} $formatted_target points to $dest (expected: $src)"
            fi
        elif [[ -e "$target" ]]; then
            ((broken++)) || true
            echo -e "  ${YELLOW}[!] CONFLICT:${NC} $formatted_target exists but is not a symlink (real file/directory)"
        else
            ((broken++)) || true
            echo -e "  ${RED}[!] MISSING:${NC} $formatted_target"
        fi
    done

    echo ""
    echo -e "${BOLD}--- Link Check Summary ---------------------------------------------------------${NC}"
    echo -e "  Total evaluated   : $total"
    echo -e "  Healthy / In place: $healthy"
    echo -e "  Broken / Missing  : $broken"
    echo -e "${BOLD}--------------------------------------------------------------------------------${NC}"

    if [[ $broken -eq 0 ]]; then
        echo ""
        log_success "All managed dotfiles symlinks are healthy and in place!"
        return 0
    else
        echo ""
        log_warn "$broken link(s) need attention. Run '$(basename "$0")' to re-create them."
        return 1
    fi
}

deploy_links() {
    local created=0
    local updated=0
    local in_place=0
    local backed_up=0
    local total=0

    init_submodules

    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        log_info "Simulating dotfiles symlink deployment to $(format_path "$HOME")..."
    else
        log_info "Deploying dotfiles symlinks to $(format_path "$HOME")..."
    fi

    for entry in "${ACTIVE_LINKS[@]}"; do
        ((total++)) || true
        IFS='|' read -r kind rel_src target <<< "$entry"
        local src="$DOTS/$rel_src"
        local formatted_target="$(format_path "$target")"

        # 1. Target is an existing symlink
        if [[ -L "$target" ]]; then
            local dest
            dest="$(readlink "$target")"
            if [[ "$dest" == "$src" && -e "$target" ]]; then
                ((in_place++)) || true
                if [[ "$VERBOSE" == true ]]; then
                    echo -e "  ${GREEN}[✓]${NC} $rel_src -> $formatted_target (in place)"
                fi
                continue
            else
                if [[ "$DRY_RUN" == true ]]; then
                    echo -e "  ${CYAN}[~]${NC} would update: $rel_src -> $formatted_target (current: $(format_path "$dest"))"
                    ((updated++)) || true
                    continue
                fi
                ln -sfn "$src" "$target"
                echo -e "  ${CYAN}[~]${NC} updated: $rel_src -> $formatted_target"
                ((updated++)) || true
                continue
            fi
        fi

        # 2. Target does not exist at all
        if [[ ! -e "$target" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${GREEN}[+]${NC} would link: $rel_src -> $formatted_target"
                ((created++)) || true
                continue
            fi
            mkdir -p "$(dirname "$target")"
            ln -sfn "$src" "$target"
            echo -e "  ${GREEN}[+]${NC} linked: $rel_src -> $formatted_target"
            ((created++)) || true
            continue
        fi

        # 3. Target exists as a real file or directory (conflict -> backup first)
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${YELLOW}[!]${NC} would backup: $formatted_target -> $(format_path "$BACKUP_DIR")/"
            echo -e "  ${GREEN}[+]${NC} would link: $rel_src -> $formatted_target"
            ((backed_up++)) || true
            ((created++)) || true
            continue
        fi

        mkdir -p "$BACKUP_DIR"
        cp -a "$target" "$BACKUP_DIR/"
        echo -e "  ${YELLOW}[!]${NC} backed up: $formatted_target -> $(format_path "$BACKUP_DIR")/"
        ((backed_up++)) || true

        if [[ "$kind" == "dir" ]]; then
            rm -rf "$target"
        fi
        mkdir -p "$(dirname "$target")"
        ln -sfn "$src" "$target"
        echo -e "  ${GREEN}[+]${NC} linked: $rel_src -> $formatted_target"
        ((created++)) || true
    done

    echo ""
    echo -e "${BOLD}--- Link Summary ---------------------------------------------------------------${NC}"
    echo -e "  Total evaluated   : $total"
    echo -e "  Already in place  : $in_place"
    echo -e "  Newly linked      : $created"
    echo -e "  Updated           : $updated"
    echo -e "  Backed up         : $backed_up"
    echo -e "${BOLD}--------------------------------------------------------------------------------${NC}"

    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        log_info "[dry-run] Dry-run enabled. No filesystem changes were made."
        return 0
    fi

    if [[ -d "$BACKUP_DIR" ]]; then
        echo ""
        log_warn "Existing files backed up to: $(format_path "$BACKUP_DIR")"
    fi

    echo ""
    if [[ $created -eq 0 && $updated -eq 0 ]]; then
        log_success "All managed dotfiles symlinks are already up to date!"
    else
        log_success "Dotfiles symlinks successfully updated!"
    fi
}

# =============================================================================
#  Main Execution
# =============================================================================
print_banner

if [[ "$CHECK_MODE" == true ]]; then
    check_links
    exit $?
fi

deploy_links
