#!/usr/bin/env bash
set -euo pipefail

# Network speed monitor for waybar
# Shows upload and download speeds

# Find the primary network interface (the one with default route)
get_primary_interface() {
    ip route | grep default | head -1 | awk '{print $5}'
}

# Read bytes from /sys
read_bytes() {
    local iface=$1
    local direction=$2
    
    if [[ -f "/sys/class/net/$iface/statistics/${direction}_bytes" ]]; then
        cat "/sys/class/net/$iface/statistics/${direction}_bytes"
    else
        echo 0
    fi
}

# Convert bytes to human-readable format
human_readable() {
    local bytes=$1
    
    if (( bytes >= 1073741824 )); then
        printf "%.1fG" $((10**9 * bytes / 1073741824))e-9
    elif (( bytes >= 1048576 )); then
        printf "%.1fM" $((10**9 * bytes / 1048576))e-9
    elif (( bytes >= 1024 )); then
        printf "%.1fK" $((10**9 * bytes / 1024))e-9
    else
        printf "%dB" "$bytes"
    fi
}

# Main logic
iface=$(get_primary_interface)

if [[ -z "$iface" ]] || [[ ! -d "/sys/class/net/$iface" ]]; then
    echo "NET --/--"
    exit 0
fi

# Read initial values
rx1=$(read_bytes "$iface" "rx")
tx1=$(read_bytes "$iface" "tx")

# Wait 1 second
sleep 1

# Read final values
rx2=$(read_bytes "$iface" "rx")
tx2=$(read_bytes "$iface" "tx")

# Calculate speeds (bytes per second)
rx_speed=$((rx2 - rx1))
tx_speed=$((tx2 - tx1))

# Format output
down=$(human_readable "$rx_speed")
up=$(human_readable "$tx_speed")

echo "NET ↓${down} ↑${up}"
