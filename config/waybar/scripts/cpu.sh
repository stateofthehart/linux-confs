#!/usr/bin/env bash
set -euo pipefail

# CPU temp sensor, resolved by driver name — hwmon indexes differ between
# machines and can shift across boots, so never hardcode hwmonN.
CPU_TEMP=""
for h in /sys/class/hwmon/hwmon*; do
  case "$(cat "$h/name" 2>/dev/null)" in
    k10temp|zenpower|coretemp)   # AMD Tctl / Intel package (millidegC)
      CPU_TEMP="$h/temp1_input"; break ;;
  esac
done

# CPU utilization from /proc/stat delta
read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
prev_total=$((user+nice+system+idle+iowait+irq+softirq+steal))
prev_idle=$((idle+iowait))

sleep 0.2

read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
total=$((user+nice+system+idle+iowait+irq+softirq+steal))
idle_all=$((idle+iowait))

dt=$((total - prev_total))
di=$((idle_all - prev_idle))

usage=0
if (( dt > 0 )); then
  usage=$(( (100 * (dt - di) + dt/2) / dt ))
fi

temp_c="?"
if [[ -r "$CPU_TEMP" ]]; then
  temp_c=$(( $(cat "$CPU_TEMP") / 1000 ))
fi

echo "CPU ${usage}% ${temp_c}°C"

