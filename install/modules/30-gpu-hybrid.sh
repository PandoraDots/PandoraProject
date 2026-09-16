#!/usr/bin/env bash
# 30 — NVIDIA open-dkms + hybrid (EnvyControl) + RTD3 + GameMode + OBS NVIDIA hints
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

# Kernel modeset + RTD3 (dGPU off until prime-run)
gpu_config_changed=0
nvidia_conf_src="$INSTALL_ROOT/assets/nvidia/nvidia.conf"
nvidia_udev_src="$INSTALL_ROOT/assets/nvidia/80-nvidia-pm.rules"
if [[ -f "$nvidia_conf_src" ]]; then
  cmp -s /etc/modprobe.d/nvidia.conf "$nvidia_conf_src" || gpu_config_changed=1
  install_if_changed 644 "$nvidia_conf_src" /etc/modprobe.d/nvidia.conf
else
  nvidia_content=$'options nvidia_drm modeset=1 fbdev=1\noptions nvidia NVreg_DynamicPowerManagement=0x02 NVreg_DynamicPowerManagementVideoMemoryThreshold=512 NVreg_PreserveVideoMemoryAllocations=0\n'
  cmp -s /etc/modprobe.d/nvidia.conf <(printf '%s\n' "$nvidia_content") || gpu_config_changed=1
  write_if_changed /etc/modprobe.d/nvidia.conf "$nvidia_content"
fi
if [[ -f "$nvidia_udev_src" ]]; then
  install_if_changed 644 "$nvidia_udev_src" /etc/udev/rules.d/80-nvidia-pm.rules
else
  install_if_changed 644 /dev/stdin /etc/udev/rules.d/80-nvidia-pm.rules <<'EOF'
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"
EOF
fi

