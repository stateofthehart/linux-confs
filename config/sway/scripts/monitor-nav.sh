#!/usr/bin/env bash
# Cycle monitor focus, or move the focused window/workspace between monitors,
# ordered by physical position (top row left->right, then down).
#
# Sway's directional `focus output left/right/...` is unreliable when outputs
# overlap or are fractionally scaled, and `focus output next` isn't valid syntax.
# Name-based focus (`focus output <name>`) always works, so we resolve the target
# name ourselves from live output geometry.
#
# Usage: monitor-nav.sh <focus|move-window|move-workspace> <next|prev>
set -euo pipefail

action="${1:-focus}"
dir="${2:-next}"

# Output names ordered by position: row first (y), then left-to-right (x).
mapfile -t outs < <(swaymsg -t get_outputs | jq -r 'sort_by(.rect.y, .rect.x) | .[].name')
cur=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused).name')
n=${#outs[@]}
(( n < 2 )) && exit 0   # single monitor: nothing to do

# Index of the currently focused output.
idx=0
for i in "${!outs[@]}"; do
  [[ "${outs[$i]}" == "$cur" ]] && { idx=$i; break; }
done

if [[ "$dir" == prev ]]; then
  target="${outs[$(( (idx - 1 + n) % n ))]}"
else
  target="${outs[$(( (idx + 1) % n ))]}"
fi

case "$action" in
  focus)          swaymsg "focus output \"$target\"" ;;
  move-window)    swaymsg "move container to output \"$target\"" ;;
  move-workspace) swaymsg "move workspace to output \"$target\"" ;;
  *) echo "usage: $0 <focus|move-window|move-workspace> <next|prev>" >&2; exit 1 ;;
esac
