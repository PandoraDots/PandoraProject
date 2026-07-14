#!/usr/bin/env bash
# Hydra Launcher: reutiliza AppImage do Shelly (ou existente); só baixa se faltar.
# Garante entrada no launcher de apps do Caelestia (XDG .desktop).
set -euo pipefail
PANDORA_ROOT="${PANDORA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export PANDORA_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HYDRA_REPO="${HYDRA_REPO:-hydralauncher/hydra}"

ensure_fuse_for_appimage() {
    if command -v fusermount &>/dev/null || command -v fusermount3 &>/dev/null; then
        return 0
    fi
    warn "fusermount ausente — instalando fuse2 (AppImage)"
    pacman_install fuse2 || true
}

hydra_latest_appimage_url() {
    curl -fsSL "https://api.github.com/repos/${HYDRA_REPO}/releases/latest" \
        | jq -r '.assets[] | select(.name | test("\\.AppImage$")) | .browser_download_url' \
        | head -1
}

# Instala só se não houver Hydra do Shelly / AppImage / PATH.
install_hydra_binary() {
    local existing dest
    existing="$(find_hydra_binary || true)"
    if [[ -n "$existing" && "${HYDRA_FORCE_UPDATE:-0}" != "1" ]]; then
        log "Hydra já instalado (Shelly/local): $existing"
        # Symlink estável hydralauncher → AppImage versionado, se útil
        if [[ "$existing" == *.AppImage ]] && [[ ! -e "${HOME}/.local/bin/hydralauncher" ]]; then
            ln -sfn "$existing" "${HOME}/.local/bin/hydralauncher"
            log "Link: ~/.local/bin/hydralauncher -> $existing"
        fi
        return 0
    fi

    ensure_fuse_for_appimage
    require_cmd curl jq

    local url
    url="$(hydra_latest_appimage_url)"
    [[ -n "$url" && "$url" != "null" ]] || die "Não foi possível obter URL do AppImage do Hydra ($HYDRA_REPO)"

    dest="${HOME}/.local/bin/hydralauncher.AppImage"
    mkdir -p "$(dirname "$dest")"
    log "Baixando Hydra AppImage: $url"
    curl -fL --progress-bar "$url" -o "$dest"
    chmod +x "$dest"
    ln -sfn "$dest" "${HOME}/.local/bin/hydralauncher"
    log "Hydra instalado: $dest"
}

run_step "Hydra Launcher (detectar Shelly / instalar se faltar)" install_hydra_binary
run_step "Hydra no launcher Caelestia (.desktop XDG)" install_hydra_launcher

log "Hydra pronto para o launcher Caelestia (já existente do Shelly é reutilizado)."
