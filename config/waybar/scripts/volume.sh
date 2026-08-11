#!/bin/bash
# Volume display/control for waybar using Nerd Font icons
# Caps volume at 100% using -l 1.0
#
# Self-healing: if WirePlumber loses its default audio sink, this script
# auto-recovers by re-setting the default. If that fails, it restarts
# WirePlumber (at most once per 30 seconds to avoid restart loops).

SINK="@DEFAULT_AUDIO_SINK@"
# Recovery sink is host-specific (a PCI-addressed node name). Put yours in
# ~/.config/waybar/fallback-sink (find it with: wpctl status). If the file is
# absent, recovery skips straight to the wireplumber-restart path.
FALLBACK_SINK="$(cat "$HOME/.config/waybar/fallback-sink" 2>/dev/null || true)"
RESTART_COOLDOWN=30

# Check if the default sink is functional. wpctl returns exit 0 even
# when the default-nodes-api is broken, so we must check the output.
sink_is_ok() {
    wpctl get-volume "$SINK" 2>&1 | grep -q "^Volume:"
}

ensure_default_sink() {
    if sink_is_ok; then
        return 0
    fi

    # Phase 1: Try setting the default sink by node ID
    if [[ -n "$FALLBACK_SINK" ]]; then
        local node_id
        node_id=$(pw-cli ls Node 2>/dev/null \
            | grep -B15 "node.name = \"$FALLBACK_SINK\"" \
            | grep "^	id" | awk '{print $2}' | tr -d ',')
        if [[ -n "$node_id" ]]; then
            wpctl set-default "$node_id" &>/dev/null
            if sink_is_ok; then
                return 0
            fi
        fi
    fi

    # Phase 2: Restart WirePlumber (with cooldown to prevent loops)
    local stamp="/tmp/.wireplumber-last-restart"
    local now last=0
    now=$(date +%s)
    [[ -f "$stamp" ]] && last=$(cat "$stamp" 2>/dev/null)
    if (( now - last >= RESTART_COOLDOWN )); then
        echo "$now" > "$stamp"
        systemctl --user restart wireplumber &>/dev/null
        sleep 2
    fi
}

case "${1:-}" in
    up)
        ensure_default_sink
        wpctl set-volume -l 1.0 "$SINK" 5%+ >/dev/null 2>&1
        ;;
    down)
        ensure_default_sink
        wpctl set-volume -l 1.0 "$SINK" 5%- >/dev/null 2>&1
        ;;
    toggle)
        ensure_default_sink
        wpctl set-mute "$SINK" toggle >/dev/null 2>&1
        ;;
    *)
        ensure_default_sink
        output=$(wpctl get-volume "$SINK" 2>/dev/null)

        if ! echo "$output" | grep -q "^Volume:"; then
            echo "󰝟 --"
            exit 0
        fi

        vol=$(echo "$output" | awk '{printf "%.0f", $2 * 100}')

        # NOTE: these four glyphs were silently lost from this file at some
        # point (only the no-sink fallback above kept its icon), leaving every
        # branch echoing a bare space. Both wraith and specter rendered a
        # volume readout with no icon. Keep them as literal UTF-8; do not let
        # an editor or transfer strip them again.
        if echo "$output" | grep -q "MUTED"; then
            echo "󰝟 $vol%"
        elif [[ $vol -gt 50 ]]; then
            echo "󰕾 $vol%"
        elif [[ $vol -gt 0 ]]; then
            echo "󰖀 $vol%"
        else
            echo "󰕿 $vol%"
        fi
        ;;
esac
