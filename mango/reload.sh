#!/usr/bin/env bash
# ~/.config/mango/reload.sh
# Runs on every config reload (exec= in config.conf)

set -euo pipefail

# Restart mangobar to pick up any theme changes
pkill -x mangobar 2>/dev/null || true
sleep 0.2
mangobar &

# Reload mako (notifications)
pkill -x mako 2>/dev/null || true
sleep 0.1
mako &

# Update GTK theme if changed (optional)
# gsettings set org.gnome.desktop.interface gtk-theme "Gruvbox-Dark-Hard"
# gsettings set org.gnome.desktop.interface icon-theme "Oranchelo"

echo "MangoWC config reloaded at $(date)"