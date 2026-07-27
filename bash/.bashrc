# =============================================================================
#  BASH CONFIGURATION
# =============================================================================

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# --- 1. ENVIRONMENT VARIABLES ---
export HISTCONTROL=ignoredups:erasedups
export HISTSIZE=10000
export HISTFILESIZE=50000
export EDITOR="nvim"
export SUDO_EDITOR="nvim"
export VISUAL="nvim"
export MANPAGER="nvim +Man!"
export CHROME_EXECUTABLE="chromium"

# Colored man pages
export LESS_TERMCAP_mb=$(printf "\e[01;31m")
export LESS_TERMCAP_md=$(printf "\e[01;31m")
export LESS_TERMCAP_me=$(printf "\e[0m")
export LESS_TERMCAP_se=$(printf "\e[0m")
export LESS_TERMCAP_so=$(printf "\e[01;44;33m")
export LESS_TERMCAP_ue=$(printf "\e[0m")
export LESS_TERMCAP_us=$(printf "\e[01;32m")

# Development-specific environment variables
export BUN_INSTALL="$HOME/.bun"
export PNPM_HOME="$HOME/.local/share/pnpm"
export FLUTTER_ROOT="$HOME/develop/flutter"
export ANDROID_HOME="$HOME/develop/android-sdk"
if [ -z "${JAVA_HOME-}" ]; then
    _java_path="$(command -v java 2>/dev/null)"
    if [ -n "$_java_path" ]; then
        export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$_java_path")")")"
    fi
    unset _java_path
fi

# --- 2. SHELL OPTIONS & BEHAVIOR ---
set -o vi # Enable vi mode keybindings

shopt -s autocd         # Change to a directory just by typing its name
shopt -s cdspell        # Autocorrect typos in cd commands
shopt -s cmdhist        # Save multi-line commands as a single history entry
shopt -s dotglob        # Include dotfiles in globbing results
shopt -s histappend     # Append to history, don't overwrite
shopt -s expand_aliases # Expand aliases
shopt -s checkwinsize   # Check window size after each command

bind "set completion-ignore-case on"
complete -c doas

# --- 3. PATH MANAGEMENT ---
add_to_path() {
    if [ -d "$1" ] && [[ ":$PATH:" != *":$1:"* ]]; then
        export PATH="$1:$PATH"
    fi
}

# Prepend all custom bin directories to PATH
add_to_path "$HOME/.local/bin"
add_to_path "$HOME/go/bin"
add_to_path "$FLUTTER_ROOT/bin"
add_to_path "$HOME/.config/emacs/bin"
add_to_path "$HOME/.local/share/gem/ruby/3.3.0/bin"
add_to_path "$HOME/.pub-cache/bin"
add_to_path "$HOME/.local/share/JetBrains/Toolbox/scripts"
add_to_path "$HOME/.cargo/bin"
add_to_path "$BUN_INSTALL/bin"
add_to_path "$HOME/.local/share/fnm"
add_to_path "$PNPM_HOME"
add_to_path "$HOME/.shorebird/bin"
add_to_path "$HOME/.atuin/bin"
add_to_path "$JAVA_HOME/bin"
add_to_path "$ANDROID_HOME/cmdline-tools/latest/bin"
add_to_path "$ANDROID_HOME/platform-tools"
add_to_path "$ANDROID_HOME/emulator"
add_to_path "/var/lib/flatpak/exports/bin"
add_to_path "$HOME/.local/share/flatpak/exports/bin"

# --- 4. ALIASES ---

## General & System
alias c='clear'
alias xc='exit'
alias srb='source ~/.bashrc'
alias srf='source ~/.config/fish/config.fish'
alias reboot='doas reboot'
alias poweroff='doas poweroff'
alias ip='ip -c'
alias chmox='chmod +x'
alias ep='echo "$PATH" | tr : "\n"'
alias pbcopy='xsel --clipboard --input'
alias pbpaste='xsel --clipboard --output'
alias toarab='(wl-paste 2>/dev/null || xclip -o -selection clipboard) | trans -b :ar'
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
alias da='date "+%Y-%m-%d %A %T %Z"'
alias dtz='date +%Y%m%d_%H%M%S'
alias openports='netstat -nape --inet'
alias diskspace="du -S | sort -n -r | more"
alias folders='du -h --max-depth=1'
alias tree='tree -CAhF --dirsfirst'
alias llp='DOCKER_HOST=unix:///run/user/1000/podman/podman.sock'
alias k='kubectl'

