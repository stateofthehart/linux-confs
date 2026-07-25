#!/bin/bash
# Bluetooth A2DP watchdog
#
# Monitors bluetooth headphone connections and ensures they use A2DP
# (high-quality stereo) instead of HSP/HFP (low-quality mono).
#
# When headphones connect on HFP, this script:
#   1. Waits for A2DP profiles to appear (sometimes just slow)
#   2. If available, switches to the best A2DP profile
#   3. If not, performs one controlled reconnect cycle
#   4. If still no A2DP, notifies the user and enters a 5-minute cooldown
#
# Runs as a systemd user service.

LOG_TAG="bt-a2dp-watchdog"
STATE_DIR="/tmp/bt-a2dp-watchdog"
SETTLE_DELAY=6
COOLDOWN=300  # 5 minutes before retrying a failed device

log() { logger -t "$LOG_TAG" "$1"; }

# Check if a device is in cooldown (recently failed, don't retry yet)
in_cooldown() {
    local coolfile="$STATE_DIR/$1.cooldown"
    [[ -f "$coolfile" ]] || return 1
    local age=$(( $(date +%s) - $(stat -c %Y "$coolfile" 2>/dev/null || echo 0) ))
    (( age < COOLDOWN ))
}

set_cooldown() {
    mkdir -p "$STATE_DIR" 2>/dev/null
    touch "$STATE_DIR/$1.cooldown"
}

clear_cooldown() { rm -f "$STATE_DIR/$1.cooldown" 2>/dev/null; }

# Acquire a per-device lock to prevent parallel fix attempts
acquire_lock() {
    mkdir -p "$STATE_DIR" 2>/dev/null
    local lockfile="$STATE_DIR/$1.lock"
    if [[ -f "$lockfile" ]]; then
        local age=$(( $(date +%s) - $(stat -c %Y "$lockfile" 2>/dev/null || echo 0) ))
        # Stale lock (>90s)
        (( age > 90 )) && rm -f "$lockfile" || return 1
    fi
    touch "$lockfile"
}

release_lock() { rm -f "$STATE_DIR/$1.lock" 2>/dev/null; }

pw_device_info() {
    local card="$1"
    pw-dump 2>/dev/null | python3 -c "
import json, sys
card = '${card}'
data = json.load(sys.stdin)
for obj in data:
    p = obj.get('info', {}).get('props', {})
    if p.get('device.name') == card:
        params = obj.get('info', {}).get('params', {})
        active = ''
        a2dp_profiles = []
        for pr in params.get('Profile', []):
            active = pr.get('name', '')
        for pr in params.get('EnumProfile', []):
            n = pr.get('name', '')
            if 'a2dp-sink' in n and pr.get('available') == 'yes':
                a2dp_profiles.append((pr.get('priority', 0), pr.get('index'), n))
        a2dp_profiles.sort(reverse=True)
        best_idx = a2dp_profiles[0][1] if a2dp_profiles else ''
        best_name = a2dp_profiles[0][2] if a2dp_profiles else ''
        print(f'{obj[\"id\"]}|{active}|{best_idx}|{best_name}')
        break
" 2>/dev/null
}

