#!/usr/bin/env bash
set -euo pipefail

DOTS="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/backups/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# Backup real files/dirs before replacing them with symlinks
backup_item() {
    local target="$1"
    if [[ -e "$target" && ! -L "$target" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$target" "$BACKUP_DIR/"
        echo "  Backed up: $target"
    fi
}

# Directory symlink: backup, remove real dir, then link
link_dir() {
    local src="$1" target="$2"
    backup_item "$target"
    rm -rf "$target"
    ln -sf "$src" "$target"
}

# File symlink: backup real file, then force-link
link_file() {
    local src="$1" target="$2"
    backup_item "$target"
    ln -sf "$src" "$target"
}

# Every path this script manages, so --check can verify them.
MANAGED_TARGETS=(
    "$HOME/.bashrc"
    "$HOME/.config/fish/config.fish"
    "$HOME/.config/nvim"
    "$HOME/.config/niri"
    "$HOME/.config/noctalia"
    "$HOME/.config/doom"
    "$HOME/.config/mango"
    "$HOME/.config/mangobar"
    "$HOME/.config/ghostty/config"
    "$HOME/.config/alacritty/alacritty.toml"
    "$HOME/.config/alacritty/themes"
    "$HOME/.config/fastfetch"
    "$HOME/.config/rofi"
    "$HOME/.config/zed/settings.json"
    "$HOME/.config/zed/keymap.json"
    "$HOME/.tmux.conf"
    "$HOME/.tmux.conf.local"
    "$HOME/.gitconfig"
)

# Report managed paths that are gone, and symlinks whose target moved.
check_links() {
    local bad=0
    for target in "${MANAGED_TARGETS[@]}"; do
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

echo "Installing dotfiles to $HOME ..."

mkdir -p "$HOME/.config/fish"
mkdir -p "$HOME/.config/ghostty"
mkdir -p "$HOME/.config/alacritty"
mkdir -p "$HOME/.config/zed"
mkdir -p "$HOME/.config/mango/scripts"
mkdir -p "$HOME/.config/mangobar"

link_file "$DOTS/bash/.bashrc"         "$HOME/.bashrc"
link_file "$DOTS/fish/config.fish"     "$HOME/.config/fish/config.fish"
link_dir  "$DOTS/nvim"                 "$HOME/.config/nvim"
link_dir  "$DOTS/niri"                 "$HOME/.config/niri"
link_dir  "$DOTS/noctalia"             "$HOME/.config/noctalia"
link_dir  "$DOTS/doom"                 "$HOME/.config/doom"
link_dir  "$DOTS/mango"                "$HOME/.config/mango"
link_dir  "$DOTS/mangobar"             "$HOME/.config/mangobar"
link_file "$DOTS/ghostty/config"       "$HOME/.config/ghostty/config"
link_file "$DOTS/alacritty/alacritty.toml"  "$HOME/.config/alacritty/alacritty.toml"
link_dir  "$DOTS/alacritty/themes"     "$HOME/.config/alacritty/themes"
link_dir  "$DOTS/fastfetch"            "$HOME/.config/fastfetch"
link_dir  "$DOTS/rofi"                 "$HOME/.config/rofi"
link_file "$DOTS/zed/settings.json"    "$HOME/.config/zed/settings.json"
link_file "$DOTS/zed/keymap.json"      "$HOME/.config/zed/keymap.json"

link_file "$DOTS/tmux/.tmux.conf"      "$HOME/.tmux.conf"
link_file "$DOTS/tmux.conf.local"      "$HOME/.tmux.conf.local"
link_file "$DOTS/git/.gitconfig"       "$HOME/.gitconfig"

echo "Done!"
if [[ -d "$BACKUP_DIR" ]]; then
    echo "Old configs backed up to: $BACKUP_DIR"
fi
