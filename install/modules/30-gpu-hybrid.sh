#!/usr/bin/env bash
# 30 — NVIDIA open-dkms + hybrid (EnvyControl) + GameMode + OBS NVIDIA hints
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user

log "Stack GPU híbrida (iGPU desktop / dGPU offload)"

pac_install \
  nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings \
  nvidia-prime egl-wayland libva-nvidia-driver \
  opencl-nvidia lib32-opencl-nvidia \
  mesa lib32-mesa vulkan-intel vulkan-icd-loader lib32-vulkan-icd-loader
pac_install egl-wayland2 || true

# Kernel modeset for Wayland
gpu_config_changed=0
nvidia_content=$'options nvidia_drm modeset=1 fbdev=1\noptions nvidia NVreg_PreserveVideoMemoryAllocations=1\n'
cmp -s /etc/modprobe.d/nvidia.conf <(printf '%s\n' "$nvidia_content") || gpu_config_changed=1
write_if_changed /etc/modprobe.d/nvidia.conf \
$'options nvidia_drm modeset=1 fbdev=1\noptions nvidia NVreg_PreserveVideoMemoryAllocations=1\n'

# Hybrid Acer/Predator etc.: nvidia_wmi_ec_backlight claims the panel but often does
# not control brightness when the compositor runs on Intel. Prefer intel_backlight.
write_if_changed /etc/modprobe.d/blacklist-nvidia-wmi-ec-backlight.conf \
$'# Pandora: force i915 intel_backlight on hybrid iGPU sessions\nblacklist nvidia_wmi_ec_backlight\n'
ensure_kernel_cmdline_param "acpi_backlight=native"
# UKI/cmdline change may already have rebuilt; keep nvidia MODULES rebuild below.

# mkinitcpio: early load helpful on hybrid laptops
if [[ -f /etc/mkinitcpio.conf ]]; then
  if grep -qE '^MODULES=' /etc/mkinitcpio.conf; then
    if ! grep -qE 'nvidia_drm' /etc/mkinitcpio.conf; then
      backup_file /etc/mkinitcpio.conf
      gpu_config_changed=1
      sed -i 's/^MODULES=(/MODULES=(i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
    fi
  fi
  if ((gpu_config_changed == 0)); then
    already_ok
  elif pkg_installed linux-zen; then
    mkinitcpio -p linux-zen || warn "mkinitcpio linux-zen falhou (DKMS pode completar no próximo boot)"
  else
    mkinitcpio -P || true
  fi
fi

install_prefer envycontrol || die "envycontrol é necessário para hybrid"
if command -v envycontrol >/dev/null; then
  if [[ "$(envycontrol --query 2>/dev/null)" == hybrid ]]; then
    already_ok
  else
  log "EnvyControl → hybrid"
  envycontrol -s hybrid || envycontrol -s hybrid --force || warn "envycontrol hybrid falhou (talvez já esteja)"
  fi
else
  warn "envycontrol não encontrado no PATH após install"
fi

# GameMode: só instalar (user configura depois)
pac_install gamemode lib32-gamemode

# OBS + wrapper NVIDIA
pac_install obs-studio
install_if_changed 755 /dev/stdin /usr/local/bin/obs-nvidia <<'EOF'
#!/usr/bin/env bash
# OBS via NVIDIA offload (NVENC / encoding na dGPU)
exec prime-run obs "$@"
EOF
install_if_changed 644 "$INSTALL_ROOT/assets/obs-nvidia.desktop" \
  /usr/share/applications/obs-nvidia.desktop

obs_dir="$REAL_HOME/.config/obs-studio"
as_user mkdir -p "$obs_dir"
hint="$obs_dir/pandora-nvidia-hint.txt"
install_if_changed 644 /dev/stdin "$hint" <<'EOF'
Pandora / Noctalia — OBS + NVIDIA
=================================
1. Abra "OBS Studio (NVIDIA)" (prime-run) ou: obs-nvidia
2. Settings → Output → Video Encoder: NVIDIA NVENC H.264 (ou HEVC)
3. Rate Control: CBR; bitrate conforme upload
4. GPU: 0 (dGPU). Se não aparecer NVENC, confirme:
   - envycontrol hybrid/nvidia
   - nvidia-open-dkms + nvidia-utils
   - prime-run / __NV_PRIME_RENDER_OFFLOAD=1
EOF
chown "$REAL_UID:$REAL_GID" "$hint"

pac_install mangohud lib32-mangohud goverlay

install_if_changed 755 /dev/stdin /usr/local/bin/prime-env <<'EOF'
#!/usr/bin/env bash
export __NV_PRIME_RENDER_OFFLOAD=1
export __VK_LAYER_NV_optimus=NVIDIA_only
export __GLX_VENDOR_LIBRARY_NAME=nvidia
exec "$@"
EOF

ok "GPU hybrid + GameMode + OBS NVIDIA wrappers prontos"
warn "Reinício recomendado após EnvyControl/DKMS para módulos nvidia no zen"