fix_device() {
    local bt_addr="$1"
    local lock_key="${bt_addr//:/_}"
    local dev_path="/org/bluez/hci0/dev_${bt_addr//:/_}"
    local card="bluez_card.${bt_addr//:/_}"

    # Skip if in cooldown from a recent failure
    if in_cooldown "$lock_key"; then
        return
    fi

    acquire_lock "$lock_key" || return

    log "Headphones $bt_addr on HFP — checking for A2DP..."

    # Phase 1: Wait and check if A2DP profiles appear (sometimes just slow)
    for i in 1 2 3; do
        sleep 2
        local info=$(pw_device_info "$card")
        local pw_id=$(echo "$info" | cut -d'|' -f1)
        local active=$(echo "$info" | cut -d'|' -f2)
        local a2dp_idx=$(echo "$info" | cut -d'|' -f3)
        local a2dp_name=$(echo "$info" | cut -d'|' -f4)

        if [[ -n "$a2dp_idx" ]]; then
            log "A2DP profile '$a2dp_name' available, switching..."
            wpctl set-profile "$pw_id" "$a2dp_idx" 2>/dev/null
            sleep 2
            info=$(pw_device_info "$card")
            active=$(echo "$info" | cut -d'|' -f2)
            if [[ "$active" == *"a2dp"* ]]; then
                log "Switched to A2DP ($active) successfully!"
                clear_cooldown "$lock_key"
                release_lock "$lock_key"
                return
            fi
        fi
    done

    # Phase 2: One controlled reconnect
    log "No A2DP available, trying one reconnect cycle..."
    dbus-send --system --print-reply --dest=org.bluez "$dev_path" \
        org.bluez.Device1.Disconnect &>/dev/null
    sleep 4
    dbus-send --system --print-reply --dest=org.bluez "$dev_path" \
        org.bluez.Device1.Connect &>/dev/null
    sleep $SETTLE_DELAY

    info=$(pw_device_info "$card")
    a2dp_idx=$(echo "$info" | cut -d'|' -f3)
    a2dp_name=$(echo "$info" | cut -d'|' -f4)
    pw_id=$(echo "$info" | cut -d'|' -f1)

    if [[ -n "$a2dp_idx" ]]; then
        log "A2DP profile '$a2dp_name' available after reconnect, switching..."
        wpctl set-profile "$pw_id" "$a2dp_idx" 2>/dev/null
        sleep 2
        info=$(pw_device_info "$card")
        active=$(echo "$info" | cut -d'|' -f2)
        if [[ "$active" == *"a2dp"* ]]; then
            log "Switched to A2DP ($active) after reconnect!"
            clear_cooldown "$lock_key"
            release_lock "$lock_key"
            return
        fi
    fi

    # Phase 3: Give up, set cooldown, notify user
    log "A2DP unavailable — entering ${COOLDOWN}s cooldown for $bt_addr"
    set_cooldown "$lock_key"
    notify-send -u normal -i bluetooth \
        "Bluetooth: HFP mode (low quality)" \
        "Headphones connected in phone-call mode. Power-cycle them (off/on) for high-quality A2DP audio." \
        2>/dev/null

    release_lock "$lock_key"
}

check_all_bt_devices() {
    while IFS= read -r dev_path; do
        [[ -z "$dev_path" ]] && continue
        local bt_addr="${dev_path##*/dev_}"
        bt_addr="${bt_addr//_/:}"
        local card="bluez_card.${dev_path##*/dev_}"

        local info=$(pw_device_info "$card")
        [[ -z "$info" ]] && continue
        local active=$(echo "$info" | cut -d'|' -f2)

        if [[ "$active" == *"a2dp"* ]]; then
            # Already on A2DP — clear any cooldown so future HFP detections are handled
            local lock_key="${bt_addr//:/_}"
            clear_cooldown "$lock_key"
        elif [[ "$active" == "headset-head-unit"* || "$active" == "audio-gateway"* ]]; then
            fix_device "$bt_addr" &
        fi
    done < <(dbus-send --system --print-reply --dest=org.bluez / \
        org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null | \
        grep 'object path "/org/bluez/hci0/dev_' | \
        sed 's/.*"\(.*\)".*/\1/' | sort -u)
}

log "Starting bluetooth A2DP watchdog..."

# Clean up stale state
rm -rf "$STATE_DIR" 2>/dev/null

# Check existing connections on startup
sleep 3
check_all_bt_devices

# Monitor for new connections — debounce with a coalescing loop
last_check=0
dbus-monitor --system "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Device1'" 2>/dev/null | \
while read -r line; do
    now=$(date +%s)
    if (( now - last_check >= SETTLE_DELAY )); then
        last_check=$now
        sleep $SETTLE_DELAY
        check_all_bt_devices
    fi
done
