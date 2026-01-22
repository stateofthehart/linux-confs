#!/usr/bin/env bash
set -euo pipefail

# Shows all non-loopback IPv4 addresses, grouped by interface
# Example output: "IPs: eth0=192.168.1.10  tailscale0=100.64.0.2"
ips=$(ip -o -4 addr show up primary scope global | awk '{print $2"="$4}' | sed 's|/.*||' | paste -sd' ' -)

if [[ -z "${ips}" ]]; then
  echo "IPs: none"
else
  echo "IPs: ${ips}"
fi

