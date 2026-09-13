#!/usr/bin/env bash
# Bluetooth status for waybar.
#
# Uses dbus directly instead of bluetoothctl, which has connection timing
# issues in non-interactive mode (bluez 5.86+).
#
# Contract: ALWAYS print exactly one JSON object and exit 0. A custom module
# that exits non-zero or prints nothing is rendered as an empty label, so the
# bar silently loses the module rather than showing a state. That is what used
# to happen on hosts with no Bluetooth controller: `set -e -o pipefail` plus a
# `grep` over empty dbus output killed the script before it could report "off".
#
# States: no controller -> "N/A", controller powered down -> "Off",
#         powered up -> "On", or the name of the connected device.
set -uo pipefail

ADAPTER="/org/bluez/hci0"
DEST="org.bluez"

# Never let a dbus failure abort the script -- absent bluez, an absent adapter
# and a refused call all have to fall through to a printable state.
get_prop() {
    dbus-send --system --print-reply --dest="$DEST" "$1" \
        org.freedesktop.DBus.Properties.Get string:"$2" string:"$3" 2>/dev/null || true
}

emit() { printf '{"text": "%s", "class": "%s", "alt": "%s"}\n' "$1" "$2" "$3"; }

# Read a `variant boolean true` reply without a pipeline that can fail.
prop_bool() { awk '/boolean/ {print $NF; exit}' <<<"${1:-}"; }

powered_reply=$(get_prop "$ADAPTER" "org.bluez.Adapter1" "Powered")

# Empty reply => bluez exports no hci0 at all (no controller on this host, or
# bluetoothd is not running). Distinct from a controller that is switched off.
if [[ -z "$powered_reply" ]]; then
    emit "󰂲 N/A" "unavailable" "unavailable"
    exit 0
fi

if [[ "$(prop_bool "$powered_reply")" != "true" ]]; then
    emit "󰂲 Off" "off" "off"
    exit 0
fi

# Powered on: find the first connected device, if any.
connected_device=""
while IFS= read -r obj_path; do
    [[ "$obj_path" == */dev_* ]] || continue
    if [[ "$(prop_bool "$(get_prop "$obj_path" "org.bluez.Device1" "Connected")")" == "true" ]]; then
        connected_device=$(get_prop "$obj_path" "org.bluez.Device1" "Alias" |
            sed -n 's/.*string "\(.*\)".*/\1/p' | tail -1)
        break
    fi
done < <(dbus-send --system --print-reply --dest="$DEST" / \
    org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null |
    sed -n 's|.*object path "\(/org/bluez/hci0/dev_[^"]*\)".*|\1|p' | sort -u)

if [[ -n "$connected_device" ]]; then
    # Truncate long names so the bar does not reflow.
    if [[ ${#connected_device} -gt 15 ]]; then
        connected_device="${connected_device:0:12}..."
    fi
    emit "󰂱 $connected_device" "connected" "connected"
else
    emit "󰂯 On" "on" "on"
fi
