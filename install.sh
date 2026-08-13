#!/usr/bin/env bash
# install.sh — Provision a machine with these configs (Arch/CachyOS,
# Ubuntu/Debian, or Fedora). Idempotent: safe to re-run. Existing non-symlink
# targets are backed up to <target>.bak.<timestamp> before being replaced.
#
# Porting notes (per-distro package gaps, aarch64 notes, laptop-vs-desktop
# bits, DisplayLink warnings) live in PORTING.md — read it before provisioning
# a new box.
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
  polkit-gnome gnome-keyring blueman
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
  policykit-1-gnome gnome-keyring blueman
  rofi grim slurp wl-clipboard jq
  playerctl psmisc libnotify-bin suckless-tools
  brightnessctl
  wireplumber pipewire-pulse pipewire-bin

  # Shells + CLI (only what noble actually packages; bat installs as
  # `batcat`, fd-find as `fdfind`)
  bash xonsh bat eza fd-find ripgrep zoxide btop
  tmux fzf mosh
)

# Not packaged on Ubuntu 24.04 — informational, printed after install.
UBUNTU_GAPS="
  swayosd     volume/brightness OSD — build from source (Rust,
              github.com/ErikReider/SwayOSD) or drop; sway config degrades
              gracefully without it
  nwg-look    GTK-theme picker bound to Super+s — upstream .deb from
              github.com/nwg-piotr/nwg-look, or rebind
  starship / git-delta / dust / procs
              prompt + CLI extras — run the homelab-ansible cli_tools role
              (pinned GitHub releases), or cargo install
  amdgpu_top  optional gpu.sh fallback — cargo install amdgpu_top
"

# Fedora package names (probed against Fedora 44 aarch64 on 2026-08-11).
# Differences from Arch worth knowing:
#   dust         -> du-dust   (same rename as Ubuntu; binary is still `dust`)
#   fd           -> fd-find   (binary IS `fd` here, unlike Ubuntu's `fdfind`)
#   pipewire-pulse -> pipewire-pulseaudio
#   polkit-gnome -> does not exist; mate-polkit is the closest GTK agent
#                   (see sway/scripts/polkit-agent.sh, which knows its path)
# bat and fd keep their real binary names on Fedora, so the ~/.local/bin
# shims cli-install.sh creates for Ubuntu are unnecessary here (harmless).
PACKAGES_FEDORA=(
  # Sway / waybar / WM stack
  sway swaylock swayidle swaybg
  waybar mako kanshi foot kitty
  mate-polkit gnome-keyring blueman
  rofi grim slurp wl-clipboard jq
  playerctl psmisc libnotify dmenu
  brightnessctl
  wireplumber pipewire-pulseaudio

  # Shells + prompt
  bash xonsh python3-pip

  # Modern CLI replacements
  bat eza fd-find ripgrep zoxide git-delta btop du-dust procs

  # Multiplexer + fuzzy finder + remote shell
  tmux fzf mosh

  # UNPATCHED font — install_fonts() fetches the patched Nerd Font per-user
  jetbrains-mono-fonts
)

# Not packaged on Fedora 44 — informational, printed after install.
FEDORA_GAPS="
  dex         XDG autostart runner used by 'exec_always dex --autostart' in
              sway/config. Single Python script: pip install --user dex, or
              comment out that line and lose ~/.config/autostart handling.
  swayosd     volume/brightness OSD — build from source or drop; the sway
              config degrades gracefully without it (same as Ubuntu).
  starship    prompt — NOT in Fedora repos. cli-install.sh fetches the
              aarch64 GitHub release, or: dnf copr enable atim/starship
  nwg-look    GTK-theme picker bound to Super+s — build from source or rebind
  amdgpu_top  irrelevant here: this machine is Adreno, not amdgpu. gpu.sh
              reads amdgpu sysfs only and will render empty — drop the waybar
              GPU module on Snapdragon hosts.
"

detect_distro() {
  if command -v pacman >/dev/null 2>&1; then
    echo arch
  elif command -v apt-get >/dev/null 2>&1; then
    echo debian
  elif command -v dnf >/dev/null 2>&1; then
    echo fedora
  else
    echo "ERROR: none of pacman, apt-get, or dnf found." >&2
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
    fedora)
      echo "==> Installing packages (dnf)..."
      # dnf aborts the whole transaction on any missing package, so install in
      # one batch of known-good names only; gaps are reported, not attempted.
      sudo dnf install -y "${PACKAGES_FEDORA[@]}"
      echo
      echo "NOT packaged on Fedora 44 (manual, see PORTING.md):"
      echo "$FEDORA_GAPS"
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

  # IMPORTANT: `[[ ... ]] && cmd` as the LAST statement makes this function
  # return 1 whenever the test is false, and `set -e` then aborts the whole
  # script. That silently killed everything after this point (fonts,
  # fallback-sink, git-delta, systemd user units, sway config validation) on
  # any kanshi-only host — i.e. every laptop, including wraith.
  return 0
}

