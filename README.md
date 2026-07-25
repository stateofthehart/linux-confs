# linux-confs

Personal sway desktop environment — sway + waybar + kitty/foot + bash/xonsh —
installable on **Arch/CachyOS or Ubuntu/Debian** with one script, plus the
fixes needed to make gnome-keyring (and therefore 1Password's 2FA token
persistence and SSH agent) work correctly under sway.

Porting a machine that isn't a wraith-clone? **Read [PORTING.md](PORTING.md)
first** — package name maps, laptop-vs-desktop gotchas, and the DisplayLink
`WLR_*` warning live there.

## Layout

```
config/               mirrors ~/.config — linked whole-dir by install.sh
  sway/               config + scripts/ (lock, monitor-nav, output-catchall,
                      polkit-agent) + CHEATSHEET.md
  waybar/             dual-bar setup: config-top, config-bottom, style.css,
                      scripts/ (cpu, gpu, volume, network, media, bluetooth…)
  foot/  kitty/       terminals (kitty is $term; foot kept for minimal hosts)
  mako/               notifications
  swaylock/           theme config (+ swaylock-pam-config, NOT auto-installed)
  autostart/          .desktop entries started by dex (1Password, Slack)
home/                 ~/.bash_profile  ~/.bashrc  ~/.xonshrc
hosts/<hostname>/     per-host monitor topology — see hosts/README.md
systemd/user/         bt-a2dp-watchdog.service (enabled only if BT hardware)
tools/foot-theme.py   foot theme switcher/previewer
legacy/i3/            pre-sway i3 config, kept for reference
install.sh            provision this machine (packages + symlinks + services)
cli-install.sh        managed shell block for remote hosts (see below)
provision-host        pushes cli-install.sh to remote hosts
PORTING.md            cross-distro / cross-hardware notes
```

Two host-local files live *inside* linked config dirs and are gitignored:
`config/sway/config.d/` (per-host sway overrides, populated from `hosts/`)
and `config/waybar/fallback-sink` (this host's audio sink node name).

## Install on a fresh machine

```
git clone git@github.com:ethans-home-lab/linux-confs.git ~/linux-confs
cd ~/linux-confs
./install.sh
```

Works on Arch/CachyOS (pacman) and Ubuntu 24.04/Debian (apt); it detects the
distro, installs the mapped package set, symlinks configs, seeds host-local
files, enables user services, and **validates the sway config** before
declaring success. Idempotent — existing non-symlink targets are backed up to
`<target>.bak.<timestamp>`.

On Ubuntu it also downloads the JetBrainsMono **Nerd Font** (the `apt` font
is unpatched and lacks every bar glyph) and prints what noble doesn't package
(swayosd, nwg-look, starship/eza/delta — see PORTING.md).

### Per-host monitor layout

Monitor topology never goes in the shared sway config. `install.sh` links
`hosts/$(hostname -s)/` if present:

- laptop/dock → `hosts/<host>/kanshi/config` (profiles per output-set)
- desktop, fixed monitors → `hosts/<host>/sway-outputs.conf` →
  `~/.config/sway/config.d/outputs.conf` (the main config `include`s that dir)

New machine: run `install.sh`, create your `hosts/<host>/` dir, re-run.
Details and current hosts: [hosts/README.md](hosts/README.md).

## Provision a remote shell

`provision-host` uploads `cli-install.sh` to remote hosts and installs the
managed shell block:

```
./provision-host bmc-api
./provision-host --xonsh bmc-api
```

Nerd Font icons are a rendering dependency of the terminal you are looking at,
not just a package on the remote host. `provision-host` enables Starship and
writes `eza --icons=always` by default so remote interactive shells keep file
icons. If a client terminal renders those glyphs as placeholders, re-run with
`--no-icons`.

To let `eza` decide when to display icons:

```
./provision-host --icons=auto bmc-api
```

For plain output:

```
./provision-host --no-icons --no-starship bmc-api
```

The provisioned Bash block also forces a UTF-8 locale when SSH starts with an
ASCII locale. This matters for tmux: tmux decides glyph handling from the
locale/client it starts with, so Nerd Font icons can render outside tmux but
break inside tmux if the server was born under `C`/ASCII. The managed tmux
block sets `tmux-256color`, propagates locale variables into panes, and the
interactive shell aliases `tmux` to `tmux -u`.

## What the keyring fix does

On a Wayland-only sway session, wrapping sway in `dbus-run-session` (a
common but outdated pattern) creates a private `/tmp/dbus-XXXXXX` session
bus separate from the systemd user bus at `/run/user/$UID/bus`. Apps under
that wrapper — including 1Password auto-started by `dex` — can't reach
the gnome-keyring Secret Service registered on the real bus. 1Password
then can't save its 2FA token, hangs SSH signing, and re-prompts for 2FA
every unlock.

The fix lives in two files:

- `home/.bash_profile` — auto-starts sway on tty1 with `exec sway`
  (no `dbus-run-session`), so everything inherits `/run/user/$UID/bus`.
- `config/sway/config` — no `gnome-keyring-daemon --start` line; the
  systemd user unit `gnome-keyring-daemon.socket` socket-activates it on
  demand instead (install.sh enables the socket).

## Keeping the repo in sync with `~/.config`

After `install.sh`, the home-side paths are symlinks into this repo, so
edits land here automatically — `git status` in `~/linux-confs` shows them.
Exceptions worth knowing:

- **First-time edits on a machine that hasn't run `install.sh`**: changes go
  to real files in `~/.config`; copy them back into the repo manually (this
  repo drifted three months that way once — check `diff -r` if unsure).
- **Host-local files** (`config.d/`, `fallback-sink`) are gitignored by
  design; per-host things that should be *shared* belong in `hosts/<host>/`.
- **New top-level apps** need a repo dir under `config/` + a `link` line in
  `install.sh`.
