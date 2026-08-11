#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc

# Auto-start sway on tty1 login.
# Hosts that must NOT run plain `sway` (e.g. phantom's DisplayLink setup needs
# a wrapper that sets WLR_*/LD_LIBRARY_PATH for a patched wlroots) drop their
# launcher at ~/.config/sway/start-wrapper (host-local, gitignored) and it is
# used instead. No wrapper file -> plain sway, unchanged behavior.
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "${XDG_VTNR:-0}" -eq 1 ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID}/bus"
  if [ -x "$HOME/.config/sway/start-wrapper" ]; then
    exec "$HOME/.config/sway/start-wrapper"
  fi
  exec sway
fi


# uv drops a PATH shim at ~/.local/bin/env. Only some hosts have uv installed,
# so guard it — unguarded this errors on every login on a fresh machine.
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# NOTE: ~/.bashrc is already sourced at the top of this file; sourcing it again
# here ran every rc line twice (visible as duplicated startup errors).

# opencode
export PATH=/home/ethan/.opencode/bin:$PATH

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

alias unclaude='claude --dangerously-skip-permissions'

alias netcheck='ping -c 5 8.8.8.8'
alias netfresh='sudo modprobe -r ath11k_pci && sudo modprobe ath11k_pci'
alias protonvpn='protonvpn 2> >(grep -v "keyring_linux\|SecretService\|KeyringLocked\|_is_backend_working\|get_preferred_collection\|get_password" >&2)'

