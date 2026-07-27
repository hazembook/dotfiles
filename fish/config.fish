# =============================================================================
#  FISH CONFIGURATION
# =============================================================================

# --- 1. INTERACTIVE SHELL GUARD ---
if not status --is-interactive
    exit
end

set fish_greeting ""
set -g fish_color_command green

# --- 2. ENVIRONMENT VARIABLES ---
set -gx EDITOR "nvim"
set -gx SUDO_EDITOR "nvim"
set -gx VISUAL "nvim"
set -gx MANPAGER "nvim +Man!"
set -gx CHROME_EXECUTABLE "chromium"

# Colored Man Pages
set -gx LESS_TERMCAP_mb (printf "\e[01;31m")
set -gx LESS_TERMCAP_md (printf "\e[01;31m")
set -gx LESS_TERMCAP_me (printf "\e[0m")
set -gx LESS_TERMCAP_se (printf "\e[0m")
set -gx LESS_TERMCAP_so (printf "\e[01;44;33m")
set -gx LESS_TERMCAP_ue (printf "\e[0m")
set -gx LESS_TERMCAP_us (printf "\e[01;32m")

# Dev Paths
set -gx BUN_INSTALL "$HOME/.bun"
set -gx PNPM_HOME "$HOME/.local/share/pnpm"
set -gx FLUTTER_ROOT "$HOME/develop/flutter"
set -gx JAVA_HOME "/usr/lib/jvm/java-17-openjdk"
set -gx ANDROID_HOME "$HOME/develop/android-sdk"

# --- 3. PATH MANAGEMENT ---
fish_add_path "$HOME/.local/bin"
fish_add_path "$HOME/go/bin"
fish_add_path "$FLUTTER_ROOT/bin"
fish_add_path "$HOME/.config/emacs/bin"
fish_add_path "$HOME/.local/share/gem/ruby/3.3.0/bin"
fish_add_path "$HOME/.pub-cache/bin"
fish_add_path "$HOME/.local/share/JetBrains/Toolbox/scripts"
fish_add_path "$HOME/.cargo/bin"
fish_add_path "$BUN_INSTALL/bin"
fish_add_path "$HOME/.local/share/fnm"
fish_add_path "$PNPM_HOME"
fish_add_path "$HOME/.shorebird/bin"
fish_add_path "$HOME/.turso"
fish_add_path "$HOME/.atuin/bin"
fish_add_path "$JAVA_HOME/bin"
fish_add_path "/var/lib/flatpak/exports/bin"
fish_add_path "$HOME/.local/share/flatpak/exports/bin"
fish_add_path "$ANDROID_HOME/cmdline-tools/latest/bin/"
fish_add_path "$ANDROID_HOME/platform-tools/"
fish_add_path "$ANDROID_HOME/emulator/"

# --- 4. ALIASES ---

## General & System
alias c 'clear'
alias xc 'exit'
alias srf 'source ~/.config/fish/config.fish'
alias reboot 'doas reboot'
alias poweroff 'doas poweroff'
alias ip 'ip -c'
alias chmox 'chmod +x'
alias ep 'echo $PATH | tr : "\n"'
alias pbcopy 'xsel --clipboard --input'
alias pbpaste 'xsel --clipboard --output'
alias toarab 'xclip -o -selection clipboard | trans -b :ar'
alias alert 'notify-send --urgency=low -i (if test $status = 0; echo terminal; else; echo error; end) (history | head -n1)'
alias da 'date "+%Y-%m-%d %A %T %Z"'
alias openports 'netstat -nape --inet'
alias diskspace "du -S | sort -n -r | more"
alias folders 'du -h --max-depth=1'
alias tree 'tree -CAhF --dirsfirst'
alias llp 'DOCKER_HOST=unix:///run/user/1000/podman/podman.sock'
alias dtz 'date +%Y%m%d_%H%M%S'
alias k 'kubectl'

## Safe Operations / Trash CLI
if command -v trash-put &> /dev/null
    alias rm 'trash-put -v'
else
    alias rm 'rm -i'
end
alias cp 'cp -i'
alias mv 'mv -i'
alias mkdir 'mkdir -p'

