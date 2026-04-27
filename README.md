# linux-confs

Personal Arch/CachyOS environment — sway + waybar + foot + bash, plus the
fixes needed to make gnome-keyring (and therefore 1Password's 2FA token
persistence and SSH agent) work correctly under sway.

## Layout

```
home/.bash_profile        -> ~/.bash_profile
sway/config               -> ~/.config/sway/config
sway/scripts/lock.sh      -> ~/.config/sway/scripts/lock.sh
i3/config                 -> ~/.config/i3/config
foot/foot/                -> ~/.config/foot/   (whole dir)
waybar/waybar/            -> ~/.config/waybar/ (whole dir)
```

## Install on a fresh machine

```
git clone <this-repo> ~/linux-confs
cd ~/linux-confs
./install.sh
```

`install.sh` is idempotent. Existing non-symlink targets in `$HOME` are
backed up to `<target>.bak.<timestamp>` before being replaced.

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

## Known drift

The `waybar/` and `foot/` directories in this repo predate recent local
edits and may be missing some scripts/themes present on the live machine.
Sync them back when you next touch them.
