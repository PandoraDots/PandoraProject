#!/usr/bin/env bash
set -euo pipefail
PANDORA_ROOT="${PANDORA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export PANDORA_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODEL_FILE="$(model_config "$PANDORA_MODEL")"

mapfile -t APP_PKGS < <(jq -r '.packages.apps[]?' "$MODEL_FILE")
mapfile -t APP_OPT_PKGS < <(jq -r '.packages.apps_optional[]?' "$MODEL_FILE")

install_missing_pkgs() {
    local pkg missing=()
    for pkg in "$@"; do
        [[ -n "$pkg" ]] || continue
        if pacman -Qi "$pkg" &>/dev/null; then
            log "Já instalado: $pkg"
        else
            missing+=("$pkg")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        pacman_install "${missing[@]}"
    fi
}

install_app_packages() {
    local pkg filtered=()
    for pkg in "${APP_PKGS[@]}"; do
        [[ -n "$pkg" ]] || continue
        # ZapZap vem do pacote local Inferno (packages/zapzap-pandora)
        if [[ "$pkg" == "zapzap" ]]; then
            continue
        fi
        filtered+=("$pkg")
    done
    if [[ ${#filtered[@]} -gt 0 ]]; then
        install_missing_pkgs "${filtered[@]}"
    fi
    run_step "ZapZap Pandora Inferno (fonte + tema vermelho)" install_zapzap_pandora
}

# Deps opcionais do Prism (e outras listadas no modelo).
install_app_optional_packages() {
    [[ ${#APP_OPT_PKGS[@]} -eq 0 ]] && {
        log "Nenhuma apps_optional no modelo; pulando."
        return 0
    }
    install_missing_pkgs "${APP_OPT_PKGS[@]}"
}

if [[ ${#APP_PKGS[@]} -eq 0 && ${#APP_OPT_PKGS[@]} -eq 0 ]]; then
    log "Nenhum pacote extra em apps; pulando."
    exit 0
fi

[[ ${#APP_PKGS[@]} -gt 0 ]] && \
    run_step "Apps Pandora (FDM, ZapZap, Planify, VLC, GOverlay, nvtop, CPU-X, Prism, arquivos)" install_app_packages

[[ ${#APP_OPT_PKGS[@]} -gt 0 ]] && \
    run_step "Deps opcionais (Prism: Java, GLFW, OpenAL, gamemode, …)" install_app_optional_packages

log "Apps instalados."
