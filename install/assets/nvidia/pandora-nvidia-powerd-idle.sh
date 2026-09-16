#!/usr/bin/env bash
# Pandora: stop nvidia-powerd once every NVIDIA display function is suspended.
# Keeps Dynamic Boost available during prime-run work without holding RTD3 off idle.
set -euo pipefail

if ! systemctl is-active --quiet nvidia-powerd.service 2>/dev/null; then
  exit 0
fi

any_active=0
for dev in /sys/bus/pci/devices/*; do
  [[ -r "$dev/vendor" && -r "$dev/class" ]] || continue
  [[ "$(cat "$dev/vendor")" == "0x10de" ]] || continue
  class="$(cat "$dev/class")"
  # VGA (0300), 3D (0302), display (0380)
  [[ "$class" == 0x030000 || "$class" == 0x030200 || "$class" == 0x038000 ]] || continue
  status="$(cat "$dev/power/runtime_status" 2>/dev/null || echo unsupported)"
  if [[ "$status" != "suspended" && "$status" != "suspending" ]]; then
    any_active=1
    break
  fi
done

if ((any_active == 0)); then
  /usr/bin/systemctl stop nvidia-powerd.service 2>/dev/null || true
fi
