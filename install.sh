#!/usr/bin/env bash
# install.sh — Provision a fresh Arch/CachyOS machine with these configs.
# Idempotent: safe to re-run. Existing non-symlink targets are backed up
# to <target>.bak.<timestamp> before being replaced.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"

# Required packages for the sway/waybar/foot stack and the keyring fix.
# Tweak this list to taste.
PACKAGES=(
  # Sway / waybar / WM stack
  sway swaylock swayidle swaybg
  waybar mako foot
  dex swayosd
  polkit-gnome gnome-keyring
  rofi grim slurp jq
  brightnessctl
  wireplumber pipewire-pulse

  # Shells + prompt
  bash xonsh starship python-pip

  # Modern CLI replacements (eza/bat/fd/rg/zoxide/delta/btop/dust/procs)
  bat eza fd ripgrep zoxide git-delta btop dust procs

  # Multiplexer + fuzzy finder + remote shell
  tmux fzf mosh

  # Terminal + Nerd Font (workstation-only; harmless on servers)
  kitty ttf-jetbrains-mono-nerd
)

require_pacman() {
  if ! command -v pacman >/dev/null 2>&1; then
    echo "ERROR: pacman not found. This script targets Arch/CachyOS." >&2
    exit 1
  fi
}

install_packages() {
  echo "==> Installing packages (sudo pacman -S --needed)..."
  sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"
}

# link <source-in-repo> <target-in-home>
#   - skips if target is already the correct symlink
#   - backs up any other existing target to <target>.bak.<TS>
#   - creates parent dirs as needed
link() {
  local src="$1"
  local dst="$2"
  if [[ ! -e "$src" ]]; then
    echo "  SKIP: $src missing in repo" >&2
    return
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" ]] && [[ "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
    echo "  ok:     $dst"
    return
  fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    local bak="${dst}.bak.${TS}"
    echo "  backup: $dst -> $bak"
    mv "$dst" "$bak"
  fi
  ln -s "$src" "$dst"
  echo "  link:   $dst -> $src"
}

link_configs() {
  echo "==> Symlinking configs..."
  link "$REPO/home/.bash_profile"   "$HOME/.bash_profile"
  link "$REPO/home/.bashrc"         "$HOME/.bashrc"
  link "$REPO/home/.xonshrc"        "$HOME/.xonshrc"
  link "$REPO/sway/config"          "$HOME/.config/sway/config"
  link "$REPO/sway/scripts/lock.sh" "$HOME/.config/sway/scripts/lock.sh"
  link "$REPO/i3/config"            "$HOME/.config/i3/config"
  link "$REPO/foot/foot"            "$HOME/.config/foot"
  link "$REPO/waybar/waybar"        "$HOME/.config/waybar"
}

# Post-install steps that the package install + symlinks don't cover.
post_install() {
  echo "==> Post-install configuration..."

  # xontrib bridges starship into xonsh (starship doesn't natively support xonsh).
  if command -v xpip >/dev/null 2>&1; then
    echo "  xpip: xontrib-prompt-starship"
    xpip install --user --break-system-packages --quiet xontrib-prompt-starship || true
  fi

  # Wire git-delta in as the diff/log pager.
  if command -v delta >/dev/null 2>&1; then
    echo "  git: configuring delta as pager"
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    git config --global delta.navigate true
    git config --global delta.line-numbers true
    git config --global delta.side-by-side true
    git config --global merge.conflictstyle diff3
    git config --global diff.colorMoved default
  fi
}

enable_user_services() {
  echo "==> Enabling systemd --user units..."
  systemctl --user daemon-reload
  # gnome-keyring's secret service is socket-activated; enabling the socket
  # is what makes 1Password's 2FA token persist across unlocks.
  systemctl --user enable --now gnome-keyring-daemon.socket
}

main() {
  require_pacman
  install_packages
  link_configs
  post_install
  enable_user_services
  cat <<EOF

Done.

Next steps:
  1. Log out of any current sway session.
  2. Log back in on tty1 — .bash_profile will exec sway directly
     (no dbus-run-session wrapper) on the systemd user bus.
  3. The first time 1Password reaches gnome-keyring, you may see a
     one-time prompt to unlock the login keyring. Use your login password.
EOF
}

main "$@"
