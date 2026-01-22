#!/usr/bin/env bash
set -euo pipefail

# Portable POSIX-ish output, one line, stable columns
# df -hP: human readable, POSIX format (no wrapping)
read -r _ _ used avail _ < <(df -hP / | tail -n1)

echo "SSD ${used}/${avail}"

