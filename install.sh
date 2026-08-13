#!/usr/bin/env bash
set -euo pipefail

DOTS="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/backups/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

echo "Installing dotfiles to $HOME ..."

mkdir -p "$HOME/.config/fish"
mkdir -p "$HOME/.config/ghostty"
mkdir -p "$HOME/.config/alacritty"
mkdir -p "$HOME/.config/zed"

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

link_file "$DOTS/bash/.bashrc"         "$HOME/.bashrc"
link_file "$DOTS/fish/config.fish"     "$HOME/.config/fish/config.fish"
link_dir  "$DOTS/nvim"                 "$HOME/.config/nvim"
link_dir  "$DOTS/niri"                 "$HOME/.config/niri"
link_dir  "$DOTS/noctalia"             "$HOME/.config/noctalia"
link_dir  "$DOTS/doom"                 "$HOME/.config/doom"
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
