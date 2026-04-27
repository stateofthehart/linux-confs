#!/usr/bin/env bash
set -euo pipefail

# Media player control for waybar using playerctl
# Works with Spotify, Firefox, Chromium, VLC, and other MPRIS players

# Check if any player is running
if ! playerctl status &>/dev/null; then
    echo ""
    exit 0
fi

# Get player status
status=$(playerctl status 2>/dev/null || echo "Stopped")

# Get metadata
artist=$(playerctl metadata artist 2>/dev/null || echo "")
title=$(playerctl metadata title 2>/dev/null || echo "")

# Truncate long strings
if [[ ${#artist} -gt 15 ]]; then
    artist="${artist:0:12}..."
fi

if [[ ${#title} -gt 20 ]]; then
    title="${title:0:17}..."
fi

# Build display text with buttons
if [[ -n "$artist" && -n "$title" ]]; then
    text="◀ ⏸ ▶ $artist - $title"
elif [[ -n "$title" ]]; then
    text="◀ ⏸ ▶ $title"
else
    text="◀ ⏸ ▶"
fi

echo "$text"
