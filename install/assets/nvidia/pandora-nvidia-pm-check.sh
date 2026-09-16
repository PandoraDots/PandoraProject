#!/usr/bin/env bash
# Pandora: one-shot after first boot — verify NVIDIA RTD3 hooks, then disable self.
set -euo pipefail

log() { printf '[pandora-nvidia-pm-check] %s\n' "$*"; }

ok=1

bl=/etc/modprobe.d/blacklist-nvidia-wmi-ec-backlight.conf
if [[ -f "$bl" ]] && grep -qx 'blacklist nvidia_wmi_ec_backlight' "$bl"; then
  log "blacklist nvidia_wmi_ec_backlight: ok"
else
  log "blacklist nvidia_wmi_ec_backlight: missing or malformed"
  ok=0
fi

nvidia_vga=""
for dev in /sys/bus/pci/devices/*; do
  [[ -r "$dev/vendor" && -r "$dev/class" ]] || continue
  [[ "$(cat "$dev/vendor")" == "0x10de" ]] || continue
  [[ "$(cat "$dev/class")" == "0x030000" ]] || continue
  nvidia_vga="$dev"
  break
done

if [[ -n "$nvidia_vga" ]]; then
  control="$(cat "$nvidia_vga/power/control" 2>/dev/null || echo missing)"
  status="$(cat "$nvidia_vga/power/runtime_status" 2>/dev/null || echo missing)"
  log "NVIDIA VGA control=$control runtime_status=$status"
  [[ "$control" == "auto" ]] || ok=0
else
  log "NVIDIA VGA not found in sysfs"
  ok=0
fi

shopt -s nullglob
for powerf in /proc/driver/nvidia/gpus/*/power; do
  if grep -q 'Runtime D3 status:[[:space:]]*Enabled' "$powerf" 2>/dev/null; then
    log "Runtime D3 Enabled: ok"
  else
    log "Runtime D3 not Enabled (may need reboot after NVreg change)"
    ok=0
  fi
  break
done
shopt -u nullglob

if command -v envycontrol >/dev/null && [[ "$(envycontrol --query 2>/dev/null)" == hybrid ]]; then
  log "envycontrol hybrid: ok"
else
  log "envycontrol not hybrid (warn only)"
fi

if ((ok == 1)); then
  log "all checks passed — disabling this oneshot"
else
  log "some checks failed — disabling oneshot anyway; re-run install module 30 if needed"
fi

systemctl disable pandora-nvidia-pm-check.service 2>/dev/null || true
exit 0
