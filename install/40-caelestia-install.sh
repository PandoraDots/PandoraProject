#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd caelestia qs
ensure_caelestia_cli_deps
pandora_cli_ready || die "caelestia CLI não funcional — verifique materialyoucolor/pillow"

mkdir -p "$PANDORA_CONFIG"
deploy_overlays
link_wallpapers

LOCAL_CAE="$PANDORA_ROOT/../caelestia"
DOTS_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/dots"

install_caelestia_dots() {
    if [[ -d "$LOCAL_CAE/.git" ]]; then
        log "Usando caelestia local: $LOCAL_CAE"
        mkdir -p "$(dirname "$DOTS_DIR")"
        if [[ ! -d "$DOTS_DIR/.git" ]]; then
            git clone "$LOCAL_CAE" "$DOTS_DIR" >&2
        else
            log "Dots locais já clonados: $DOTS_DIR"
        fi
    fi

    run_step "Stack de áudio (PipeWire)" install_audio_stack

    run_step "caelestia install" caelestia install \
        --noconfirm \
        --aur-helper "$PANDORA_AUR_HELPER" \
        --enable-components spotify,cursor,discord \
        --disable-components vscodium,vscode,pipewire,qt
}

if skip_if_ready "caelestia install (dots)" caelestia_dots_ready; then
    log "Reaplicando overlays Pandora"
    deploy_overlays
else
    install_caelestia_dots
    deploy_overlays
fi

log "Caelestia dots instalados com overlays Pandora."
