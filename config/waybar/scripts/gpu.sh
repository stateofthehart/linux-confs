#!/usr/bin/env bash
set -euo pipefail

# GPU stats for waybar. Sensors are resolved by NAME, never by hwmonN /
# thermal_zoneN index — those shift between machines and across boots.
#
# Three backends, tried in order:
#   1. amdgpu       hwmon "amdgpu" temp + gpu_busy_percent   (wraith, phantom)
#   2. Adreno/msm   devfreq clock + gpuss-*-thermal zones    (specter, Snapdragon)
#   3. neither      prints "?" rather than failing
#
# NOTE on the Adreno path: the msm driver exposes no gpu_busy_percent, so there
# is no true utilization figure to read. We report the current core CLOCK in MHz
# instead of a fake percentage — devfreq's governor scales frequency with load,
# so it moves with GPU activity, but it is a clock reading and is labelled as
# such. Idle sits at min_freq (280 MHz on x1p42100); max is 1107 MHz.

util="?"
unit=""
temp_c="?"

# ---------------------------------------------------------------- amdgpu ---
for h in /sys/class/hwmon/hwmon*; do
  if [[ "$(cat "$h/name" 2>/dev/null)" == "amdgpu" ]]; then
    [[ -r "$h/temp1_input" ]] && temp_c=$(( $(cat "$h/temp1_input") / 1000 ))
    break   # temp1 = edge (millidegC)
  fi
done

busy_path="$(ls /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -n1 || true)"
if [[ -n "${busy_path}" && -r "${busy_path}" ]]; then
  util="$(tr -d '[:space:]' < "${busy_path}")"
  unit="%"
elif command -v amdgpu_top >/dev/null 2>&1; then
  # Optional amdgpu fallback when gpu_busy_percent is absent.
  parsed="$(
    amdgpu_top -J -n 1 2>/dev/null \
    | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

def find_number(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            lk = str(k).lower()
            if lk in ("gpu_usage", "gpu_busy", "gpu_busy_percent", "gpu_util", "utilization") and isinstance(v, (int, float)):
                return v
            r = find_number(v)
            if r is not None: return r
    elif isinstance(obj, list):
        for it in obj:
            r = find_number(it)
            if r is not None: return r
    return None

v = find_number(data)
if v is not None:
    print(int(round(v)))
PY
  )" || parsed=""
  if [[ -n "${parsed}" ]]; then
    util="${parsed}"
    unit="%"
  fi
fi

# ----------------------------------------------------- Adreno / Qualcomm ---
# Only consulted if the amdgpu path found nothing, so amd hosts are unchanged.
if [[ "${util}" == "?" ]]; then
  devfreq="$(ls -d /sys/class/devfreq/*.gpu 2>/dev/null | head -n1 || true)"
  if [[ -n "${devfreq}" && -r "${devfreq}/cur_freq" ]]; then
    util=$(( $(cat "${devfreq}/cur_freq") / 1000000 ))
    unit="MHz"
  fi
fi

if [[ "${temp_c}" == "?" ]]; then
  # Snapdragon exposes several GPU subsystem zones (gpuss-0..3); report the
  # hottest, which is what you actually care about for throttling.
  hottest=""
  for z in /sys/class/thermal/thermal_zone*; do
    ztype="$(cat "${z}/type" 2>/dev/null || true)"
    case "${ztype}" in
      gpuss-*|*-gpu-*|*gpu*)
        t="$(cat "${z}/temp" 2>/dev/null || true)"
        [[ -z "${t}" ]] && continue
        if [[ -z "${hottest}" ]] || (( t > hottest )); then
          hottest="${t}"
        fi
        ;;
    esac
  done
  [[ -n "${hottest}" ]] && temp_c=$(( hottest / 1000 ))
fi

echo "GPU ${util}${unit} ${temp_c}°C"