## Safe Operations / Trash CLI
if command -v trash-put &> /dev/null; then
    alias rm='trash-put -v'
else
    alias rm='rm -i'
fi
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -p'

## Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

## File & Directory Listing
if command -v lsd &> /dev/null; then
    alias ls='lsd -A --group-directories-first'
    alias ll='lsd -Alh --group-directories-first'
    alias l1='lsd -1F --icon never'
    alias lt='lsd --tree'
    alias ltr='lsd -ltrh --group-directories-first'
    alias l.='lsd -a | grep "^\."'
    alias lx='lsd -lXBh --group-directories-first'
    alias lk='lsd -lSrh --group-directories-first'
    alias lc='lsd -lcrh --group-directories-first'
    alias lu='lsd -lurh --group-directories-first'
    alias lr='lsd -lRh --group-directories-first'
    alias la1='lsd -A1'
else
    alias ls='ls -A --group-directories-first --color=auto'
    alias ll='ls -Alh --group-directories-first --color=auto'
    alias l1='ls -1 --color=auto'
    alias lt='tree -CAhF --dirsfirst 2>/dev/null || ls -ltrh --color=auto'
    alias ltr='ls -ltrh --group-directories-first --color=auto'
    alias l.='ls -a | egrep "^\." --color=auto'
    alias lx='ls -lXBh --group-directories-first --color=auto'
    alias lk='ls -lSrh --group-directories-first --color=auto'
    alias lc='ls -lcrh --group-directories-first --color=auto'
    alias lu='ls -lurh --group-directories-first --color=auto'
    alias lr='ls -lRh --group-directories-first --color=auto'
    alias la1='ls -A1 --color=auto'
fi

## Grep & Process
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias psa='ps auxf'
alias psmem='ps auxf | sort -nr -k 4'
alias pscpu='ps auxf | sort -nr -k 3'
alias h='history | grep'
alias p='ps aux | grep'
alias df='df -h'
alias free='free -m'

## DYNAMIC PACKAGE MANAGER ALIASES
if command -v xbps-install &> /dev/null; then
    # --- Void Linux ---
    alias i="doas xbps-install -S"
    alias u="i; doas xbps-install xbps; doas xbps-install -uv"
    alias uy="i; doas xbps-install xbps; doas xbps-install -uvy"
    alias r="doas xbps-remove -Rfv"
    alias R="doas xbps-remove -Oofv"
    alias q="doas xbps-query -Rs"
    alias Q="doas xbps-query -R"
    alias qls="xbps-query --list-manual-pkgs | awk '{sub(/-[^-]+_[0-9]+$/, \"\"); print}'"
elif command -v pacman &> /dev/null; then
    # --- Arch Linux ---
    alias i="doas pacman -S --needed"
    alias u="doas pacman -Syu"
    alias r="doas pacman -Rns"
    alias q="doas pacman -Ss"
    alias Q="doas pacman -Qs"
    alias pu="doas paru"
fi

## Editing Configs
alias n='nvim'
alias nb='n ~/.bashrc'
alias nf='n ~/.config/fish/config.fish'
alias nx='n ~/.xinitrc'
alias nt='n ~/.tmux.conf.local'
alias nalc='n ~/.config/alacritty/alacritty.toml'
alias nk='n ~/.config/kitty/kitty.conf'
alias ni3='n ~/.config/i3/config'
alias nq='n ~/.config/qtile/config.py'
alias ng='n ~/.config/ghostty/config'
alias nn='n ~/.config/niri/config.kdl'
alias nw='n ~/.config/waybar/config.jsonc'
alias nh='n ~/.config/hypr/hyprland.conf'

# Default 'emacs' command opens IN the terminal (-nw)
# If the server isn't running, -a '' automatically starts the daemon!
alias emacs="emacsclient -nw -a ''"

