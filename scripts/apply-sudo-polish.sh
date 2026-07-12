#!/usr/bin/env bash
# Aplica polish UX que exige root (pacotes + spicetify perms).
# Uso: bash scripts/apply-sudo-polish.sh
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PANDORA_ROOT PANDORA_MODEL="${PANDORA_MODEL:-phn16-72}"
source "$PANDORA_ROOT/install/lib.sh"

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

log "Pronto. Rode: bash $PANDORA_ROOT/scripts/waywallen-bridge.sh"
log "E: PATH=\"\$HOME/.local/bin:\$PATH\" caelestia scheme set -n inferno -f default -m dark"
