#!/usr/bin/env bash
set -euo pipefail

# Media player info for waybar
# Uses playerctld to track the most recently active player

# Check if any player is running (try playerctld first, then spotify, then any)
if ! playerctl -p playerctld status &>/dev/null && ! playerctl -p spotify status &>/dev/null && ! playerctl status &>/dev/null; then
    echo ""
    exit 0
fi

# Get metadata (try playerctld first, then spotify, then any)
artist=$(playerctl -p playerctld metadata artist 2>/dev/null || playerctl -p spotify metadata artist 2>/dev/null || playerctl metadata artist 2>/dev/null || echo "")
title=$(playerctl -p playerctld metadata title 2>/dev/null || playerctl -p spotify metadata title 2>/dev/null || playerctl metadata title 2>/dev/null || echo "")

# Truncate long strings
if [[ ${#artist} -gt 12 ]]; then
    artist="${artist:0:9}..."
fi

if [[ ${#title} -gt 18 ]]; then
    title="${title:0:15}..."
fi

# Build display text
if [[ -n "$artist" && -n "$title" ]]; then
    text="$artist - $title"
elif [[ -n "$title" ]]; then
    text="$title"
else
    text=""
fi

echo "$text"
