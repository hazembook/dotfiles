# hazem's dotfiles

Managed by [NixOS](https://github.com/hazembook/nixos-config) (via `xdg.configFile` + home-manager) on NixOS.
For non-Nix systems, run `install.sh` to symlink everything into `$HOME`:

    git clone --recursive git@codeberg.org:hazembook/dotfiles.git ~/.dots
    cd ~/.dots
    ./install.sh

### What's here

| Directory   | Target                          |
|-------------|---------------------------------|
| `bash/`     | `~/.bashrc`                     |
| `fish/`     | `~/.config/fish/config.fish`    |
| `nvim/`     | `~/.config/nvim/`               |
| `niri/`     | `~/.config/niri/`               |
| `noctalia/` | `~/.config/noctalia/`           |
| `doom/`     | `~/.config/doom/`               |
| `tmux/`     | submodule — gpakosz/.tmux       |
| `tmux.conf.local` | `~/.tmux.conf.local`      |

### Tmux

`tmux/` is a submodule of [gpakosz/.tmux](https://github.com/gpakosz/.tmux).
The install script symlinks `tmux/.tmux.conf` to `~/.tmux.conf` and your local
overrides from `tmux.conf.local` to `~/.tmux.conf.local`.
