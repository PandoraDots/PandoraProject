#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd caelestia

MODEL_FILE="$(model_config "$PANDORA_MODEL")"
DEFAULT_WALL="$PANDORA_ROOT/Wallpapers/glassesredjapan.jpg"

if ! skip_if_ready "Perfil de energia: performance" bash -c '
    command -v powerprofilesctl &>/dev/null \
        && [[ "$(powerprofilesctl get 2>/dev/null)" == "performance" ]]
'; then
    run_step "Perfil de energia: performance" bash -c '
        powerprofilesctl set performance 2>/dev/null || true
        if [[ -f /sys/firmware/acpi/platform_profile ]]; then
            echo performance | sudo tee /sys/firmware/acpi/platform_profile >/dev/null 2>&1 || true
        fi
    '
fi

postinstall_gpu_profile() {
    chmod +x "$PANDORA_ROOT/scripts/gpu-profile.sh"
    deploy_systemd_units
    "$PANDORA_ROOT/scripts/gpu-profile.sh"
    systemctl --user enable pandora-gpu-profile.path pandora-gpu-profile.timer 2>/dev/null || true
    systemctl --user start pandora-gpu-profile.path pandora-gpu-profile.timer 2>/dev/null || true
}

if ! skip_if_ready "GPU profile inicial" bash -c "
    [[ -f '$PANDORA_CONFIG/gpu-profile.env' ]] \
        && systemctl --user is-enabled pandora-gpu-profile.path &>/dev/null
"; then
    run_step "GPU profile inicial" postinstall_gpu_profile
fi

run_step "Ícone de usuário (~/.face)" deploy_user_icon

if ! skip_if_ready "Schema inferno" scheme_inferno_ready; then
    run_step "Schema inferno" caelestia scheme set -n inferno -f default -m dark
fi

postinstall_wallpaper() {
    if [[ -f "$DEFAULT_WALL" ]]; then
        caelestia wallpaper -f "$DEFAULT_WALL" -N 2>/dev/null || \
        bash "$PANDORA_ROOT/scripts/wallpaper-posthook.sh" "$DEFAULT_WALL"
    else
        warn "Wallpaper padrão não encontrado: $DEFAULT_WALL"
    fi
}

if ! skip_if_ready "Wallpaper padrão" bash -c "
    [[ -f '${XDG_STATE_HOME:-$HOME/.local/state}/pandora/waywallen-last.txt' ]]
"; then
    run_step "Wallpaper padrão" postinstall_wallpaper
fi

if [[ -x /usr/share/sddm/themes/caelestia/scripts/sync.sh ]]; then
    run_step "Tema SDDM Caelestia" sync_sddm_theme
else
    warn "Tema SDDM Caelestia não instalado — pulando sync"
fi

run_step "nekro-sense defaults" bash -c "
    chmod +x '$PANDORA_ROOT/scripts/nekro-setup.sh'
    '$PANDORA_ROOT/scripts/nekro-setup.sh' '$MODEL_FILE'
"

postinstall_dashboard() {
    chmod +x "$PANDORA_ROOT/scripts/workspace-dashboard.sh"
    deploy_overlays
    bash "$PANDORA_ROOT/scripts/workspace-dashboard.sh" || true
}

if ! skip_if_ready "Dashboard workspace 1" pandora_overlays_ready; then
    run_step "Dashboard workspace 1" postinstall_dashboard
else
    deploy_overlays
fi

run_step "Iniciar serviços user" bash -c '
    systemctl --user start waywallen.service 2>/dev/null || true
    caelestia shell -d >/dev/null 2>&1 || true
'

log "Pós-instalação concluída."
