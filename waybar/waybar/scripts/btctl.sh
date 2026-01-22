#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-status}"

have_controller() {
  bluetoothctl list 2>/dev/null | grep -q "^Controller"
}

power_state() {
  bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/{print $2; exit}'
}

paired_macs() {
  bluetoothctl paired-devices 2>/dev/null | awk '{print $2}'
}

device_name() {
  local mac="$1"
  bluetoothctl info "$mac" 2>/dev/null | awk -F': ' '/Name:/{print $2; exit}'
}

device_connected() {
  local mac="$1"
  bluetoothctl info "$mac" 2>/dev/null | awk -F': ' '/Connected:/{print $2; exit}'
}

connected_devices() {
  paired_macs | while read -r mac; do
    [[ -n "$mac" ]] || continue
    if [[ "$(device_connected "$mac")" == "yes" ]]; then
      printf "%s\t%s\n" "$mac" "$(device_name "$mac")"
    fi
  done
}

status_line() {
  if ! have_controller; then
    echo "BT: none"
    return
  fi

  local p
  p="$(power_state)"
  if [[ "$p" != "yes" ]]; then
    echo " off"
    return
  fi

  # If something is connected, show its name (first one).
  local first
  first="$(connected_devices | head -n 1 || true)"
  if [[ -n "$first" ]]; then
    local name
    name="$(echo "$first" | cut -f2-)"
    echo " ${name}"
  else
    echo " on"
  fi
}

toggle_power() {
  if ! have_controller; then exit 0; fi
  if [[ "$(power_state)" == "yes" ]]; then
    bluetoothctl power off >/dev/null
  else
    bluetoothctl power on >/dev/null
  fi
}

menu_devices() {
  command -v wofi >/dev/null || { echo "wofi not installed" >&2; exit 1; }

  if ! have_controller; then
    notify-send "Bluetooth" "No controller found."
    exit 1
  fi

  bluetoothctl power on >/dev/null

  # Build paired devices list
  mapfile -t dev_lines < <(
    bluetoothctl paired-devices | sed 's/^Device //' | while read -r mac name_rest; do
      name="${name_rest}"
      conn="$(bluetoothctl info "$mac" 2>/dev/null | awk -F': ' '/Connected:/{print $2; exit}')"
      printf "%s  (%s)  [%s]\n" "$name" "$mac" "${conn:-unknown}"
    done
  )

  # Top-level actions + devices
  choice="$(
    {
      echo "Pair new device…"
      echo "Toggle power"
      echo "—"
      printf '%s\n' "${dev_lines[@]}"
    } | wofi --dmenu -p "Bluetooth"
  )" || exit 0

  case "$choice" in
    "Pair new device…")
      "$0" pair
      exit 0
      ;;
    "Toggle power")
      "$0" toggle
      exit 0
      ;;
    "—"|"")
      exit 0
      ;;
  esac

  # Otherwise, parse MAC and connect/disconnect
  mac="$(echo "$choice" | sed -n 's/.*(\([0-9A-Fa-f:]\+\)).*/\1/p')"
  [[ -n "$mac" ]] || exit 0

  conn="$(bluetoothctl info "$mac" 2>/dev/null | awk -F': ' '/Connected:/{print $2; exit}')"
  if [[ "$conn" == "yes" ]]; then
    bluetoothctl disconnect "$mac" >/dev/null && notify-send "Bluetooth" "Disconnected"
  else
    bluetoothctl connect "$mac" >/dev/null && notify-send "Bluetooth" "Connected"
  fi
}

pair_menu() {
  command -v wofi >/dev/null || { echo "wofi not installed" >&2; exit 1; }

  if ! have_controller; then
    notify-send "Bluetooth" "No controller found."
    exit 1
  fi

  bluetoothctl power on >/dev/null
  bluetoothctl agent on >/dev/null
  bluetoothctl default-agent >/dev/null
  bluetoothctl pairable on >/dev/null
  bluetoothctl discoverable on >/dev/null

  # Start scan in background briefly
  bluetoothctl scan on >/dev/null

  # Give it a moment to populate
  sleep 2

  # Pull discovered devices list
  # NOTE: bluetoothctl doesn't have a perfect "discovered-only" list; `devices` includes seen devices.
  mapfile -t lines < <(
    bluetoothctl devices | sed 's/^Device //' | awk '
      {
        mac=$1; $1="";
        name=substr($0,2);
        print name "  (" mac ")"
      }'
  )

  if [[ ${#lines[@]} -eq 0 ]]; then
    bluetoothctl scan off >/dev/null
    notify-send "Bluetooth" "No devices found (yet). Try again."
    exit 0
  fi

  choice="$(printf '%s\n' "${lines[@]}" | wofi --dmenu -p "Pair device")" || true

  bluetoothctl scan off >/dev/null

  mac="$(echo "${choice:-}" | sed -n 's/.*(\([0-9A-F:]\+\)).*/\1/p')"
  [[ -n "$mac" ]] || exit 0

  # Try pair/trust/connect
  bluetoothctl pair "$mac" >/dev/null || { notify-send "Bluetooth" "Pair failed"; exit 1; }
  bluetoothctl trust "$mac" >/dev/null || true
  bluetoothctl connect "$mac" >/dev/null || true
  notify-send "Bluetooth" "Paired/connected"
}

auto_connect() {
  # Connect to a list of MACs in ~/.config/btctl/favorites (one per line)
  local favfile="${XDG_CONFIG_HOME:-$HOME/.config}/btctl/favorites"
  [[ -f "$favfile" ]] || exit 0

  if ! have_controller; then exit 0; fi
  bluetoothctl power on >/dev/null

  while read -r mac; do
    mac="${mac//[[:space:]]/}"
    [[ -n "$mac" ]] || continue
    [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || continue
    bluetoothctl connect "$mac" >/dev/null || true
  done < "$favfile"
}

case "$cmd" in
  status) status_line ;;
  toggle) toggle_power ;;
  menu)   menu_devices ;;
  pair)   pair_menu ;;
  autoconnect) auto_connect ;;
  *) echo "Usage: btctl {status|toggle|menu|pair|autoconnect}" >&2; exit 2 ;;
esac

