# linux-confs

Personal Arch/CachyOS environment — sway + waybar + foot + bash, plus the
fixes needed to make gnome-keyring (and therefore 1Password's 2FA token
persistence and SSH agent) work correctly under sway.

## Layout

```
home/.bash_profile        -> ~/.bash_profile
home/.bashrc              -> ~/.bashrc
home/.xonshrc             -> ~/.xonshrc
sway/config               -> ~/.config/sway/config
sway/scripts/lock.sh      -> ~/.config/sway/scripts/lock.sh
i3/config                 -> ~/.config/i3/config
foot/foot/                -> ~/.config/foot/   (whole dir)
waybar/waybar/            -> ~/.config/waybar/ (whole dir)
```

Plus post-install: installs `xontrib-prompt-starship` (for xonsh's starship prompt)
and wires `delta` in as git's diff/log pager.

## Install on a fresh machine

```
git clone <this-repo> ~/linux-confs
cd ~/linux-confs
./install.sh
```

`install.sh` is idempotent. Existing non-symlink targets in `$HOME` are
backed up to `<target>.bak.<timestamp>` before being replaced.

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
- `sway/config` — removes the redundant `gnome-keyring-daemon --start`
  line; the systemd user unit `gnome-keyring-daemon.socket` socket-
  activates it on demand instead.

## Keeping the repo in sync with `~/.config`

After `install.sh`, the home-side paths are symlinks into this repo, so
edits land here automatically. Two exceptions worth knowing:

- **First-time edits** on a fresh machine before `install.sh` runs:
  changes go to `~/.config/...` first; copy back into the repo manually.
- **`waybar/` and `foot/` are directory symlinks**, so adding new
  scripts/themes inside them shows up in `git status` automatically. New
  top-level apps need a new repo dir + a new `link` line in `install.sh`.