## Navigation
alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'
alias ..... 'cd ../../../..'

## File & Directory Listing
if command -v lsd &> /dev/null
    alias ls 'lsd -A --group-directories-first'
    alias ll 'lsd -Alh --group-directories-first'
    alias l1 'lsd -1F --icon never'
    alias lt 'lsd --tree'
    alias ltr 'lsd -ltrh --group-directories-first'
    alias l. 'lsd -a | grep "^\."'
    alias lx 'lsd -lXBh --group-directories-first'
    alias lk 'lsd -lSrh --group-directories-first'
    alias lc 'lsd -lcrh --group-directories-first'
    alias lu 'lsd -lurh --group-directories-first'
    alias lr 'lsd -lRh --group-directories-first'
    alias la1 'lsd -A1'
else
    alias ls 'ls -aFh --color=always --group-directories-first'
    alias ll 'ls -Alh --group-directories-first --color=auto'
    alias l1 'ls -1 --color=auto'
    alias lt 'tree -CAhF --dirsfirst 2>/dev/null; or ls -ltrh --color=auto'
    alias ltr 'ls -ltrh --group-directories-first --color=auto'
    alias l. 'ls -a | egrep "^\." --color=auto'
    alias lx 'ls -lXBh --group-directories-first --color=auto'
    alias lk 'ls -lSrh --group-directories-first --color=auto'
    alias lc 'ls -lcrh --group-directories-first --color=auto'
    alias lu 'ls -lurh --group-directories-first --color=auto'
    alias lr 'ls -lRh --group-directories-first --color=auto'
    alias la1 'ls -A1 --color=auto'
end

## DYNAMIC PACKAGE MANAGER ALIASES
if command -v xbps-install &> /dev/null
    # --- Void Linux ---
    alias i "doas xbps-install -S"
    alias u "i; doas xbps-install xbps; doas xbps-install -uv"
    alias uy "i; doas xbps-install xbps; doas xbps-install -uvy"
    alias r "doas xbps-remove -Rfv"
    alias R "doas xbps-remove -Oofv"
    alias q "doas xbps-query -Rs"
    alias Q "doas xbps-query -R"
    alias qls "xbps-query --list-manual-pkgs | awk '{sub(/-[^-]+_[0-9]+\$/, ""); print}'"
else if command -v pacman &> /dev/null
    # --- Arch Linux ---
    alias i "doas pacman -S --needed"
    alias u "doas pacman -Syu"
    alias r "doas pacman -Rns"
    alias q "doas pacman -Ss"
    alias Q "doas pacman -Qs"
    alias pu "paru"
end

## Editing Configs
alias n 'nvim'
alias nb 'n ~/.bashrc'
alias nf 'n ~/.config/fish/config.fish'
alias nx 'n ~/.xinitrc'
alias nt 'n ~/.tmux.conf.local'
alias nalc 'n ~/.config/alacritty/alacritty.yml'
alias nk 'n ~/.config/kitty/kitty.conf'
alias ni3 'n ~/.config/i3/config'
alias nq 'n ~/.config/qtile/config.py'
alias ng 'n ~/.config/ghostty/config'
alias nn 'n ~/.config/niri/config.kdl'
alias nw 'n ~/.config/waybar/config.jsonc'
alias nh 'n ~/.config/hypr/hyprland.conf'

# Default 'emacs' command opens IN the terminal (-nw)
# If the server isn't running, -a '' automatically starts the daemon!
alias emacs "emacsclient -nw -a ''"

# Alias 'em' as a short command for quick edits
alias em "emacsclient -nw -a ''"

# Optional: 'gemacs' for the rare times you WANT a GUI window
alias gemacs "emacsclient -c -a '' &"

# Restart the Emacs daemon
alias rem "killall emacs; command emacs --daemon"

# Neovim Profiles
alias nlazy 'NVIM_APPNAME=lazyvim nvim'
alias nchad 'NVIM_APPNAME=nvchad nvim'
alias nkick 'NVIM_APPNAME=kickstart nvim'
alias nyousef 'NVIM_APPNAME=yousefnvim nvim'
alias tonynvim 'NVIM_APPNAME=tonynvim nvim'

