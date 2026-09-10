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
  noctalia greetd linux-zen linux-zen-headers nvidia-open-dkms nvidia-utils
  nvidia-prime mesa vulkan-intel egl-wayland libva-nvidia-driver
  gamemode steam mangohud goverlay obs-studio
  zram-generator pacman-contrib
  nodejs npm rustup clang cmake
  dotnet-sdk-8.0 dotnet-sdk-10.0
  vlc dolphin ffmpeg pipewire wireplumber
  xwayland-satellite power-profiles-daemon
)

AUR=(
  envycontrol umbriel-git xdg-desktop-portal-umbriel-git noctalia-greeter
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

# Concord / Sung remotes
for url in \
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
