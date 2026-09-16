#!/usr/bin/env bash
# Valida sintaxe + resolução de pacotes (não instala nada destrutivo por padrão)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

fail=0

log "bash -n em todos os scripts"
while IFS= read -r -d '' f; do
  if bash -n "$f"; then
    ok "syntax $f"
  else
    warn "syntax FAIL $f"
    fail=1
  fi
done < <(find "$ROOT" -type f -name '*.sh' -print0)

log "Checando pacotes oficiais / AUR"

OFFICIAL=(
  greetd linux-zen linux-zen-headers nvidia-open-dkms nvidia-utils
  nvidia-prime mesa vulkan-intel egl-wayland libva-nvidia-driver
  gamemode steam mangohud goverlay obs-studio
  zram-generator pacman-contrib
  nodejs npm rustup clang cmake meson ninja
  wlroots0.20 sdbus-cpp tomlplusplus libdisplay-info libepoxy
  dotnet-sdk-8.0 dotnet-sdk-10.0
  vlc dolphin ffmpeg pipewire wireplumber
  xwayland-satellite power-profiles-daemon
  accountsservice ffmpegthumbnailer jemalloc kitty
)

AUR=(
  envycontrol
  cursor-bin rider blockbench-bin heroic-games-launcher-bin
  stremio zapzap proton-vpn-gtk-app labymodlauncher-bin
  hydra-launcher-bin concord-bin concord ttf-ms-fonts
)

missing_off=()
for p in "${OFFICIAL[@]}"; do
  if pac_available "$p"; then
    ok "official: $p"
  else
    warn "official MISSING: $p"
    missing_off+=("$p")
    fail=1
  fi
done

if command -v paru >/dev/null; then
  for p in "${AUR[@]}"; do
    if paru -Si -- "$p" &>/dev/null || pac_available "$p"; then
      ok "aur/repo: $p"
    else
      warn "aur MISSING: $p"
      fail=1
    fi
  done
else
  warn "paru ausente — pulando checagem AUR (install.sh instala paru)"
fi

log "Bootloader atual: $(detect_bootloader)"
log "UEFI: $([[ -d /sys/firmware/efi ]] && echo yes || echo no)"

log "Checando GPU híbrida / RTD3 (não destrutivo)"
if command -v envycontrol >/dev/null; then
  if [[ "$(envycontrol --query 2>/dev/null)" == hybrid ]]; then
    ok "envycontrol: hybrid"
  else
    warn "envycontrol: $(envycontrol --query 2>/dev/null || echo missing) (esperado: hybrid)"
    fail=1
  fi
else
  warn "envycontrol ausente"
  fail=1
fi

bl=/etc/modprobe.d/blacklist-nvidia-wmi-ec-backlight.conf
if [[ -f "$bl" ]] && grep -qx 'blacklist nvidia_wmi_ec_backlight' "$bl"; then
  ok "blacklist nvidia_wmi_ec_backlight"
else
  warn "blacklist nvidia_wmi_ec_backlight ausente ou malformado (\\n literal?)"
  fail=1
fi

if [[ -f /etc/environment.d/90-pandora-igpu.conf ]] \
  && grep -q 'VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.json' /etc/environment.d/90-pandora-igpu.conf; then
  ok "environment.d iGPU + Vulkan pin"
else
  warn "environment.d/90-pandora-igpu.conf sem pin Vulkan Intel"
  fail=1
fi

if [[ -f /etc/mkinitcpio.conf ]] && grep -qE '(^|[[:space:]\(])xe($|[[:space:]\)])' /etc/mkinitcpio.conf \
  && grep -qE 'nvidia_drm' /etc/mkinitcpio.conf; then
  ok "mkinitcpio MODULES: xe + nvidia_drm"
else
  warn "mkinitcpio MODULES sem xe e/ou nvidia_drm"
fi

nvidia_vga=""
for dev in /sys/bus/pci/devices/*; do
  [[ -r "$dev/vendor" && -r "$dev/class" ]] || continue
  [[ "$(cat "$dev/vendor" 2>/dev/null)" == "0x10de" ]] || continue
  [[ "$(cat "$dev/class" 2>/dev/null)" == "0x030000" ]] || continue
  nvidia_vga="$dev"
  break
done
if [[ -n "$nvidia_vga" ]]; then
  control="$(cat "$nvidia_vga/power/control" 2>/dev/null || echo missing)"
  status="$(cat "$nvidia_vga/power/runtime_status" 2>/dev/null || echo missing)"
  if [[ "$control" == "auto" ]]; then
    ok "NVIDIA power/control=auto"
  else
    warn "NVIDIA power/control=$control (esperado: auto)"
    fail=1
  fi
  case "$status" in
    suspended|suspending) ok "NVIDIA runtime_status=$status" ;;
    active)
      warn "NVIDIA runtime_status=active (ok se prime-run/btop/sysmon estiver aberto; senão a dGPU não dormiu)"
      ;;
    *)
      warn "NVIDIA runtime_status=$status"
      ;;
  esac
else
  warn "NVIDIA VGA não encontrada em sysfs (BIOS hybrid?)"
fi

if systemctl is-enabled --quiet nvidia-persistenced.service 2>/dev/null; then
  warn "nvidia-persistenced ainda enabled (deveria estar masked)"
  fail=1
else
  ok "nvidia-persistenced não enabled"
fi

# Remotes essenciais da stack Pandora
for url in \
  "$UMBRIEL_REPO_URL" \
  "$PORTAL_REPO_URL" \
  "$NOCTALIA_REPO_URL" \
  "$NOCTALIA_GREETER_REPO_URL" \
  https://github.com/yPerfectBR/PerfectSense.git \
  https://github.com/yappologistic/Sung.git
do
  if git ls-remote "$url" HEAD &>/dev/null; then
    ok "git reachable: $url"
  else
    warn "git unreachable: $url"
    fail=1
  fi
done

if ((fail)); then
  warn "Validação terminou com avisos/falhas (veja acima)"
  exit 1
fi
ok "Validação limpa"