# Alias 'em' as a short command for quick edits
alias em="emacsclient -nw -a ''"

# Optional: 'gemacs' for the rare times you WANT a GUI window
alias gemacs="emacsclient -c -a '' &"

# Restart the Emacs daemon
alias rem="killall emacs; command emacs --daemon"

# Neovim Profiles
alias nlazy='NVIM_APPNAME=lazyvim nvim'
alias nchad='NVIM_APPNAME=nvchad nvim'
alias nkick='NVIM_APPNAME=kickstart nvim'
alias nyousef='NVIM_APPNAME=yousefnvim nvim'
alias tonynvim='NVIM_APPNAME=tonynvim nvim'

## Git
alias lg='lazygit'
alias gcom='git add . && git commit -m'
alias lazyg='git add . && git commit -m "$1" && git push'
alias push='git remote | xargs -I R git push R main'
alias pushall='git remote | xargs -I R git push R --all'

## Media & Downloads (yt-dlp)
alias ytv='yt-dlp --format "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" -S res:1080 --embed-chapters -o "%(title)s.%(ext)s"'
alias ytv7='yt-dlp -S res:720 --embed-chapters -o "%(title)s.%(ext)s"'
alias ytv4='yt-dlp -S res:480 --embed-chapters -o "%(title)s.%(ext)s"'
alias ytp='yt-dlp --format "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" -S res:1080 --embed-chapters -o "%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s"'
alias ytp7='yt-dlp --format "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" -S res:720 --embed-chapters -o "%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s"'
alias ytp4='yt-dlp --format "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" -S res:480 --embed-chapters -o "%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s"'
alias ytp3='yt-dlp --format "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" -S res:360 --embed-chapters -o "%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s"'
alias ytf='yt-dlp -o "%(title)s.%(ext)s"'
alias curld='curl --fail --show-error --remote-name --location --continue-at - '
alias ytap='yt-dlp --skip-download --extract-audio --audio-quality 0 -o "%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s"'
alias ytnail='yt-dlp -o "%(title)s.%(ext)s" --skip-download --write-thumbnail'

## TMUX
alias tl='tmux ls'
alias tn='tmux new-session'
alias ta='tmux attach -t'
alias tks='tmux kill-session -t'
alias tns='tmux new -s'
alias srt='tmux source ~/.tmux.conf'
alias netsp='bwm-ng -I wlp2s0'
alias nethogs='doas nethogs'

## Virsh (Left-Handed V-Set)
alias vv='virsh list --all'
alias vs='virsh start'
alias vq='virsh shutdown'
alias vc='virsh console'
alias vd='virsh destroy'
alias vr='virsh reboot'
alias ve='virsh edit'

## TV Casting
alias tv_cast="catt -d 192.168.1.167 cast"
alias tv_stop="catt -d 192.168.1.167 stop"
alias tv_pause="catt -d 192.168.1.167 pause"

# --- 5. FUNCTIONS ---

# Universal file extractor
ex() {
    if [ ! -f "$1" ]; then echo "'$1' is not a valid file"; return 1; fi
    case "$1" in
      *.tar.bz2) tar xjf "$1" ;; *.tar.gz)  tar xzf "$1" ;; *.tar.xz)  tar xf "$1" ;;
      *.tar.zst) unzstd "$1"  ;; *.bz2)     bunzip2 "$1" ;; *.rar)     unrar x "$1" ;;
      *.gz)      gunzip "$1"  ;; *.tar)     tar xf "$1"  ;; *.tbz2)    tar xjf "$1" ;;
      *.tgz)     tar xzf "$1" ;; *.zip)     unzip "$1"   ;; *.Z)       uncompress "$1" ;;
      *.7z)      7z x "$1"    ;; *.deb)     ar x "$1"    ;;
      *) echo "'$1' cannot be extracted via ex()"; return 1 ;;
    esac
}

# Recursively go up directories
up() {
    local limit="${1:-1}"
    local d=""
    for ((i=1; i <= limit; i++)); do
        d="../$d"
    done
    cd "$d"
}

# Grep helper
ftext() {
    grep -iIHrn --color=always "$1" . | less -r
}

