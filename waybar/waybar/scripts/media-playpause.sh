#!/usr/bin/env bash
# Dynamic play/pause icon - uses same style icons without background

# Try playerctld first, then spotify, then any player
status=$(playerctl -p playerctld status 2>/dev/null || playerctl -p spotify status 2>/dev/null || playerctl status 2>/dev/null || echo "Stopped")

if echo "$status" | grep -qi "playing"; then
    # Pause icon - similar style to play icon (no background)
    echo "󰏤"
else
    # Play icon
    echo "󰐊"
fi
