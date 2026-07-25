# PORTING.md — provisioning a new machine

Distilled from the wraith (CachyOS laptop) → phantom (Ubuntu 24.04 desktop,
DisplayLink) migration, 2026-07. Read this before running `install.sh` on a
new box; most of it is already automated, the rest is a checklist.

## What's already handled for you

These used to be hardcoded-for-wraith and are now portable:

| Was | Now |
|---|---|
| `cpu.sh` / `gpu.sh` hardcoded `hwmon5`/`hwmon4` | resolved by driver name (`k10temp`/`zenpower`/`coretemp`, `amdgpu`) at runtime |
| `volume.sh` hardcoded wraith's PCI sink name | reads `~/.config/waybar/fallback-sink` (host-local, gitignored); `install.sh` seeds it from `wpctl` |
| sway config hardcoded Arch's polkit agent path | `sway/scripts/polkit-agent.sh` tries Arch, Ubuntu/Debian, and Fedora paths |
| monitor layout baked into shared config | per-host under `hosts/<hostname>/` → kanshi config (laptops) or `sway-outputs.conf` → `~/.config/sway/config.d/` (desktops) |
| Arch-only package list | `install.sh` detects pacman vs apt and uses per-distro name maps |

## Package name mapping (Arch ↔ Ubuntu 24.04)

Same name on both: sway swaylock swayidle swaybg waybar kanshi foot kitty dex
gnome-keyring rofi grim slurp wl-clipboard jq playerctl psmisc brightnessctl
wireplumber pipewire-pulse tmux fzf mosh ripgrep zoxide btop bat eza xonsh.

| Arch | Ubuntu 24.04 | Note |
|---|---|---|
| mako | mako-notifier | |
| polkit-gnome | policykit-1-gnome | binary path differs too — handled by polkit-agent.sh |
| libnotify | libnotify-bin | for `notify-send` |
| dmenu | suckless-tools | `dmenu` alone is not a package |
| fd | fd-find | binary is `fdfind` |
| ttf-jetbrains-mono-nerd | — | `fonts-jetbrains-mono` is the UNPATCHED font (no bar glyphs); install.sh downloads the Nerd Font per-user instead |
| swayosd | — | no Ubuntu package; build from source or drop (OSD only, config degrades gracefully) |
| starship, git-delta, dust, procs | — | not in noble; installed from pinned GitHub releases by the homelab-ansible cli_tools role |
| rofi (2.x, native Wayland) | rofi 1.7 (X11) | runs via XWayland; native alternatives: fuzzel, wmenu |

Waybar version gap: Arch ships 0.15.x, noble 0.9.24. The configs stay within
0.9.24's feature set, but `sway/workspaces` `window-rewrite` and
`custom/media-info` `hide-empty-text` are near the edge (landed ~0.9.22) —
if workspace app-dots or the media pill misbehave on an old waybar, those keys
are the suspects. Waybar ignores unknown keys rather than crashing.

sway version note: everything in `config/sway/config` is sway ≥1.9 compatible
(verified against phantom's 1.9). Avoid 1.10+ features (`allow_tearing`,
`primary`, HDR options) unless every host is upgraded.

## Laptop-only components (inert or wrong on desktops)

- `XF86MonBrightness*` bindings + waybar `backlight` module — no backlight
  device on desktops; bindings fail silently, module doesn't render.
- waybar `battery` module — logs "No battery" noise; remove from
  `config-bottom` on desktop-only setups if it bothers you.
- `input type:touchpad` block — matches nothing on a desktop, harmless.
- `config/swaylock/swaylock-pam-config` — PAM stack with `pam_fprintd`
  (fingerprint). **Never install on a host without fprintd**; install.sh
  deliberately doesn't touch `/etc/pam.d`.
- `bt-a2dp-watchdog` — install.sh enables it only if `/sys/class/bluetooth`
  has an adapter.
- waybar `custom/network` (`network-tooltip.sh`) — requires NetworkManager;
  on netplan/systemd-networkd hosts it shows "Offline" forever. The speed
  and IP scripts are sysfs-based and portable.

## GPU note

`gpu.sh` reads amdgpu sysfs only. On a multi-GPU box (e.g. AMD iGPU +
NVIDIA dGPU) it reports whichever amdgpu card exists and cannot see the
NVIDIA card (that needs `nvidia-smi`). Pick which GPU you actually want on
the bar per-host.

## DisplayLink / evdi hosts (phantom!)

- phantom launches sway through a wrapper that sets `WLR_EVDI_RENDER_DEVICE`,
  `WLR_DRM_DEVICES`, and `LD_LIBRARY_PATH` for a patched wlroots. **Setting
  any `WLR_*` variable in sway config, `environment.d`, or a systemd user
  unit breaks its DisplayLink output.** This repo sets none — keep it that
  way.
- On such hosts sway must be started through that wrapper, never as plain
  `sway`. `.bash_profile`'s tty1 autostart execs
  `~/.config/sway/start-wrapper` (host-local, gitignored) when it exists —
  point it at the DisplayLink launcher; hosts without the file get plain
  sway as before.
- phantom's two monitors report identical EDID (XEC 4433, serial "Unknown"):
  they can only be matched by connector name (`DVI-I-1`/`DVI-I-2`), never by
  `output "Make Model Serial"`. Same is true of wraith's dock monitors —
  hence the docked/docked-swapped kanshi profile pair.
- Prefer the monitor's preferred mode (60 Hz) first; high-refresh over
  USB/evdi is a bandwidth gamble to try later.
- `sway/scripts/output-catchall.sh` is the failsafe when no layout matches:
  it only acts when two active outputs physically overlap (the stacked-at-0,0
  signature), so it never fights kanshi or the static config.d outputs.

## New-host checklist

1. `git clone` this repo, `./install.sh` (it validates the sway config at
   the end and refuses silently-broken installs).
2. Create `hosts/$(hostname -s)/` with kanshi config (laptop/dock) or
   `sway-outputs.conf` (desktop, fixed monitors); re-run `./install.sh`.
   Don't guess left/right for identical monitors — check with
   `swaymsg output <name> power off`, then fix positions.
3. Log in on tty1 (`.bash_profile` execs sway).
4. Verify: both waybar bars render with icons (Nerd Font), volume keys work
   (`fallback-sink` seeded), polkit prompts appear (run `pkexec true`),
   notifications show (`notify-send test`), lock works (Super+L),
   screenshots work (Print).
5. Anything host-weird you had to do → record it in `hosts/<host>/` or this
   file, not in the shared configs.
