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

postinstall_user_dirs() {
    setup_english_user_dirs
    link_wallpapers
}
run_step "XDG user dirs (English)" postinstall_user_dirs
run_step "Thunar ASK + volman" deploy_thunar_overlays

if ! skip_if_ready "Schema inferno" scheme_inferno_ready; then
    run_step "Schema inferno" caelestia scheme set -n inferno -f default -m dark
fi

postinstall_wallpaper() {
    if [[ -f "$DEFAULT_WALL" ]]; then
        caelestia wallpaper -f "$DEFAULT_WALL" -N 2>/dev/null || \
        bash "$PANDORA_ROOT/scripts/wallpaper-posthook.sh" "$DEFAULT_WALL"
        bash "$PANDORA_ROOT/scripts/waywallen-bridge.sh" "$DEFAULT_WALL" || true
    else
        warn "Wallpaper padrão não encontrado: $DEFAULT_WALL"
    fi
}

if ! skip_if_ready "Wallpaper padrão" wallpaper_ready; then
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
    if ! command -v qs >/dev/null || ! pandora_shell_qsconf >/dev/null 2>&1; then
        warn "caelestia shell não instalado (rode install/30-caelestia-build.sh)"
    elif caelestia shell -d >/dev/null 2>&1; then
        log "caelestia shell iniciado"
    else
        warn "caelestia shell falhou ao iniciar — veja: caelestia shell -l"
    fi
'

postinstall_spicetify() {
    command -v spicetify &>/dev/null || {
        warn "spicetify-cli ausente — pulando"
        return 0
    }
    command -v spotify &>/dev/null || pacman -Qi spotify &>/dev/null || {
        warn "spotify ausente — pulando spicetify apply"
        return 0
    }

    # Spicetify precisa escrever em /opt/spotify
    if [[ -d /opt/spotify ]]; then
        sudo chmod a+wr /opt/spotify 2>/dev/null || true
        sudo chmod a+wr /opt/spotify/Apps -R 2>/dev/null || true
    fi

    spicetify config current_theme caelestia color_scheme caelestia custom_apps marketplace 2>/dev/null || true
    if ! spicetify backup apply 2>/dev/null; then
        spicetify apply 2>/dev/null || warn "spicetify apply falhou — rode: sudo chmod a+wr /opt/spotify && spicetify backup apply"
    fi
}

if ! skip_if_ready "Spicetify tema caelestia" bash -c '
    grep -q "^current_theme[ =]*caelestia" "${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/config-xpui.ini" 2>/dev/null \
        && grep -qE "^version[ =]+.+" "${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/config-xpui.ini" 2>/dev/null
'; then
    run_step "Spicetify tema caelestia" postinstall_spicetify
fi

log "Pós-instalação concluída."
