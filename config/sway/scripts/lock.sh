#!/bin/bash
# Swaylock wrapper with proper configuration

# Check if any screens are active
if [ -z "$(swaymsg -t get_outputs | grep '"active": true')" ]; then
    exit 0
fi

# Lock the screen with our config
swaylock --config ~/.config/swaylock/config "$@"
