#!/usr/bin/env bash
set -euo pipefail

# Bluetooth status script for waybar
# Uses dbus directly instead of bluetoothctl, which has connection
# timing issues in non-interactive mode (bluez 5.86+).

ADAPTER="/org/bluez/hci0"
DEST="org.bluez"

get_prop() {
    dbus-send --system --print-reply --dest="$DEST" "$1" \
        org.freedesktop.DBus.Properties.Get string:"$2" string:"$3" 2>/dev/null
}

# Check if bluetooth adapter is powered on
powered=$(get_prop "$ADAPTER" "org.bluez.Adapter1" "Powered" | grep "boolean" | awk '{print $3}')

if [[ "$powered" != "true" ]]; then
    echo "{\"text\": \"󰂲 Off\", \"class\": \"off\", \"alt\": \"off\"}"
    exit 0
fi

# Find connected devices by enumerating bluez objects
connected_device=""
while IFS= read -r obj_path; do
    [[ "$obj_path" == */dev_* ]] || continue
    connected=$(get_prop "$obj_path" "org.bluez.Device1" "Connected" | grep "boolean" | awk '{print $3}')
    if [[ "$connected" == "true" ]]; then
        device_name=$(get_prop "$obj_path" "org.bluez.Device1" "Alias" | grep 'string "' | tail -1 | sed 's/.*string "//;s/"//')
        connected_device="$device_name"
        break
    fi
done < <(dbus-send --system --print-reply --dest="$DEST" / \
    org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null | \
    grep 'object path "/org/bluez/hci0/dev_' | sed 's/.*"\(.*\)".*/\1/' | sort -u)

if [[ -n "$connected_device" ]]; then
    # Truncate long names
    if [[ ${#connected_device} -gt 15 ]]; then
        connected_device="${connected_device:0:12}..."
    fi
    echo "{\"text\": \"󰂱 $connected_device\", \"class\": \"connected\", \"alt\": \"connected\"}"
else
    echo "{\"text\": \"󰂯 On\", \"class\": \"on\", \"alt\": \"on\"}"
fi
