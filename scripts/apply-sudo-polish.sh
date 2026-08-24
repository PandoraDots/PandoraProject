#!/usr/bin/env bash
# Aplica polish UX que exige root (pacotes + spicetify) e corrige wallpaper Caelestia.
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
    # Preferência: overlay Inferno Pandora (preto/vermelho/branco)
    if declare -F deploy_spicetify_inferno &>/dev/null; then
        deploy_spicetify_inferno || warn "deploy_spicetify_inferno falhou"
    else
        spicetify config current_theme caelestia color_scheme caelestia custom_apps marketplace || true
        spicetify backup apply || spicetify apply || warn "spicetify apply ainda falhou"
    fi
fi

log "Instalando Hydra Launcher (.desktop + ícone)..."
install_hydra_launcher || warn "launcher Hydra falhou"

log "Atualizando Orion Launcher (release latest)..."
install_orion_binary || warn "Orion AppImage falhou"
install_orion_launcher || warn "launcher Orion falhou"

log "Aplicando overlays..."
deploy_overlays
deploy_pandora_sddm_conf 2>/dev/null || true
install_hyprland_session 2>/dev/null || true
deploy_systemd_units 2>/dev/null || true
sync_sddm_theme 2>/dev/null || true

log "Aplicando wallpaper via Caelestia..."
if [[ -f "$DEFAULT_WALL" ]] && command -v caelestia &>/dev/null; then
    caelestia wallpaper -f "$DEFAULT_WALL" -N 2>/dev/null \
        || caelestia wallpaper -f "$DEFAULT_WALL" 2>/dev/null \
        || warn "falha ao aplicar wallpaper"
fi

if command -v caelestia &>/dev/null && pandora_shell_qsconf &>/dev/null; then
    log "Reiniciando caelestia shell..."
    if caelestia shell -d >/dev/null 2>&1; then
        log "caelestia shell reiniciado"
    else
        warn "falha ao reiniciar shell — rode: caelestia shell -d"
    fi
fi

log "Pronto. Wallpaper via Caelestia; Hydra no launcher de apps."
log "Verifique: bash $PANDORA_ROOT/scripts/verify-install.sh"
