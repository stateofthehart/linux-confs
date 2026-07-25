#!/usr/bin/env bash
set -euo pipefail

# GPU temp sensor, resolved by driver name — hwmon indexes differ between
# machines and can shift across boots, so never hardcode hwmonN.
# amdgpu only; an NVIDIA card would need nvidia-smi instead.
GPU_TEMP=""
for h in /sys/class/hwmon/hwmon*; do
  if [[ "$(cat "$h/name" 2>/dev/null)" == "amdgpu" ]]; then
    GPU_TEMP="$h/temp1_input"; break   # temp1 = edge (millidegC)
  fi
done

temp_c="?"
if [[ -r "$GPU_TEMP" ]]; then
  temp_c=$(( $(cat "$GPU_TEMP") / 1000 ))
fi

# GPU util: prefer gpu_busy_percent if available (super cheap + accurate)
util="?"
busy_path="$(ls /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -n1 || true)"
if [[ -n "${busy_path}" && -r "${busy_path}" ]]; then
  util="$(cat "${busy_path}" | tr -d '[:space:]')"
else
  # Fallback: try amdgpu_top JSON if installed
  if command -v amdgpu_top >/dev/null 2>&1; then
    util="$(
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
    )"
    [[ -z "${util}" ]] && util="?"
  fi
fi

echo "GPU ${util}% ${temp_c}°C"

