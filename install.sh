#!/usr/bin/env bash
set -euo pipefail

DOTS="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/backups/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

is_termux() {
    [[ -n "${TERMUX_VERSION:-}" || -d "/data/data/com.termux/files/usr" ]]
}

# Format: "type|src_relative_to_DOTS|target_absolute"
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
    "dir|mango|$HOME/.config/mango"
    "dir|mangobar|$HOME/.config/mangobar"
    "file|ghostty/config|$HOME/.config/ghostty/config"
    "file|alacritty/alacritty.toml|$HOME/.config/alacritty/alacritty.toml"
    "dir|alacritty/themes|$HOME/.config/alacritty/themes"
    "dir|rofi|$HOME/.config/rofi"
    "file|zed/settings.json|$HOME/.config/zed/settings.json"
    "file|zed/keymap.json|$HOME/.config/zed/keymap.json"
)

ACTIVE_LINKS=("${COMMON_LINKS[@]}")
if ! is_termux; then
    ACTIVE_LINKS+=("${DESKTOP_LINKS[@]}")
fi

backup_item() {
    local target="$1"
    if [[ -e "$target" && ! -L "$target" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$target" "$BACKUP_DIR/"
        echo "  Backed up: $target"
    fi
}

link_entry() {
    local kind="$1" src="$DOTS/$2" target="$3"
    mkdir -p "$(dirname "$target")"
    backup_item "$target"
    if [[ "$kind" == "dir" ]]; then
        rm -rf "$target"
    fi
    ln -sfn "$src" "$target"
}

check_links() {
    local bad=0 entry kind src target
    for entry in "${ACTIVE_LINKS[@]}"; do
        IFS='|' read -r kind src target <<< "$entry"
        if [[ -L "$target" ]]; then
            if [[ ! -e "$target" ]]; then
                echo "  BROKEN: $target -> $(readlink "$target")"
                bad=1
            fi
        elif [[ ! -e "$target" ]]; then
            echo "  MISSING: $target"
            bad=1
        fi
    done
    if [[ $bad -eq 0 ]]; then
        echo "All managed paths are in place."
    else
        echo "Run this script without --check to re-create them."
    fi
    return $bad
}

if [[ "${1:-}" == "--check" ]]; then
    echo "Checking dotfiles links in $HOME ..."
    check_links
    exit $?
fi

echo "Installing dotfiles to $HOME ($(is_termux && echo 'Termux' || echo 'Linux')) ..."

for entry in "${ACTIVE_LINKS[@]}"; do
    IFS='|' read -r kind src target <<< "$entry"
    link_entry "$kind" "$src" "$target"
done

echo "Done!"
if [[ -d "$BACKUP_DIR" ]]; then
    echo "Old configs backed up to: $BACKUP_DIR"
fi
