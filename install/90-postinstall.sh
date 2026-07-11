#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODEL_FILE="$(model_config "$PANDORA_MODEL")"
DEFAULT_WALL="$PANDORA_ROOT/Wallpapers/glassesredjapan.jpg"

run_step "Perfil de energia: performance" bash -c '
    powerprofilesctl set performance 2>/dev/null || true
    if [[ -f /sys/firmware/acpi/platform_profile ]]; then
        echo performance | sudo tee /sys/firmware/acpi/platform_profile >/dev/null 2>&1 || true
    fi
'

postinstall_gpu_profile() {
    chmod +x "$PANDORA_ROOT/scripts/gpu-profile.sh"
    deploy_systemd_units
    "$PANDORA_ROOT/scripts/gpu-profile.sh"
    systemctl --user enable pandora-gpu-profile.path pandora-gpu-profile.timer 2>/dev/null || true
    systemctl --user start pandora-gpu-profile.path pandora-gpu-profile.timer 2>/dev/null || true
}

run_step "GPU profile inicial" postinstall_gpu_profile

run_step "Ícone de usuário (~/.face)" deploy_user_icon

run_step "Schema inferno" bash -c '
    caelestia scheme set -n inferno -f default -m dark
'

postinstall_wallpaper() {
    if [[ -f "$DEFAULT_WALL" ]]; then
        caelestia wallpaper -f "$DEFAULT_WALL" -N 2>/dev/null || \
        bash "$PANDORA_ROOT/scripts/wallpaper-posthook.sh" "$DEFAULT_WALL"
    else
        warn "Wallpaper padrão não encontrado: $DEFAULT_WALL"
    fi
}

run_step "Wallpaper padrão" postinstall_wallpaper

run_step "Tema SDDM Caelestia" sync_sddm_theme

run_step "nekro-sense defaults" bash -c "
    chmod +x '$PANDORA_ROOT/scripts/nekro-setup.sh'
    '$PANDORA_ROOT/scripts/nekro-setup.sh' '$MODEL_FILE'
"

postinstall_dashboard() {
    chmod +x "$PANDORA_ROOT/scripts/workspace-dashboard.sh"
    deploy_overlays
    bash "$PANDORA_ROOT/scripts/workspace-dashboard.sh" || true
}

run_step "Dashboard workspace 1" postinstall_dashboard

run_step "Iniciar serviços user" bash -c '
    systemctl --user start waywallen.service 2>/dev/null || true
    caelestia shell -d >/dev/null 2>&1 || true
'

log "Pós-instalação concluída."
