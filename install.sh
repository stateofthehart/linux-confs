#!/usr/bin/env bash
# install.sh — Provision a machine with these configs (Arch/CachyOS or
# Ubuntu/Debian). Idempotent: safe to re-run. Existing non-symlink targets
# are backed up to <target>.bak.<timestamp> before being replaced.
#
# Porting notes (Ubuntu package gaps, laptop-vs-desktop bits, DisplayLink
# warnings) live in PORTING.md — read it before provisioning a new box.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
HOST="$(hostname -s)"

# ---------------------------------------------------------------- packages

# Arch/CachyOS package names.
PACKAGES_ARCH=(
  # Sway / waybar / WM stack
  sway swaylock swayidle swaybg
  waybar mako kanshi foot kitty
  dex swayosd
  polkit-gnome gnome-keyring
  rofi grim slurp wl-clipboard jq
  playerctl psmisc libnotify
  brightnessctl
  wireplumber pipewire-pulse

  # Shells + prompt
  bash xonsh starship python-pip

  # Modern CLI replacements (eza/bat/fd/rg/zoxide/delta/btop/dust/procs)
  bat eza fd ripgrep zoxide git-delta btop dust procs

  # Multiplexer + fuzzy finder + remote shell
  tmux fzf mosh

  # Nerd Font (waybar/kitty glyphs)
  ttf-jetbrains-mono-nerd
)

# Ubuntu 24.04 package names (verified against noble on 2026-07-24).
PACKAGES_UBUNTU=(
  # Sway / waybar / WM stack — note the renames vs Arch:
  #   mako->mako-notifier, polkit-gnome->policykit-1-gnome,
  #   dmenu->suckless-tools, libnotify->libnotify-bin
  sway swaylock swayidle swaybg
  waybar mako-notifier kanshi foot kitty
  dex
  policykit-1-gnome gnome-keyring
  rofi grim slurp wl-clipboard jq
  playerctl psmisc libnotify-bin suckless-tools
  brightnessctl
  wireplumber pipewire-pulse pipewire-bin

  # Shells + CLI (only what noble actually packages; bat installs as
  # `batcat`, fd-find as `fdfind`)
  bash xonsh bat fd-find ripgrep zoxide btop
  tmux fzf mosh
)

# Not packaged on Ubuntu 24.04 — informational, printed after install.
UBUNTU_GAPS="
  swayosd     volume/brightness OSD — build from source (Rust,
              github.com/ErikReider/SwayOSD) or drop; sway config degrades
              gracefully without it
  nwg-look    GTK-theme picker bound to Super+s — upstream .deb from
              github.com/nwg-piotr/nwg-look, or rebind
  starship / eza / git-delta / dust / procs
              prompt + CLI extras — cargo install, or upstream installers
  amdgpu_top  optional gpu.sh fallback — cargo install amdgpu_top
"

detect_distro() {
  if command -v pacman >/dev/null 2>&1; then
    echo arch
  elif command -v apt-get >/dev/null 2>&1; then
    echo debian
  else
    echo "ERROR: neither pacman nor apt-get found." >&2
    exit 1
  fi
}

install_packages() {
  case "$1" in
    arch)
      echo "==> Installing packages (pacman)..."
      sudo pacman -S --needed --noconfirm "${PACKAGES_ARCH[@]}"
      ;;
    debian)
      echo "==> Installing packages (apt)..."
      sudo apt-get update -qq
      sudo apt-get install -y "${PACKAGES_UBUNTU[@]}"
      echo
      echo "NOT packaged on Ubuntu 24.04 (manual, see PORTING.md):"
      echo "$UBUNTU_GAPS"
      ;;
  esac
}

# Nerd Font: Ubuntu's fonts-jetbrains-mono is the UNPATCHED upstream and lacks
# every glyph the waybar/kitty configs use. Fetch the patched TTFs per-user.
install_fonts() {
  if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
    echo "  fonts: JetBrainsMono Nerd Font already present"
    return
  fi
  local dst="$HOME/.local/share/fonts/JetBrainsMonoNerd"
  echo "  fonts: downloading JetBrainsMono Nerd Font -> $dst"
  mkdir -p "$dst"
  local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
  if curl -fsSL "$url" | tar -xJ -C "$dst" 2>/dev/null; then
    fc-cache -f "$dst"
  else
    echo "  fonts: download failed — install manually from nerd-fonts releases" >&2
  fi
}

