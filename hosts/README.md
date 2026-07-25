# hosts/ — per-host configuration

Anything that is true for one machine but wrong for another lives here, keyed
by short hostname (`hostname -s`). `install.sh` links `hosts/$(hostname -s)/`
content if the directory exists; hosts without a directory just skip this step.

| Path | Installs to | Why per-host |
|---|---|---|
| `<host>/kanshi/config` | `~/.config/kanshi/config` | Monitor topology (connector names, positions, scales) is unique per machine. Only laptops/docks need kanshi at all. |
| `<host>/sway-outputs.conf` | `~/.config/sway/config.d/outputs.conf` | Static `output` lines for machines with fixed monitors (desktops). Mutually exclusive with kanshi. |

Current hosts:

- **wraith** — laptop (eDP-1 + DisplayLink dock with two identical-EDID XEC
  externals). Uses kanshi with docked/docked-swapped/undocked profiles;
  `sway/scripts/output-catchall.sh` is the failsafe for unmatched combos.
- **phantom** — desktop (Ubuntu 24.04, sway 1.9, DisplayLink/evdi with a
  patched-wlroots wrapper). Uses static outputs; see the warnings inside
  `phantom/sway-outputs.conf`. Full porting notes: `../PORTING.md`.
