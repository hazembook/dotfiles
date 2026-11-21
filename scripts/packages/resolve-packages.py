#!/usr/bin/env python3
"""
Resolve and query dotfiles packages from dotfiles-packages.yaml.
Supports Arch, Debian/Ubuntu, and Termux environments with zero external pip dependencies.
"""

import argparse
import os
import shutil
import subprocess
import sys

def parse_yaml_fallback(text: str) -> dict:
    """Fallback YAML parser for dotfiles-packages.yaml when PyYAML is not installed."""
    data = {"modules": {}, "profiles": {}}
    cur_sec = None
    cur_mod = None
    cur_pkg = None
    cur_prof = None

    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.strip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        s = line.strip()

        if indent == 0:
            if s == "modules:":
                cur_sec = "modules"
            elif s == "profiles:":
                cur_sec = "profiles"
            continue

        if cur_sec == "modules":
            if indent == 2 and s.endswith(":"):
                cur_mod = s[:-1]
                data["modules"][cur_mod] = {"packages": {}}
            elif indent == 4 and s.startswith("description:"):
                desc = s.split(":", 1)[1].strip().strip("\"'")
                data["modules"][cur_mod]["description"] = desc
            elif indent == 4 and s == "packages:":
                continue
            elif indent == 6 and s.endswith(":"):
                cur_pkg = s[:-1]
                data["modules"][cur_mod]["packages"][cur_pkg] = {}
            elif indent == 8 and ":" in s:
                k, v = s.split(":", 1)
                data["modules"][cur_mod]["packages"][cur_pkg][k.strip()] = v.strip().strip("\"'")
        elif cur_sec == "profiles":
            if indent == 2 and s.endswith(":"):
                cur_prof = s[:-1]
                data["profiles"][cur_prof] = []
            elif indent == 4 and s.startswith("modules:"):
                rest = s.split(":", 1)[1].strip()
                if rest.startswith("[") and rest.endswith("]"):
                    items = [x.strip() for x in rest[1:-1].split(",") if x.strip()]
                    data["profiles"][cur_prof] = items
            elif indent == 6 and s.startswith("- "):
                data["profiles"][cur_prof].append(s[2:].strip())

    return data

def load_inventory(yaml_path: str) -> dict:
    if yaml_path == "-":
        content = sys.stdin.read()
    else:
        with open(yaml_path, "r", encoding="utf-8") as f:
            content = f.read()

    try:
        import yaml
        return yaml.safe_load(content)
    except ImportError:
        return parse_yaml_fallback(content)

def detect_distro() -> str:
    if os.environ.get("TERMUX_VERSION") or os.path.isdir("/data/data/com.termux/files/usr"):
        return "termux"
    if os.path.exists("/etc/NIXOS"):
        return "nixos"
    if shutil.which("pacman"):
        return "arch"
    if shutil.which("apt"):
        return "debian"
    return "unknown"

def detect_profile(distro: str) -> str:
    if distro == "termux":
        return "termux"
    wayland = os.environ.get("WAYLAND_DISPLAY")
    x11 = os.environ.get("DISPLAY")
    desktop = os.environ.get("XDG_CURRENT_DESKTOP")
    if wayland or x11 or desktop:
        return "desktop"
    return "cli"

def is_pkg_installed(pkg_name: str, distro: str) -> tuple[bool, str]:
    """Check if a package is installed. Returns (is_installed, version_str)."""
    if distro == "arch":
        res = subprocess.run(
            ["pacman", "-Q", pkg_name],
            capture_output=True,
            text=True
        )
        if res.returncode == 0:
            parts = res.stdout.strip().split()
            version = parts[1] if len(parts) > 1 else "installed"
            return True, version
        return False, ""

    elif distro in ("debian", "termux"):
        res = subprocess.run(
            ["dpkg-query", "-W", "-f=${Status}|${Version}", pkg_name],
            capture_output=True,
            text=True
        )
        if res.returncode == 0 and "install ok installed" in res.stdout:
            parts = res.stdout.split("|")
            version = parts[1] if len(parts) > 1 else "installed"
            return True, version
        return False, ""

    return False, ""

def main():
    parser = argparse.ArgumentParser(description="Resolve packages for dotfiles")
    parser.add_argument("--file", "-f", default=None, help="Path to dotfiles-packages.yaml")
    parser.add_argument("--distro", "-d", choices=["arch", "debian", "termux"], default=None)
    parser.add_argument("--profile", "-p", choices=["desktop", "cli", "termux"], default=None)
    parser.add_argument("--modules", "-m", nargs="+", help="Explicit module names to load")
    parser.add_argument("--format", choices=["list", "inspect"], default="list",
                        help="'list' outputs package names; 'inspect' performs installed-checks")
    args = parser.parse_args()

    yaml_file = args.file
    if not yaml_file:
        try:
            script_dir = os.path.dirname(os.path.abspath(__file__))
        except NameError:
            script_dir = os.getcwd()
        yaml_file = os.path.join(script_dir, "dotfiles-packages.yaml")

    if not os.path.exists(yaml_file):
        sys.stderr.write(f"Error: inventory not found at {yaml_file}\n")
        sys.exit(1)

    distro = args.distro or detect_distro()
    profile = args.profile or detect_profile(distro)

    inv = load_inventory(yaml_file)
    active_modules = args.modules
    if not active_modules:
        prof_entry = inv.get("profiles", {}).get(profile, [])
        if isinstance(prof_entry, dict):
            active_modules = prof_entry.get("modules", [])
        elif isinstance(prof_entry, list):
            active_modules = prof_entry
        else:
            active_modules = []

    resolved_pkgs = []
    seen = set()

    for mod_name in active_modules:
        mod = inv.get("modules", {}).get(mod_name, {})
        for canonical_name, platforms in mod.get("packages", {}).items():
            target_pkg = platforms.get(distro, "").strip()
            if target_pkg and target_pkg not in seen:
                seen.add(target_pkg)
                resolved_pkgs.append((canonical_name, target_pkg, mod_name))

    if args.format == "list":
        # Print space-separated package list for direct consumption by package managers
        pkgs = [p[1] for p in resolved_pkgs]
        print(" ".join(pkgs))

    elif args.format == "inspect":
        # Output detailed status per package: canonical | target_pkg | module | is_installed | version
        for canonical, target, mod in resolved_pkgs:
            installed, ver = is_pkg_installed(target, distro)
            status_str = "1" if installed else "0"
            print(f"{canonical}\t{target}\t{mod}\t{status_str}\t{ver}")

if __name__ == "__main__":
    main()