# ------------------------------------------------------------------ linking

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

  # Whole config dirs. Host-local files inside them (sway/config.d/*,
  # waybar/fallback-sink) are gitignored, so they never dirty the repo.
  link "$REPO/config/sway"          "$HOME/.config/sway"
  link "$REPO/config/waybar"        "$HOME/.config/waybar"
  link "$REPO/config/foot"          "$HOME/.config/foot"
  link "$REPO/config/kitty"         "$HOME/.config/kitty"
  link "$REPO/config/mako"          "$HOME/.config/mako"

  # swaylock: link the theme config only. swaylock-pam-config is fprintd/
  # laptop-specific and must NEVER be auto-installed to /etc/pam.d.
  link "$REPO/config/swaylock/config" "$HOME/.config/swaylock/config"

  # Autostart entries (dex --autostart picks these up)
  local f
  for f in "$REPO"/config/autostart/*.desktop; do
    link "$f" "$HOME/.config/autostart/$(basename "$f")"
  done

  # sway includes config.d/*.conf for per-host overrides; make sure it exists
  # (a real dir inside the possibly-symlinked sway config dir, gitignored).
  mkdir -p "$HOME/.config/sway/config.d"
}

link_host_configs() {
  local hostdir="$REPO/hosts/$HOST"
  if [[ ! -d "$hostdir" ]]; then
    echo "==> No hosts/$HOST/ — skipping per-host config (see hosts/README.md)"
    return
  fi
  echo "==> Per-host config for $HOST..."
  # Monitor topology: kanshi profiles (laptops/docks)...
  [[ -f "$hostdir/kanshi/config" ]] && \
    link "$hostdir/kanshi/config" "$HOME/.config/kanshi/config"
  # ...or static sway output lines (desktops). Mutually exclusive with kanshi.
  [[ -f "$hostdir/sway-outputs.conf" ]] && \
    link "$hostdir/sway-outputs.conf" "$HOME/.config/sway/config.d/outputs.conf"
}

# ------------------------------------------------------------- post-install

post_install() {
  echo "==> Post-install configuration..."

  install_fonts

  # waybar volume.sh recovery: record this host's sink node name if we can.
  local sinkfile="$HOME/.config/waybar/fallback-sink"
  if [[ ! -s "$sinkfile" ]] && command -v wpctl >/dev/null 2>&1; then
    local sink
    sink="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
            | awk -F'"' '/node.name/{print $2; exit}')" || true
    if [[ -n "${sink:-}" ]]; then
      echo "$sink" > "$sinkfile"
      echo "  waybar: fallback-sink = $sink"
    fi
  fi

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
  # gnome-keyring's secret service is socket-activated; enabling the socket
  # is what makes 1Password's 2FA token persist across unlocks.
  systemctl --user daemon-reload
  systemctl --user enable --now gnome-keyring-daemon.socket

  # Bluetooth A2DP watchdog — only where there's a bluetooth adapter.
  if compgen -G "/sys/class/bluetooth/hci*" >/dev/null 2>&1; then
    link "$REPO/systemd/user/bt-a2dp-watchdog.service" \
         "$HOME/.config/systemd/user/bt-a2dp-watchdog.service"
    systemctl --user daemon-reload
    systemctl --user enable --now bt-a2dp-watchdog.service
    echo "  bt-a2dp-watchdog: enabled"
  else
    echo "  bt-a2dp-watchdog: skipped (no bluetooth adapter)"
  fi

  # Ubuntu's waybar/mako debs ship user units wired into
  # graphical-session.target. The sway config owns both via exec_always, so
  # those units would double-start the bar under sway and leak waybar/mako
  # into GNOME sessions. Mask them where present.
  local u
  for u in waybar.service mako.service; do
    if [[ -e "/usr/lib/systemd/user/$u" ]]; then
      systemctl --user mask --quiet "$u" 2>/dev/null || true
      echo "  masked vendor unit: $u (sway config exec_always owns it)"
    fi
  done
}

main() {
  local distro
  distro="$(detect_distro)"
  echo "==> Distro: $distro, host: $HOST"
  install_packages "$distro"
  link_configs
  link_host_configs
  post_install
  enable_user_services
  echo "==> Validating sway config..."
  # --unsupported-gpu: proprietary-NVIDIA hosts refuse to start without it.
  # WLR_BACKENDS=headless: sway 1.9's --validate still initializes a backend,
  # which fails without a seat (e.g. over ssh). Both are scoped to this one
  # subprocess — they never touch the real session environment.
  WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
    sway --unsupported-gpu --validate -c "$HOME/.config/sway/config" || {
    echo "ERROR: sway config failed validation — fix before logging in!" >&2
    exit 1
  }
  cat <<EOF

Done.

Next steps:
  1. If this is a NEW host: check PORTING.md, then create hosts/$HOST/ with
     its monitor topology (kanshi config or sway-outputs.conf) and re-run.
  2. Log out of any current sway session.
  3. Log back in on tty1 — .bash_profile will exec sway directly
     (no dbus-run-session wrapper) on the systemd user bus.
  4. The first time 1Password reaches gnome-keyring, you may see a
     one-time prompt to unlock the login keyring. Use your login password.

DisplayLink hosts (e.g. phantom): sway is launched through a wrapper that
sets WLR_* and LD_LIBRARY_PATH. Never set WLR_* in sway config,
environment.d, or systemd user units — see PORTING.md.
EOF
}

main "$@"
