#!/bin/bash
# Swaylock wrapper with proper configuration

# Refuse to start a second swaylock (dueling input grabs -> frozen lock screen)
pgrep -x swaylock >/dev/null && exit 0

# Check if any screens are active
if [ -z "$(swaymsg -t get_outputs | grep '"active": true')" ]; then
    exit 0
fi

# Lock the screen with our config
swaylock --config ~/.config/swaylock/config "$@"