# --------------------------------------------------------------- audio (arm)

# Qualcomm X1E/X1P laptops need an ASoC topology blob whose filename is derived
# from the DMI model string. linux-firmware ships one per known machine, so a
# machine that shipped after the last firmware release gets NO sound card at
# all -- not a misconfigured one, an absent one. That is what happened on
# specter (ThinkBook 16 G7 QOY): the kernel asked for
# X1E80100-LENOVO-ThinkBook-16-tplg.bin, no such file existed anywhere, and the
# card failed to instantiate with -2.
#
# The ThinkPad T14s topology works byte-for-byte because the two boards are
# identical in every audio-relevant device-tree property (same sndcard
# compatible, same wcd9385 headset codec, same RX_0/TX_3/VA_0/WSA_0 DAI links,
# same 2x sdw20217020400 speaker amps, same 4.8MHz DMIC rate). Donor choice
# MUST be made that way, not by "same vendor" -- the Yoga Slim 7x looks similar
# and is wrong (4 speaker drivers, 2 DAI links).
#
# /lib/firmware/updates is searched BEFORE /lib/firmware, so this survives
# linux-firmware upgrades instead of being clobbered by them.
#
# This restores SPEAKERS and HDMI only. The internal microphones stay silent on
# this board for reasons unrelated to the topology -- see PORTING.md.
install_asoc_topology() {
  local model="/proc/device-tree/model"
  [[ -r "$model" ]] || return 0

  local want donor dir="/lib/firmware/updates/qcom/x1e80100"
  case "$(tr -d '\0' < "$model")" in
    *"ThinkBook 16 Gen 7 QOY"*)
      want="X1E80100-LENOVO-ThinkBook-16-tplg.bin"
      donor="X1E80100-LENOVO-Thinkpad-T14s-tplg.bin"
      ;;
    *) return 0 ;;
  esac

  # Already provided by linux-firmware proper? Then upstream has caught up and
  # this workaround must NOT shadow it.
  if compgen -G "/lib/firmware/qcom/x1e80100/${want}*" >/dev/null 2>&1; then
    echo "  audio: $want now shipped by linux-firmware — removing local override"
    sudo rm -f "$dir/$want" "$dir/$want.xz"
    return 0
  fi
  if compgen -G "$dir/${want}*" >/dev/null 2>&1; then
    echo "  audio: topology workaround already in place"
    return 0
  fi

  local src
  src="$(compgen -G "/lib/firmware/qcom/x1e80100/${donor}*" | head -1)" || true
  if [[ -z "${src:-}" ]]; then
    echo "  audio: donor topology $donor not found — speakers will not work" >&2
    return 0
  fi

  # Preserve the donor's compression suffix; the kernel tries .xz then plain.
  local ext="${src##*/}"; ext="${ext#$donor}"
  echo "  audio: installing $want$ext (from T14s topology)"
  sudo mkdir -p "$dir"
  sudo cp -p "$src" "$dir/$want$ext"
  # Fedora enforces SELinux; an unlabelled blob is silently unreadable.
  command -v restorecon >/dev/null 2>&1 && sudo restorecon -R /lib/firmware/updates
  echo "  audio: reboot (or reload snd_soc_x1e80100) to instantiate the card"
}

# ------------------------------------------------------------- post-install

post_install() {
  echo "==> Post-install configuration..."

  install_fonts

  # waybar volume.sh recovery: record this host's sink node name if we can.
  #
  # `auto_null` is PipeWire's dummy sink, present when no real audio device has
  # been detected yet. Recording it is worse than recording nothing: it looks
  # populated so this block never re-runs, and volume.sh then falls back to a
  # sink that does not exist. That happened on specter, where the sound card
  # only appeared later (a missing ASoC topology, see PORTING.md), leaving a
  # permanently broken volume module. So refuse to write it, and overwrite it
  # if a previous run already did.
  local sinkfile="$HOME/.config/waybar/fallback-sink"
  local current=""
  [[ -s "$sinkfile" ]] && current="$(cat "$sinkfile")"
  if [[ -z "$current" || "$current" == "auto_null" ]] && command -v wpctl >/dev/null 2>&1; then
    local sink
    sink="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
            | awk -F'"' '/node.name/{print $2; exit}')" || true
    if [[ -n "${sink:-}" && "${sink}" != "auto_null" ]]; then
      echo "$sink" > "$sinkfile"
      echo "  waybar: fallback-sink = $sink"
    else
      echo "  waybar: no real audio sink yet — leaving fallback-sink unset"
      echo "          (re-run install.sh once audio works, or write the value from"
      echo "           'wpctl inspect @DEFAULT_AUDIO_SINK@' into $sinkfile)"
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
  # Before post_install: it records the default sink, which does not exist
  # until the topology is in place and the card has instantiated.
  install_asoc_topology
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
