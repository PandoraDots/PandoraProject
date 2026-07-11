#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mkdir -p "$PANDORA_CONFIG"
deploy_overlays
link_wallpapers

# Preferir fork caelestia local (irmão do PandoraProject) para dots
LOCAL_CAE="$PANDORA_ROOT/../caelestia"
DOTS_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/dots"
if [[ -d "$LOCAL_CAE/.git" ]]; then
    log "Usando caelestia local: $LOCAL_CAE"
    mkdir -p "$(dirname "$DOTS_DIR")"
    rm -rf "$DOTS_DIR"
    git clone "$LOCAL_CAE" "$DOTS_DIR"
fi

run_step "Stack de áudio (PipeWire)" install_audio_stack

run_step "caelestia install" caelestia install \
    --noconfirm \
    --aur-helper "$PANDORA_AUR_HELPER" \
    --enable-components spotify,cursor,discord \
    --disable-components vscodium,vscode,pipewire

deploy_overlays

log "Caelestia dots instalados com overlays Pandora."
