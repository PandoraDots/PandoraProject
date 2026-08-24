#!/usr/bin/env bash
# Atualiza forks PandoraDots com upstream caelestia-dots e reaplica overlays.
# Após Hyprland/libcava/qs mudarem de ABI, força rebuild do cli/shell.
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PANDORA_ROOT
source "$PANDORA_ROOT/install/lib.sh"

UPSTREAM_ORG="https://github.com/caelestia-dots"
PANDORA_ORG="https://github.com/PandoraDots"
MERGE_FAILED=0

merge_fork() {
    local name="$1"
    local upstream_url="$UPSTREAM_ORG/$name.git"
    local local_path="$PANDORA_ROOT/../$name"
    local dir
    local stashed=0

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

    # Preserva WIP local (ex.: patches Pandora ainda não commitados)
    if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
        log "Stash de mudanças locais em $name antes do merge..."
        git -C "$dir" stash push -u -m "pandora-update-stash-$(date +%Y%m%d%H%M%S)" && stashed=1
    fi

    git -C "$dir" fetch upstream main
    if ! git -C "$dir" merge upstream/main -m "merge(upstream): caelestia-dots/$name"; then
        warn "Conflitos em $name — resolva manualmente em $dir"
        warn "Arquivos Pandora-owned: inferno scheme, manifest.toml (cursor/equicord), rules.lua, Wallpaper.qml"
        warn "Após resolver: git -C $dir merge --continue && PANDORA_FORCE_REBUILD=1 $PANDORA_ROOT/scripts/update.sh"
        if [[ "$stashed" -eq 1 ]]; then
            warn "Stash preservado: git -C $dir stash list"
        fi
        MERGE_FAILED=1
        return 1
    fi

    if [[ "$stashed" -eq 1 ]]; then
        if git -C "$dir" stash pop; then
            log "Stash reaplicado em $name"
        else
            warn "Conflito ao reaplicar stash em $name — veja: git -C $dir stash list"
            MERGE_FAILED=1
            return 1
        fi
    fi
    return 0
}

mkdir -p "$PANDORA_BUILD"

# Detecta mudança de ABI antes do merge (pacotes do sistema)
if pandora_runtime_changed; then
    log "Runtime stamp desatualizado — rebuild forçado após merge"
    export PANDORA_FORCE_REBUILD=1
fi

if ! pandora_hyprland_version_ok; then
    warn "Hyprland < $(pandora_hyprland_min_version) — dashboard (hl.dsp) pode falhar. Atualize o sistema primeiro: scripts/system-update.sh"
fi

merge_fork cli || true
merge_fork caelestia || true
merge_fork shell || true

# Merge bem-sucedido muda revs dos forks → rebuild
export PANDORA_FORCE_REBUILD="${PANDORA_FORCE_REBUILD:-1}"

log "Rebuild cli/shell (force=${PANDORA_FORCE_REBUILD})..."
bash "$PANDORA_ROOT/install/30-caelestia-build.sh"

if command -v caelestia >/dev/null 2>&1; then
    deploy_overlays
    deploy_sddm_sudoers
    caelestia update --noconfirm --aur-helper "$PANDORA_AUR_HELPER" || warn "caelestia update falhou"
fi

bash "$PANDORA_ROOT/scripts/gpu-profile.sh" 2>/dev/null || true
caelestia scheme set -n inferno -f default -m dark 2>/dev/null || true
bash "$PANDORA_ROOT/scripts/nekro-setup.sh" "$(model_config "${PANDORA_MODEL:-phn16-72}")" 2>/dev/null || true

WALL_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/wallpaper/path.txt"
if [[ -f "$WALL_STATE" ]] && command -v caelestia &>/dev/null; then
    last="$(cat "$WALL_STATE" 2>/dev/null || true)"
    if [[ -n "$last" && -f "$last" ]]; then
        caelestia wallpaper -f "$last" -N 2>/dev/null || true
    fi
fi

configure_keyboard_layout 2>/dev/null || true
deploy_pandora_sddm_conf 2>/dev/null || true
install_hyprland_session 2>/dev/null || true
sync_sddm_theme 2>/dev/null || true
bash "$PANDORA_ROOT/scripts/workspace-dashboard.sh" 2>/dev/null || true

save_pandora_runtime_stamp

if [[ "$MERGE_FAILED" -eq 1 ]]; then
    warn "Update concluído com conflitos de merge — revise os forks antes de reiniciar a sessão."
    exit 1
fi

log "Update concluído."
