#!/usr/bin/env bash
# Aplica polish UX que exige root (pacotes + spicetify) e corrige wallpaper.
# Uso: bash scripts/apply-sudo-polish.sh
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PANDORA_ROOT PANDORA_MODEL="${PANDORA_MODEL:-phn16-72}"
source "$PANDORA_ROOT/install/lib.sh"

DEFAULT_WALL="$PANDORA_ROOT/Wallpapers/glassesredjapan.jpg"

log "Instalando gvfs/fuse2/tumbler/thunar-volman..."
pacman_install gvfs gvfs-mtp tumbler thunar-volman fuse2 sqlite

if [[ -d /opt/spotify ]]; then
    log "Liberando /opt/spotify para spicetify..."
    sudo chmod a+wr /opt/spotify
    sudo chmod a+wr -R /opt/spotify/Apps
fi

if command -v spicetify &>/dev/null; then
    spicetify config current_theme caelestia color_scheme caelestia custom_apps marketplace || true
    spicetify backup apply || spicetify apply || warn "spicetify apply ainda falhou"
fi

log "Instalando launcher Waywallen (.desktop + ícone)..."
install_waywallen_launcher || warn "launcher Waywallen falhou"

# Waywallen daemon no NVIDIA fica preto — desligar
systemctl --user unmask waywallen.service 2>/dev/null || true
systemctl --user disable --now waywallen.service 2>/dev/null || true
pkill -u "$USER" -f 'waywallen.*--no-ui' 2>/dev/null || true

log "Aplicando overlay (Caelestia wallpaper habilitado)..."
deploy_overlays

log "Aplicando wallpaper via Caelestia..."
if [[ -f "$DEFAULT_WALL" ]]; then
    bash "$PANDORA_ROOT/scripts/waywallen-bridge.sh" "$DEFAULT_WALL" || true
else
    bash "$PANDORA_ROOT/scripts/waywallen-bridge.sh" || true
fi

if command -v caelestia &>/dev/null && pandora_shell_qsconf &>/dev/null; then
    log "Reiniciando caelestia shell..."
    if caelestia shell -d >/dev/null 2>&1; then
        log "caelestia shell reiniciado"
    else
        warn "falha ao reiniciar shell — rode: caelestia shell -d"
    fi
fi

log "Pronto. Wallpaper via Caelestia; Waywallen só no launcher."
log "Verifique: bash $PANDORA_ROOT/scripts/verify-install.sh"
