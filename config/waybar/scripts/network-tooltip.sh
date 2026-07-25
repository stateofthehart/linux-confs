#!/usr/bin/env bash
set -euo pipefail

# Network module with dynamic signal strength icons for waybar

# Get connection info
wifi_info=$(nmcli -t -f active,ssid,signal dev wifi 2>/dev/null | grep '^yes' || true)
ethernet_info=$(nmcli -t -f device,type,state dev show 2>/dev/null | grep -E "ethernet.*connected" || true)

# Get IP addresses
ips=$(ip -o -4 addr show up primary scope global 2>/dev/null | awk '{print $2": "$4}' | sed 's|/.*||' | tr '\n' ' ' | sed 's/ $//')

# Function to get WiFi icon based on signal strength
get_wifi_icon() {
    local signal=$1
    if (( signal >= 80 )); then
        echo "󰤨"  # 5 bars
    elif (( signal >= 60 )); then
        echo "󰤢"  # 4 bars
    elif (( signal >= 40 )); then
        echo "󰤡"  # 3 bars
    elif (( signal >= 20 )); then
        echo "󰤠"  # 2 bars
    elif (( signal > 0 )); then
        echo "󰤟"  # 1 bar
    else
        echo "󰤭"  # No signal
    fi
}

if [[ -n "$wifi_info" ]]; then
    ssid=$(echo "$wifi_info" | cut -d: -f2)
    signal=$(echo "$wifi_info" | cut -d: -f3)
    
    # Get dynamic icon based on signal strength
    icon=$(get_wifi_icon "$signal")
    
    # Build tooltip with IP info
    tooltip="Connected: $ssid\nSignal: $signal%"
    if [[ -n "$ips" ]]; then
        tooltip="$tooltip\n$ips"
    fi
    
    # Include icon directly in text
    echo "{\"text\": \"$icon $ssid\", \"tooltip\": \"$tooltip\", \"class\": \"wifi\", \"alt\": \"wifi\"}"
elif [[ -n "$ethernet_info" ]]; then
    iface=$(echo "$ethernet_info" | head -1 | cut -d: -f1)
    
    tooltip="Ethernet: $iface"
    if [[ -n "$ips" ]]; then
        tooltip="$tooltip\n$ips"
    fi
    
    # Include icon directly in text
    echo "{\"text\": \"󰈀 $iface\", \"tooltip\": \"$tooltip\", \"class\": \"ethernet\", \"alt\": \"ethernet\"}"
else
    echo "{\"text\": \"󰤭 Offline\", \"tooltip\": \"Not connected\", \"class\": \"disconnected\", \"alt\": \"disconnected\"}"
fi
