#!/usr/bin/env bash
set -euo pipefail

DOTS="$(cd "$(dirname "$0")" && pwd)"

echo "Installing dotfiles to $HOME ..."

mkdir -p "$HOME/.config/fish"
mkdir -p "$HOME/.config/nvim"
mkdir -p "$HOME/.config/niri"
mkdir -p "$HOME/.config/noctalia"
mkdir -p "$HOME/.config/doom"

ln -sf "$DOTS/bash/.bashrc"         "$HOME/.bashrc"
ln -sf "$DOTS/fish/config.fish"     "$HOME/.config/fish/config.fish"
ln -sf "$DOTS/nvim"                 "$HOME/.config/nvim"
ln -sf "$DOTS/niri"                 "$HOME/.config/niri"
ln -sf "$DOTS/noctalia"             "$HOME/.config/noctalia"
ln -sf "$DOTS/doom"                 "$HOME/.config/doom"

ln -sf "$DOTS/tmux/.tmux.conf"      "$HOME/.tmux.conf"
ln -sf "$DOTS/tmux.conf.local"      "$HOME/.tmux.conf.local"

echo "Done!"
