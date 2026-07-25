#!/bin/bash
# output-catchall.sh — failsafe so an unmatched monitor combo never stacks at 0,0.
#
# kanshi only arranges displays when the connected set matches one of its
# profiles. For any combo it doesn't cover, sway drops the new output at 0,0,
# overlapping the others -> "mirror mode" that eats input. This watches for that
# exact signature (two active outputs physically overlapping) and, only then,
# spreads all active outputs left-to-right by name. If nothing overlaps — kanshi
# arranged them, or it's a single screen — it does nothing, so it never
# overrides an intentional kanshi layout (e.g. `docked`, laptop below externals).

arrange_if_overlapping() {
    local data
    data=$(swaymsg -t get_outputs | jq -c \
        '[.[] | select(.active) | {name, x:.rect.x, y:.rect.y, w:.rect.width, h:.rect.height}]')

    # Strict overlap test between any pair of active outputs (touching != overlap).
    local overlap
    overlap=$(jq -r '
        def pairs: [range(0;length) as $i | range($i+1;length) as $j | [.[$i],.[$j]]];
        [ pairs[] | .[0] as $a | .[1] as $b |
          if   ($a.x < $b.x + $b.w) and ($b.x < $a.x + $a.w)
           and ($a.y < $b.y + $b.h) and ($b.y < $a.y + $a.h)
          then 1 else empty end ] | length' <<<"$data")

    [ "${overlap:-0}" -gt 0 ] || return 0

    # Spread active outputs left-to-right, sorted by name, preserving mode/scale.
    # (Repositioning emits more output events; the next pass finds no overlap and
    # no-ops, so there's no loop.)
    local x=0 name w
    while IFS=$'\t' read -r name w; do
        swaymsg "output $name position $x 0" >/dev/null
        x=$(( x + w ))
    done < <(jq -r 'sort_by(.name)[] | "\(.name)\t\(.w)"' <<<"$data")
}

case "$1" in
    --listen)
        # Singleton via flock: on sway reload a fresh instance starts but bails
        # here because the running one still holds the lock. Avoids the pkill -f
        # self-match footgun (that pattern appears in the launcher's own argv).
        exec 9>"${XDG_RUNTIME_DIR:-/tmp}/output-catchall.lock"
        flock -n 9 || exit 0
        # React to every output hotplug, after a beat so kanshi acts first.
        swaymsg -t subscribe -m '["output"]' | while read -r _; do
            sleep 0.8
            arrange_if_overlapping
        done
        ;;
    *)
        arrange_if_overlapping
        ;;
esac
