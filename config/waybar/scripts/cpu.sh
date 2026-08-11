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

# Qualcomm/Snapdragon has no single package sensor. It exposes a per-core zone
# grid instead — cpu0-0-top-thermal, cpu0-0-btm-thermal, ... cpu1-3-btm-thermal,
# plus cpuss0/cpuss1 subsystem zones (~40 zones total on x1p42100). There is no
# k10temp/coretemp equivalent, which is why this read "?" before.
# Report the HOTTEST core zone: that's what actually governs throttling.
QCOM_TEMP=""
if [[ -z "$CPU_TEMP" ]]; then
  for z in /sys/class/thermal/thermal_zone*; do
    case "$(cat "$z/type" 2>/dev/null)" in
      cpu*-thermal|cpuss*-thermal)
        t="$(cat "$z/temp" 2>/dev/null || true)"
        [[ -z "$t" ]] && continue
        if [[ -z "$QCOM_TEMP" ]] || (( t > QCOM_TEMP )); then
          QCOM_TEMP="$t"
        fi
        ;;
    esac
  done
fi

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
if [[ -n "$CPU_TEMP" && -r "$CPU_TEMP" ]]; then
  temp_c=$(( $(cat "$CPU_TEMP") / 1000 ))
elif [[ -n "$QCOM_TEMP" ]]; then
  temp_c=$(( QCOM_TEMP / 1000 ))
fi

echo "CPU ${usage}% ${temp_c}°C"