# What is my IP
whatismyip() {
    echo "Internal: $(ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n1)"
    echo "External: $(curl -s ifconfig.me)"
}

# Hastebin Upload
hb() {
    if [ -z "$1" ] || [ ! -f "$1" ]; then echo "Usage: hb <file>"; return 1; fi
    local uri="http://bin.christitus.com/documents"
    local response=$(curl -s -X POST -d @"$1" "$uri")
    local key=$(echo "$response" | jq -r '.key')
    if [ "$key" != "null" ]; then
        echo "http://bin.christitus.com/$key"
    else
        echo "Upload failed."
    fi
}

# Yazi integration
y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    IFS= read -r -d '' cwd < "$tmp"
    [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
    rm -f -- "$tmp"
}

# Distribution detection
distribution() {
    local dtype="unknown"
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        dtype=$ID
    fi
    echo "$dtype"
}

# TV playlist casting
tv_playlist() {
    for file in "$@"; do
        echo "Casting $file to TCL TV..."
        catt -d 192.168.1.167 cast --block "$file"
    done
}

# Virsh helpers
va() {
    virsh domifaddr "$1" | awk '/ipv4/ {print $4}' | cut -d/ -f1
}

vxx() {
    echo "Destroying and Undefining: $1"
    virsh destroy "$1" 2>/dev/null
    virsh undefine "$1" --remove-all-storage
}

vm-from-iso() {
    local name="${1:?Usage: vm-from-iso <vm_name> <iso_path> [disk_size] [ram] [vcpus]}"
    local iso="${2:?Usage: vm-from-iso <vm_name> <iso_path> [disk_size] [ram] [vcpus]}"
    local disk_size="${3:-20G}"
    local ram="${4:-2048}"
    local vcpus="${5:-2}"
    local disk_path="$HOME/VM/disks/${name}.qcow2"

    mkdir -p "$(dirname "$disk_path")"

    virt-install \
        --name "$name" \
        --memory "$ram" \
        --vcpus "$vcpus" \
        --disk path="$disk_path",size="${disk_size%G}",format=qcow2 \
        --cdrom "$iso" \
        --os-variant detect=on,name=generic \
        --graphics vnc,listen=127.0.0.1 \
        --network network=default \
        --noautoconsole
}

# File Watcher Wrapper
_watch_runner() {
    local pattern="$1"
    local prompt="$2"
    shift 2
    local cmd="$@"
    local file=$(find . -type f -name "$pattern" | fzf --prompt="$prompt")
    if [ -n "$file" ]; then
        echo "Watching: $file"
        echo "$file" | entr -c sh -c "clear; $cmd '$file'"
    else
        echo "No file selected."
    fi
}

go_watch() { _watch_runner '*.go' "Select Go file > " "go run"; }
py_watch() { _watch_runner '*.py' "Select Python file > " "python"; }
dart_watch() { _watch_runner '*.dart' "Select Dart file > " "dart run"; }
js_watch() { _watch_runner '*.js' "Select JS file > " "node"; }
sh_watch() { _watch_runner '*.sh' "Select Shell script > " "bash"; }
md_watch() { _watch_runner '*.md' "Select Markdown file > " "glow"; }
cpp_watch() {
    local file=$(find . -type f -name '*.cpp' | fzf --prompt="Select C++ file > ")
    if [ -n "$file" ]; then
        echo "Watching: $file"
        local base=$(basename "$file" .cpp)
        echo "$file" | entr -c sh -c "clear; g++ '$file' -o '$base' && './$base'"
    fi
}

# --- 6. TOOL INITIALIZATIONS ---
[ -x "$(command -v starship)" ] && eval "$(starship init bash)"
[ -x "$(command -v zoxide)" ] && eval "$(zoxide init bash)"
[ -x "$(command -v fnm)" ] && eval "$(fnm env --use-on-cd)"
[ -x "$(command -v atuin)" ] && eval "$(atuin init bash --disable-up-arrow)"
[ -x "$(command -v pipx)" ] && eval "$(register-python-argcomplete pipx)"
[ -x "$(command -v jj)" ] && source <(jj util completion bash)
if command -v mise &>/dev/null; then eval "$(mise activate bash)"; fi
