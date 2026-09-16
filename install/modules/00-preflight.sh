#!/usr/bin/env bash
# 00 — Preflight checks for Arch + linux-zen + nvidia-open-dkms assumptions
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user
ensure_wheel_sudo

log "Preflight (usuário=$REAL_USER home=$REAL_HOME)"

command -v pacman >/dev/null || die "pacman não encontrado — isto precisa ser Arch Linux"
[[ -f /etc/arch-release ]] || warn "/etc/arch-release ausente (ainda assim seguindo)"

# Sync DB early
pacman -Sy --noconfirm

enable_multilib

# Max parallelism for the whole install (makepkg/paru/pacman). Dialed back in 80-finalize.
log "Paralelismo de build/install → todos os cores ($(nproc 2>/dev/null || echo '?'))"
configure_build_parallelism_install
ensure_paru || die "paru é necessário para o restante do install (AUR)"
ok "paru pronto + pacman/makepkg em modo install (todos os cores)"

# Assumptions from archinstall
if ! pkg_installed linux-zen; then
  warn "linux-zen não instalado — archinstall deveria tê-lo colocado. Instalando..."
  pac_install linux-zen linux-zen-headers
else
  already_ok
  pac_install linux-zen-headers
fi

if ! pkg_installed nvidia-open-dkms; then
  warn "nvidia-open-dkms ausente — instalando (stack open + zen)"
  pac_install nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings
else
  already_ok
  pac_install nvidia-utils lib32-nvidia-utils nvidia-settings
fi

# Base tools always useful
pac_install \
  base-devel git curl wget rsync unzip zip \
  jq htop btop nano vim \
  networkmanager polkit \
  pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber \
  xdg-user-dirs xdg-utils \
  qt6-wayland qt5-wayland \
  mesa lib32-mesa vulkan-intel vulkan-icd-loader lib32-vulkan-icd-loader \
  intel-media-driver libva-utils \
  egl-wayland libva-nvidia-driver \
  opencl-nvidia lib32-opencl-nvidia \
  nvidia-prime \
  bluez bluez-utils \
  power-profiles-daemon upower \
  xorg-xwayland xwayland-satellite \
  seahorse gnome-keyring

# Opcional / mirrors recentes
pac_install egl-wayland2 || true

systemd_enable NetworkManager bluetooth power-profiles-daemon

# xdg dirs for user
as_user xdg-user-dirs-update || true

ok "Preflight concluído"
