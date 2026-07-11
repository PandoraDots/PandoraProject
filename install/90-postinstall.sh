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

run_step "GPU profile inicial" bash -c "
    chmod +x '$PANDORA_ROOT/scripts/gpu-profile.sh'
    deploy_systemd_units
    '$PANDORA_ROOT/scripts/gpu-profile.sh'
    systemctl --user enable pandora-gpu-profile.path pandora-gpu-profile.timer 2>/dev/null || true
    systemctl --user start pandora-gpu-profile.path pandora-gpu-profile.timer 2>/dev/null || true
"

run_step "Schema inferno" bash -c '
    caelestia scheme set -n inferno -f default -m dark
'

run_step "Wallpaper padrão" bash -c "
    if [[ -f '$DEFAULT_WALL' ]]; then
        caelestia wallpaper -f '$DEFAULT_WALL' -N 2>/dev/null || \
        bash '$PANDORA_ROOT/scripts/waywallen-bridge.sh'
    else
        warn 'Wallpaper padrão não encontrado: $DEFAULT_WALL'
    fi
"

run_step "nekro-sense defaults" bash -c "
    chmod +x '$PANDORA_ROOT/scripts/nekro-setup.sh'
    '$PANDORA_ROOT/scripts/nekro-setup.sh' '$MODEL_FILE'
"

run_step "Iniciar serviços user" bash -c '
    systemctl --user start waywallen.service 2>/dev/null || true
    caelestia shell -d >/dev/null 2>&1 || true
'

log "Pós-instalação concluída."
