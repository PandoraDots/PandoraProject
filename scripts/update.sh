#!/usr/bin/env bash
# Atualiza forks PandoraDots com upstream caelestia-dots e reaplica overlays.
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PANDORA_ROOT
source "$PANDORA_ROOT/install/lib.sh"

UPSTREAM_ORG="https://github.com/caelestia-dots"
PANDORA_ORG="https://github.com/PandoraDots"

merge_fork() {
    local name="$1"
    local upstream_url="$UPSTREAM_ORG/$name.git"
    local local_path="$PANDORA_ROOT/../$name"
    local dir

    if [[ -d "$local_path/.git" ]]; then
        dir="$local_path"
        log "Atualizando fork local: $dir"
    else
        dir="$PANDORA_BUILD/$name"
        log "Atualizando fork remoto: $name"
        clone_or_pull "$PANDORA_ORG/$name.git" "$dir"
    fi

    if ! git -C "$dir" remote get-url upstream >/dev/null 2>&1; then
        git -C "$dir" remote add upstream "$upstream_url"
    fi

    git -C "$dir" fetch upstream main
    if ! git -C "$dir" merge upstream/main -m "merge(upstream): caelestia-dots/$name"; then
        warn "Conflitos em $name — resolva manualmente em $dir"
        warn "Arquivos Pandora-owned: inferno scheme, manifest.toml (cursor/equicord), rules.lua"
        return 1
    fi
    return 0
}

mkdir -p "$PANDORA_BUILD"

merge_fork cli || true
merge_fork caelestia || true
merge_fork shell || true

log "Rebuild cli/shell se necessário..."
bash "$PANDORA_ROOT/install/30-caelestia-build.sh"

if command -v caelestia >/dev/null 2>&1; then
    deploy_overlays
    caelestia update --noconfirm --aur-helper "$PANDORA_AUR_HELPER" || warn "caelestia update falhou"
fi

bash "$PANDORA_ROOT/scripts/gpu-profile.sh" 2>/dev/null || true
caelestia scheme set -n inferno -f default -m dark 2>/dev/null || true
bash "$PANDORA_ROOT/scripts/nekro-setup.sh" "$(model_config "${PANDORA_MODEL:-phn16-72}")" 2>/dev/null || true

LAST_WALL="${XDG_STATE_HOME:-$HOME/.local/state}/pandora/waywallen-last.txt"
if [[ -f "$LAST_WALL" ]]; then
    export WALLPAPER_PATH="$(cat "$LAST_WALL")"
    bash "$PANDORA_ROOT/scripts/waywallen-bridge.sh" || true
fi

log "Update concluído."