# Apply PCI power/control=auto without waiting for reboot.
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=pci --action=add 2>/dev/null || true
for dev in /sys/bus/pci/devices/*; do
  [[ -r "$dev/vendor" ]] || continue
  [[ "$(cat "$dev/vendor")" == "0x10de" ]] || continue
  if [[ -w "$dev/power/control" ]]; then
    echo auto >"$dev/power/control" 2>/dev/null || true
  fi
done

# Hybrid Acer/Predator etc.: nvidia_wmi_ec_backlight claims the panel but often does
# not control brightness when the compositor runs on Intel. Prefer intel_backlight.
install_if_changed 644 \
  "$INSTALL_ROOT/assets/nvidia/blacklist-nvidia-wmi-ec-backlight.conf" \
  /etc/modprobe.d/blacklist-nvidia-wmi-ec-backlight.conf
ensure_kernel_cmdline_param "acpi_backlight=native"

# Session-wide iGPU defaults (Electron included). prime-run clears these.
install_if_changed 644 \
  "$INSTALL_ROOT/assets/environment.d/90-pandora-igpu.conf" \
  /etc/environment.d/90-pandora-igpu.conf
as_user mkdir -p "$REAL_HOME/.config/environment.d"
install_if_changed 644 \
  "$INSTALL_ROOT/assets/environment.d/90-pandora-igpu.conf" \
  "$REAL_HOME/.config/environment.d/90-pandora-igpu.conf"
chown "$REAL_UID:$REAL_GID" "$REAL_HOME/.config/environment.d/90-pandora-igpu.conf" 2>/dev/null || true

# Umbriel compositor multi-GPU: ensure it can initialize NVIDIA EGL for external monitors
# without being blocked by Mesa-only session variables.
mkdir -p /etc/systemd/user/umbriel.service.d 2>/dev/null || true
install_if_changed 644 \
  "$INSTALL_ROOT/assets/systemd/user/umbriel.service.d/10-gpu.conf" \
  /etc/systemd/user/umbriel.service.d/10-gpu.conf
as_user mkdir -p "$REAL_HOME/.config/systemd/user/umbriel.service.d"
install_if_changed 644 \
  "$INSTALL_ROOT/assets/systemd/user/umbriel.service.d/10-gpu.conf" \
  "$REAL_HOME/.config/systemd/user/umbriel.service.d/10-gpu.conf"
chown -R "$REAL_UID:$REAL_GID" "$REAL_HOME/.config/systemd/user" 2>/dev/null || true

# mkinitcpio: early KMS for Intel (i915+xe) + NVIDIA stack on hybrid laptops
if [[ -f /etc/mkinitcpio.conf ]]; then
  modules_line="$(grep -E '^MODULES=' /etc/mkinitcpio.conf || true)"
  if [[ -n "$modules_line" ]]; then
    need_mkinit=0
    if ! grep -qE 'nvidia_drm' <<<"$modules_line"; then
      backup_file /etc/mkinitcpio.conf
      sed -i 's/^MODULES=(/MODULES=(i915 xe nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
      need_mkinit=1
      gpu_config_changed=1
    elif ! grep -qE '(^|[[:space:]\(])xe($|[[:space:]\)])' <<<"$modules_line"; then
      backup_file /etc/mkinitcpio.conf
      if grep -qE 'i915' <<<"$modules_line"; then
        sed -i 's/i915 /i915 xe /' /etc/mkinitcpio.conf
      else
        sed -i 's/nvidia /xe nvidia /' /etc/mkinitcpio.conf
      fi
      need_mkinit=1
      gpu_config_changed=1
    fi
    if ((need_mkinit == 1)); then
      if pkg_installed linux-zen; then
        mkinitcpio -p linux-zen || warn "mkinitcpio linux-zen falhou (DKMS pode completar no próximo boot)"
      else
        mkinitcpio -P || true
      fi
    elif ((gpu_config_changed == 1)); then
      if pkg_installed linux-zen; then
        mkinitcpio -p linux-zen || warn "mkinitcpio linux-zen falhou (DKMS pode completar no próximo boot)"
      else
        mkinitcpio -P || true
      fi
    else
      already_ok
    fi
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

# persistenced keeps the dGPU awake — never wanted with RTD3.
# powerd (Dynamic Boost) stays available but off at boot; prime-run starts it,
# idle timer stops it when every NVIDIA display function is suspended.
if systemctl list-unit-files nvidia-persistenced.service &>/dev/null; then
  systemctl disable --now nvidia-persistenced.service 2>/dev/null || true
  systemctl mask nvidia-persistenced.service 2>/dev/null || true
  ok "nvidia-persistenced masked (RTD3)"
fi
if systemctl list-unit-files nvidia-powerd.service &>/dev/null; then
  systemctl disable nvidia-powerd.service 2>/dev/null || true
  systemctl stop nvidia-powerd.service 2>/dev/null || true
  ok "nvidia-powerd disabled at boot (started on demand by prime-run)"
fi

mkdir -p /usr/local/lib/pandora /etc/sudoers.d
install_if_changed 755 \
  "$INSTALL_ROOT/assets/nvidia/pandora-nvidia-powerd-start" \
  /usr/local/lib/pandora/nvidia-powerd-start
install_if_changed 755 \
  "$INSTALL_ROOT/assets/nvidia/pandora-nvidia-powerd-idle.sh" \
  /usr/local/lib/pandora/nvidia-powerd-idle.sh
install_if_changed 755 \
  "$INSTALL_ROOT/assets/nvidia/pandora-nvidia-pm-check.sh" \
  /usr/local/lib/pandora/nvidia-pm-check.sh
install_if_changed 644 \
  "$INSTALL_ROOT/assets/nvidia/pandora-nvidia-powerd-idle.service" \
  /etc/systemd/system/pandora-nvidia-powerd-idle.service
install_if_changed 644 \
  "$INSTALL_ROOT/assets/nvidia/pandora-nvidia-powerd-idle.timer" \
  /etc/systemd/system/pandora-nvidia-powerd-idle.timer
install_if_changed 644 \
  "$INSTALL_ROOT/assets/nvidia/pandora-nvidia-pm-check.service" \
  /etc/systemd/system/pandora-nvidia-pm-check.service

install_if_changed 440 /dev/stdin /etc/sudoers.d/pandora-nvidia-powerd <<'EOF'
# Pandora: allow wheel to start/stop Dynamic Boost without a password (prime-run / idle timer).
%wheel ALL=(root) NOPASSWD: /usr/bin/systemctl start nvidia-powerd.service, /usr/bin/systemctl stop nvidia-powerd.service
EOF
chmod 440 /etc/sudoers.d/pandora-nvidia-powerd

systemctl daemon-reload
systemctl enable --now pandora-nvidia-powerd-idle.timer 2>/dev/null || warn "timer powerd-idle falhou"
systemctl enable pandora-nvidia-pm-check.service 2>/dev/null || warn "pm-check oneshot enable falhou"

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

install_if_changed 755 "$INSTALL_ROOT/assets/prime-run" /usr/local/bin/prime-run
install_if_changed 755 /dev/stdin /usr/local/bin/prime-env <<'EOF'
#!/usr/bin/env bash
# Same as Pandora prime-run (NVIDIA offload + clear Mesa-only pins + Dynamic Boost).
exec /usr/local/bin/prime-run "$@"
EOF
as_user mkdir -p "$REAL_HOME/.local/bin"
install_if_changed 755 "$INSTALL_ROOT/assets/prime-run" "$REAL_HOME/.local/bin/prime-run"
chown "$REAL_UID:$REAL_GID" "$REAL_HOME/.local/bin/prime-run" 2>/dev/null || true

ok "GPU hybrid + RTD3 (DPM 0x02) + powerd on-demand + GameMode + OBS NVIDIA wrappers prontos"
warn "Reinício necessário se NVreg_* / MODULES (xe) mudaram neste run"
warn "RTD3: dGPU em D3cold ociosa; prime-run acorda (+ Dynamic Boost). Idle timer desliga powerd."
warn "Clientes que seguram a dGPU acordada: btop/nvtop/nvidia-smi e o card GPU do painel System (Noctalia) aberto."
warn "Suspender o laptop com app ainda na NVIDIA pode falhar (PreserveVideoMemoryAllocations=0) — feche prime-run antes."
