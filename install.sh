#!/usr/bin/env bash
set -euo pipefail

DOTS="$(cd "$(dirname "$0")" && pwd)"

echo "Installing dotfiles to $HOME ..."

mkdir -p "$HOME/.config/fish"
mkdir -p "$HOME/.config/nvim"
mkdir -p "$HOME/.config/niri"
mkdir -p "$HOME/.config/noctalia"
mkdir -p "$HOME/.config/doom"
mkdir -p "$HOME/.config/ghostty"
mkdir -p "$HOME/.config/alacritty"
mkdir -p "$HOME/.config/fastfetch"
mkdir -p "$HOME/.config/rofi"

ln -sf "$DOTS/bash/.bashrc"         "$HOME/.bashrc"
ln -sf "$DOTS/fish/config.fish"     "$HOME/.config/fish/config.fish"
ln -sf "$DOTS/nvim"                 "$HOME/.config/nvim"
ln -sf "$DOTS/niri"                 "$HOME/.config/niri"
ln -sf "$DOTS/noctalia"             "$HOME/.config/noctalia"
ln -sf "$DOTS/doom"                 "$HOME/.config/doom"
ln -sf "$DOTS/ghostty/config"       "$HOME/.config/ghostty/config"
ln -sf "$DOTS/alacritty/alacritty.toml"  "$HOME/.config/alacritty/alacritty.toml"
ln -sf "$DOTS/alacritty/themes"     "$HOME/.config/alacritty/themes"
ln -sf "$DOTS/fastfetch"            "$HOME/.config/fastfetch"
ln -sf "$DOTS/rofi"                 "$HOME/.config/rofi"

ln -sf "$DOTS/tmux/.tmux.conf"      "$HOME/.tmux.conf"
ln -sf "$DOTS/tmux.conf.local"      "$HOME/.tmux.conf.local"
ln -sf "$DOTS/git/.gitconfig"       "$HOME/.gitconfig"

echo "Done!"
