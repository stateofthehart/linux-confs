# Sway cheatsheet

Modifiers used in this config:
- **Alt** = `$mod` (Mod1)
- **Super** = `$wndw` (Mod4, the Windows/Command key)

---

## Apps and launchers

| Keys | Action |
|---|---|
| `Alt+Enter` | Open terminal (kitty + bash) |
| `Alt+d` | Rofi window switcher (jump to an existing window) |
| `Super+d` | Rofi app launcher (drun) |
| `Alt+Super+d` | dmenu_run |
| `Super+s` | nwg-look (GTK theme settings) |
| `Super+l` | Lock screen |

## Window control

| Keys | Action |
|---|---|
| `Alt+Shift+q` | Close focused window |
| `Alt+f` | Toggle fullscreen |
| `Alt+Shift+Space` | Toggle floating |
| `Alt+a` | Focus parent container (for nested layouts) |

## Focus within a workspace

| Keys | Action |
|---|---|
| `Alt+Tab` | Focus right |
| `Alt+Shift+Tab` | Focus left |
| `Alt+Up` | Focus up |
| `Alt+Down` | Focus down |

## Move windows within a workspace

| Keys | Action |
|---|---|
| `Alt+Shift+Left/Right/Up/Down` | Move focused window in that direction |

## Splits and layouts

| Keys | Action |
|---|---|
| `Alt+h` | Set split direction to horizontal (next window opens to the right) |
| `Alt+v` | Set split direction to vertical (next window opens below) |
| `Alt+e` | Toggle between horizontal and vertical split layout |
| `Alt+w` | Switch container to **tabbed** layout |
| `Alt+s` | Switch container to **stacking** layout |

## Resize mode

| Keys | Action |
|---|---|
| `Alt+r` | Enter resize mode |
| `h/j/k/l` or arrows (in mode) | Shrink/grow width and height |
| `Enter` / `Esc` / `Alt+r` | Exit resize mode |

## Workspaces (within current output)

| Keys | Action |
|---|---|
| `Alt+1` … `Alt+0` | Switch to workspace 1–10 (jumps to its monitor if elsewhere) |
| `Alt+Shift+1` … `Alt+Shift+0` | Move focused window to workspace 1–10 |
| `Alt+Ctrl+Tab` | Cycle to next workspace **on this monitor** |
| `Alt+Ctrl+Shift+Tab` | Cycle to previous workspace **on this monitor** |
| `Alt+Ctrl+Shift+Right` | Move window to next workspace on this monitor and follow it |
| `Alt+Ctrl+Shift+Left` | Move window to previous workspace on this monitor and follow it |

## Multi-monitor

Mnemonic: **Super = between-monitor operations**, **Alt = within the workspace**. Monitors are *cycled* by physical position (top-left → top-right → laptop, wrapping around) via `~/.config/sway/scripts/monitor-nav.sh`. Left = previous, Right = next.

| Keys | Action |
|---|---|
| `Super+Left` / `Super+Right` | Focus previous / next monitor (cycles, wraps) |
| `Super+Shift+Left` / `Super+Shift+Right` | Send focused window to previous / next monitor |
| `Super+Ctrl+Left` / `Super+Ctrl+Right` | Move entire workspace to previous / next monitor |

> Cycling (via the helper script) is used instead of Sway's built-in directional `focus output left/right/up/down`, because directional focus silently no-ops when monitors overlap or are fractionally scaled — which yours are. Up/Down are intentionally unbound.

## Display arrangement (important gotcha)

Monitor positions/scale live in the `output …` lines near the top of `~/.config/sway/config`. **wdisplays changes alone do NOT persist** — on every reload Sway resets any output without explicit config back to defaults. So after rearranging in wdisplays, capture the new layout into the config *before* reloading:

```bash
swaymsg -t get_outputs | jq -r '.[] | "output \(.name) position \(.rect.x) \(.rect.y) scale \(.scale)"'
```

Paste the output over the existing `output …` lines, then reload.

## System / config

| Keys | Action |
|---|---|
| `Alt+Shift+c` | Reload Sway config |
| `Alt+Shift+r` | Reload Sway config (alternate) |
| `Alt+Shift+e` | Exit Sway prompt (swaynag) |

## Screenshots

| Keys | Action |
|---|---|
| `PrintScreen` *or* `Super+p` | Full screen → `~/Pictures/Screenshots/` |
| `Shift+PrintScreen` *or* `Super+Shift+p` | Region (drag with `slurp`) |
| `Ctrl+PrintScreen` *or* `Super+Ctrl+p` | Focused window only |

## Media keys (laptop function row)

| Keys | Action |
|---|---|
| `XF86AudioRaiseVolume` / `Lower` / `Mute` | Volume via `volume.sh` script |
| `XF86AudioMicMute` | Mic mute |
| `XF86MonBrightnessUp` / `Down` | Brightness via `brightnessctl` (±10%) |

---

## Useful CLI commands

```bash
swaymsg reload                                  # reload config
swaymsg -t get_outputs                          # list monitors and positions
swaymsg -t get_workspaces                       # list workspaces and which output owns them
swaymsg -t get_tree                             # full window/container tree (JSON)
swaymsg "workspace 5"                           # programmatically switch workspace
swaymsg "[app_id=firefox] focus"                # focus a window by app_id
wlr-randr                                       # CLI monitor config (alternative to wdisplays)
wdisplays                                       # GUI monitor arrangement (doesn't persist — copy into config)
```

---

## Tiling vocabulary (quick reference)

- **Container**: any node in the tree. A window is a leaf container; a split/tabbed group is a parent container.
- **Split layout**: children laid out side-by-side (`split h`) or stacked (`split v`). Default.
- **Tabbed layout**: children share the same space; tabs at the top let you switch.
- **Stacking layout**: like tabbed but title bars stack vertically.
- **Split direction**: when you press `Alt+h` or `Alt+v`, you're telling Sway *where the next new window should appear*, not splitting an existing window.
- **Focus parent** (`Alt+a`): selects the container holding the current window, so subsequent commands (layout changes, moves, resizes) act on the group rather than just one window.

---

## Notes

- The waybar workspace indicator on each monitor only shows workspaces living on *that* monitor (`"all-outputs": false` in `~/.config/waybar/config-top`).
- Workspaces have global numeric identities — workspace 5 is unique across all monitors. Cycling, however, is scoped per-monitor (`next_on_output` / `prev_on_output`).
- DisplayLink dock (Wavlink) requires `displaylink` + `evdi-dkms` from AUR; sway sees its monitors as virtual DRM outputs.
- If you ever add a Rofi workspace picker, save it in `~/.config/sway/scripts/` and bind to something like `Alt+grave`.
