#!/usr/bin/env bash
# 60 — Dev toolchains: vim, node, .NET 8+10, Rider, C/C++, Rust, Cursor
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user

log "Toolchains de desenvolvimento"

pac_install \
  vim neovim \
  nodejs npm \
  clang llvm lld lldb \
  gcc gdb cmake ninja meson \
  python python-pip python-virtualenv \
  dotnet-sdk-8.0 dotnet-sdk-10.0 \
  docker docker-compose

# paru may already have installed the distro Rust toolchain; rustup conflicts
# with that package. Keep a working distro toolchain on repeated installations.
if ! pkg_installed rust && ! pkg_installed rustup; then
  pac_install rustup
fi

# rustup default toolchain as user
if command -v rustup >/dev/null; then
  if as_user rustup show active-toolchain 2>/dev/null | grep -q '^stable-'; then
    already_ok
  else
    as_user rustup default stable
  fi
  for component in rustfmt clippy; do
    if as_user rustup component list --installed | grep -q "^${component}-"; then
      already_ok
    else
      as_user rustup component add "$component" || true
    fi
  done
fi

install_prefer cursor-bin || warn "cursor-bin (AUR) falhou"
# Cursor wrapper remains as belt-and-suspenders; session-wide iGPU defaults live in
# /etc/environment.d/90-pandora-igpu.conf (module 30) so every Electron app inherits them.
if [[ -x /usr/share/cursor/cursor || -x /usr/bin/cursor ]]; then
  as_user mkdir -p "$REAL_HOME/.local/bin" "$REAL_HOME/.local/share/applications" \
    "$REAL_HOME/.config/pandora" "$REAL_HOME/.config/environment.d"

  # Detect Intel PCI at install time (avoid hardcoding device/BDF).
  intel_pci="$(lspci -Dn 2>/dev/null | awk '$2 ~ /^(0300|0302|0380):$/ && $3 ~ /^8086:/ {print $1; exit}')"
  intel_dri="pci-0000_00_02_0"
  intel_dev="a788"
  if [[ -n "$intel_pci" && -r "/sys/bus/pci/devices/${intel_pci}/device" ]]; then
    intel_dri="pci-${intel_pci//[:.]/_}"
    intel_dev="$(sed 's/^0x//' "/sys/bus/pci/devices/${intel_pci}/device")"
  fi

  tmp_env="$(mktemp)"
  cat >"$tmp_env" <<EOF
# Pandora: force Cursor/Electron onto Intel Mesa (generated at install).
# Session-wide defaults are in environment.d; this file strengthens Cursor only.
export __GLX_VENDOR_LIBRARY_NAME=mesa
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.json
export MESA_VK_DEVICE_SELECT=8086:${intel_dev}!
export DRI_PRIME=${intel_dri}
export __NV_PRIME_RENDER_OFFLOAD=0
unset __VK_LAYER_NV_optimus 2>/dev/null || true
export CUDA_VISIBLE_DEVICES=
export NVIDIA_VISIBLE_DEVICES=void
export ELECTRON_OZONE_PLATFORM_HINT="\${ELECTRON_OZONE_PLATFORM_HINT:-auto}"
EOF
  install_if_changed 644 "$tmp_env" "$REAL_HOME/.config/pandora/cursor-igpu-env.sh"
  rm -f "$tmp_env"
  # Keep asset template in sync for reference checkouts without re-running detect.
  install_if_changed 644 "$INSTALL_ROOT/assets/cursor-igpu-env.sh" \
    "$REAL_HOME/.config/pandora/cursor-igpu-env.template.sh" 2>/dev/null || true

  install_if_changed 755 "$INSTALL_ROOT/assets/cursor-igpu" "$REAL_HOME/.local/bin/cursor"
  install_if_changed 644 "$INSTALL_ROOT/assets/environment.d/90-pandora-igpu.conf" \
    "$REAL_HOME/.config/environment.d/90-pandora-igpu.conf"
  tmp_desktop="$(mktemp)"
  sed "s|@HOME@|$REAL_HOME|g" "$INSTALL_ROOT/assets/cursor-igpu.desktop" >"$tmp_desktop"
  install_if_changed 644 "$tmp_desktop" "$REAL_HOME/.local/share/applications/cursor.desktop"
  rm -f "$tmp_desktop"
  # Inject source into the distro launcher so internal Electron restarts keep iGPU env.
  if [[ -f /usr/share/cursor/cursor ]] && ! grep -q 'Pandora iGPU begin' /usr/share/cursor/cursor; then
    backup_file /usr/share/cursor/cursor
    awk '
      BEGIN { done = 0 }
      {
        print
        if (!done && $0 ~ /^set -euo pipefail/) {
          print ""
          print "# Pandora iGPU begin"
          print "if [[ -f \"${XDG_CONFIG_HOME:-$HOME/.config}/pandora/cursor-igpu-env.sh\" ]]; then"
          print "  # shellcheck source=/dev/null"
          print "  source \"${XDG_CONFIG_HOME:-$HOME/.config}/pandora/cursor-igpu-env.sh\""
          print "fi"
          print "# Pandora iGPU end"
          done = 1
        }
      }
    ' /usr/share/cursor/cursor > /tmp/pandora-cursor-launcher
    install_if_changed 755 /tmp/pandora-cursor-launcher /usr/share/cursor/cursor
    rm -f /tmp/pandora-cursor-launcher
  fi
  chown -R "$REAL_UID:$REAL_GID" "$REAL_HOME/.local/bin/cursor" \
    "$REAL_HOME/.config/pandora" "$REAL_HOME/.config/environment.d" \
    "$REAL_HOME/.local/share/applications/cursor.desktop" 2>/dev/null || true
  ok "Cursor → Intel iGPU (wrapper + detected PCI ${intel_pci:-unknown} + environment.d)"
fi
install_prefer rider || warn "rider (AUR) falhou — IDE grande; tente depois: paru -S rider"

# Docker opcional para o user
if id -nG "$REAL_USER" | tr ' ' '\n' | grep -qx docker; then
  already_ok
else
  usermod -aG docker "$REAL_USER" 2>/dev/null || true
fi
systemd_enable docker.service || true

ok "Dev stack instalada"