## Git
alias lg 'lazygit'
alias gcom 'git add . && git commit -m'
alias lazyg 'git add . && git commit -m "$argv" && git push'
alias push 'git remote | xargs -I R git push R main'
alias pushall 'git remote | xargs -I R git push R --all'

## Process Management
alias psa 'ps auxf'
alias psmem 'ps auxf | sort -nr -k 4'
alias pscpu 'ps auxf | sort -nr -k 3'
alias h "history | grep"
alias p "ps aux | grep"
alias df 'df -h'
alias free 'free -m'
alias grep 'grep --color=auto'
alias egrep 'egrep --color=auto'
alias fgrep 'fgrep --color=auto'

## TMUX
alias tl 'tmux ls'
alias tn 'tmux new-session'
alias ta 'tmux attach -t'
alias tks 'tmux kill-session -t'
alias tns 'tmux new -s'
alias srt 'tmux source ~/.tmux.conf'
alias netsp 'bwm-ng -I wlp2s0'
alias nethogs 'doas nethogs'

## yt-dlp
alias ytv='yt-dlp --format "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" -S res:1080 --embed-chapters -o "%(title)s.%(ext)s"'
alias ytv7='yt-dlp -S res:720 --embed-chapters -o "%(title)s.%(ext)s"'
alias ytv4='yt-dlp -S res:480 --embed-chapters -o "%(title)s.%(ext)s"'
alias ytp='yt-dlp --format "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" -S res:1080 --embed-chapters -o "%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s"'
alias ytp7='yt-dlp --format "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" -S res:720 --embed-chapters -o "%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s"'
alias ytp4='yt-dlp --format "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" -S res:480 --embed-chapters -o "%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s"'
alias ytp3='yt-dlp --format "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" -S res:360 --embed-chapters -o "%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s"'
alias ytf='yt-dlp -o "%(title)s.%(ext)s"'
alias curld='curl --fail --remote-name --location --continue-at -'
alias ytap='yt-dlp --skip-download --extract-audio --audio-quality 0 -o "%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s"'
alias ytnail='yt-dlp -o "%(title)s.%(ext)s" --skip-download --write-thumbnail'

# TCL TV Casting
alias tv_cast="catt -d 192.168.1.167 cast"
alias tv_stop="catt -d 192.168.1.167 stop"
alias tv_pause="catt -d 192.168.1.167 pause"
function tv_playlist
    for file in $argv
        echo "Casting $file to TCL TV..."
        catt -d 192.168.1.167 cast --block $file
    end
end

## Virsh (Left-Handed V-Set)
alias vv 'virsh list --all'
alias vs 'virsh start'
alias vq 'virsh shutdown'
alias vc 'virsh console'
alias vd 'virsh destroy'
alias vr 'virsh reboot'
alias ve 'virsh edit'
function va; virsh domifaddr $argv[1] | awk '/ipv4/ {print $4}' | cut -d/ -f1; end
function vxx
    echo "💣 Destroying and Undefining: $argv[1]"
    virsh destroy $argv[1] 2>/dev/null
    virsh undefine $argv[1] --remove-all-storage
end
function vm-from-iso -d "Create a VM from an ISO file"
    if test (count $argv) -lt 2
        echo "Usage: vm-from-iso <vm_name> <iso_path> [disk_size] [ram] [vcpus]"
        return 1
    end
    set name $argv[1]
    set iso $argv[2]
    set disk_size $argv[3]; or set disk_size "20G"
    set ram $argv[4]; or set ram 2048
    set vcpus $argv[5]; or set vcpus 2
    set disk_path "$HOME/VM/disks/$name.qcow2"

    mkdir -p (dirname "$disk_path")

    virt-install \
        --name "$name" \
        --memory "$ram" \
        --vcpus "$vcpus" \
        --disk path="$disk_path",size=(string replace -r 'G$' '' -- "$disk_size"),format=qcow2 \
        --cdrom "$iso" \
        --os-variant detect=on,name=generic \
        --graphics vnc,listen=127.0.0.1 \
        --network network=default \
        --noautoconsole
end

# --- 5. FUNCTIONS ---

