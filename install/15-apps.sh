#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODEL_FILE="$(model_config "$PANDORA_MODEL")"

mapfile -t APP_PKGS < <(jq -r '.packages.apps[]?' "$MODEL_FILE")

install_app_packages() {
    local pkg missing=()
    for pkg in "${APP_PKGS[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            log "Já instalado: $pkg"
        else
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        if ! pacman_install "${missing[@]}" 2>/dev/null; then
            aur_install "${missing[@]}"
        fi
    fi
}

if [[ ${#APP_PKGS[@]} -eq 0 ]]; then
    log "Nenhum pacote extra em apps; pulando."
    exit 0
fi

run_step "Apps Pandora (FDM, ZapZap, Planify, VLC, arquivos)" install_app_packages

log "Apps instalados."