function ex
    if not test -f "$argv[1]"
        echo "'$argv[1]' is not a valid file"
        return 1
    end
    switch "$argv[1]"
        case '*.tar.bz2'; tar xjf "$argv[1]"
        case '*.tar.gz';  tar xzf "$argv[1]"
        case '*.tar.xz';  tar xf "$argv[1]"
        case '*.tar.zst'; unzstd "$argv[1]"
        case '*.bz2';     bunzip2 "$argv[1]"
        case '*.rar';     unrar x "$argv[1]"
        case '*.gz';      gunzip "$argv[1]"
        case '*.tar';     tar xf "$argv[1]"
        case '*.tbz2';    tar xjf "$argv[1]"
        case '*.tgz';     tar xzf "$argv[1]"
        case '*.zip';     unzip "$argv[1]"
        case '*.Z';       uncompress "$argv[1]"
        case '*.7z';      7z x "$argv[1]"
        case '*.deb';     ar x "$argv[1]"
        case '*';         echo "'$argv[1]' cannot be extracted via ex()"; return 1
    end
end

function ftext
	grep -iIHrn --color=always "$argv[1]" . | less -r
end

function up
    set limit $argv[1]
    if test -z "$limit"; set limit 1; end
    set d ""
    for i in (seq $limit)
        set d "$d../"
    end
    cd $d
end

function y
	set tmp (mktemp -t "yazi-cwd.XXXXXX")
	yazi $argv --cwd-file="$tmp"
	if read -z cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
		builtin cd -- "$cwd"
	end
	rm -f -- "$tmp"
end

function distribution
    set dtype "unknown"
    if test -r /etc/os-release
        source /etc/os-release
        set dtype $ID
    end
    echo $dtype
end

function whatismyip
    set internal_ip (ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
    set external_ip (curl -s ifconfig.me)
    echo "Internal IP: $internal_ip"
    echo "External IP: $external_ip"
end

function hb
    if test -z "$argv[1]"; echo "No file specified"; return 1; end
    set uri "http://bin.christitus.com/documents"
    set response (curl -s -X POST -d @(cat "$argv[1]") "$uri")
    if test $status -eq 0
        set hasteKey (echo "$response" | jq -r '.key')
        echo "http://bin.christitus.com/$hasteKey"
    else
        echo "Failed to upload."
    end
end

# File Watcher Helper
function _watch_runner
    set file_pattern $argv[1]
    set prompt_text $argv[2]
    set run_command $argv[3..-1]
    set file (find . -type f -name "$file_pattern" | fzf --prompt="$prompt_text")
    if test -n "$file"
        echo "Watching: $file"
        echo "$file" | entr -c sh -c "clear; $run_command '$file'"
    else
        echo "No file selected."
    end
end

function go_watch;   _watch_runner '*.go'   "Select Go file > " "go run"; end
function py_watch;   _watch_runner '*.py'   "Select Python file > " "python"; end
function dart_watch; _watch_runner '*.dart' "Select Dart file > " "dart run"; end
function js_watch;   _watch_runner '*.js'   "Select JS file > " "node"; end
function sh_watch;   _watch_runner '*.sh'   "Select Shell script > " "bash"; end
function md_watch;   _watch_runner '*.md'   "Select Markdown file > " "glow"; end
function cpp_watch
    set file (find . -type f -name '*.cpp' | fzf --prompt="Select C++ file > ")
    if test -n "$file"
        echo "Watching: $file"
        set cmd "g++ '$file' -o (basename '$file' .cpp) && ./(basename '$file' .cpp)"
        echo "$file" | entr -c sh -c "clear; $cmd"
    end
end

# --- 6. KEY BINDINGS ---
fish_vi_key_bindings

# --- 7. TOOL INITIALIZATIONS ---
if command -v starship &> /dev/null; starship init fish | source; end
if command -v zoxide &> /dev/null; zoxide init fish | source; end
if command -v fnm &> /dev/null; fnm env --use-on-cd | source; end
if command -v atuin &> /dev/null; atuin init fish --disable-up-arrow | source; end
if command -v pipx &> /dev/null; register-python-argcomplete --shell fish pipx | source; end
if command -v jj &> /dev/null; jj util completion fish | source; end
if command -v mise &> /dev/null; mise activate fish | source; end
