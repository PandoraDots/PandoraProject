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
    # path unit causa loop com hyprctl/sysfs — só timer
    systemctl --user disable --now pandora-gpu-profile.path 2>/dev/null || true
    systemctl --user enable --now pandora-gpu-profile.timer 2>/dev/null || true
}

if ! skip_if_ready "GPU profile inicial" bash -c "
    [[ -f '$PANDORA_CONFIG/gpu-profile.env' ]] \
        && systemctl --user is-enabled pandora-gpu-profile.timer &>/dev/null
"; then
    run_step "GPU profile inicial" postinstall_gpu_profile
fi

# PerfectSense (CLI + perms + fan curve) — sempre, independente do skip do GPU timer
postinstall_perfectsense() {
    chmod +x "$PANDORA_ROOT/scripts/perfectsense" \
        "$PANDORA_ROOT/scripts/perfectsense-fan-curve.sh" \
        "$PANDORA_ROOT/scripts/setup-perfectsense-perms.sh" \
        "$PANDORA_ROOT/scripts/pandora-sysfs-write" \
        "$PANDORA_ROOT/scripts/sync-shell-runtime.sh" \
        "$PANDORA_ROOT/scripts/run-deploy-perfectsense-ui.sh" \
        "$PANDORA_ROOT/scripts/start-caelestia-shell.sh" \
        "$PANDORA_ROOT/scripts/restart-caelestia-shell.sh" \
        "$PANDORA_ROOT/scripts/setup-data-ssd.sh" 2>/dev/null || true
    deploy_systemd_units
    bash "$PANDORA_ROOT/scripts/setup-perfectsense-perms.sh" 2>/dev/null \
        || warn "PerfectSense perms — rode: scripts/setup-perfectsense-perms.sh"
    mkdir -p "${XDG_BIN_HOME:-$HOME/.local/bin}"
    ln -sfn "$PANDORA_ROOT/scripts/perfectsense" "${XDG_BIN_HOME:-$HOME/.local/bin}/perfectsense"
    systemctl --user enable --now pandora-fan-curve.service 2>/dev/null \
        || warn "fan-curve unit — verifique overlays/systemd/pandora-fan-curve.service"
}

run_step "PerfectSense (CLI + fan curve + perms)" postinstall_perfectsense

# Sync QML PerfectSense/Monitors do fork shell → runtime (/etc ou ~/.config)
postinstall_sync_shell_ui() {
    local shell_src="${PANDORA_SHELL:-$HOME/shell}"
    [[ -d "$shell_src" ]] || {
        warn "fork shell ausente ($shell_src) — pule sync UI PerfectSense"
        return 0
    }
    if [[ -x "$PANDORA_ROOT/scripts/run-deploy-perfectsense-ui.sh" ]]; then
        PANDORA_SHELL="$shell_src" "$PANDORA_ROOT/scripts/run-deploy-perfectsense-ui.sh" "$shell_src" \
            || warn "sync PerfectSense UI falhou — rode: scripts/run-deploy-perfectsense-ui.sh"
    fi
}

run_step "Sync PerfectSense UI (shell → qs runtime)" postinstall_sync_shell_ui

# SSD DATA (Kingston / LABEL=DATA) — opcional; no-op se disco ausente
postinstall_data_ssd() {
    if [[ -x "$PANDORA_ROOT/scripts/setup-data-ssd.sh" ]]; then
        if command -v pkexec >/dev/null 2>&1; then
            pkexec "$PANDORA_ROOT/scripts/setup-data-ssd.sh" \
                || warn "DATA SSD — rode: sudo scripts/setup-data-ssd.sh"
        else
            sudo "$PANDORA_ROOT/scripts/setup-data-ssd.sh" \
                || warn "DATA SSD — rode: sudo scripts/setup-data-ssd.sh"
        fi
    fi
}

if blkid -L DATA >/dev/null 2>&1 || blkid -U dfd5686c-0b7d-4c4f-9151-104bff20f8c9 >/dev/null 2>&1; then
    run_step "SSD DATA → /mnt/data + ~/DATA" postinstall_data_ssd
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
# Garante cava com cores do schema mesmo se scheme já estava pronto (skip)
run_step "Cava ← schema Caelestia (bars=32)" sync_cava_from_scheme || true

postinstall_wallpaper() {
    if [[ -f "$DEFAULT_WALL" ]]; then
        caelestia wallpaper -f "$DEFAULT_WALL" -N 2>/dev/null \
            || caelestia wallpaper -f "$DEFAULT_WALL" 2>/dev/null \
            || warn "falha ao aplicar wallpaper: $DEFAULT_WALL"
    else
        warn "Wallpaper padrão não encontrado: $DEFAULT_WALL"
    fi
}

if ! skip_if_ready "Wallpaper padrão" wallpaper_ready; then
    run_step "Wallpaper padrão" postinstall_wallpaper
fi

if [[ -x /usr/share/sddm/themes/caelestia/scripts/sync.sh ]]; then
    run_step "Tema SDDM Caelestia (opcional)" sync_sddm_theme || warn "sync SDDM falhou (ok — greeter é tuigreet)"
else
    warn "Tema SDDM Caelestia não instalado — pulando sync (ok — greeter é tuigreet)"
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
    if ! command -v qs >/dev/null || ! pandora_shell_qsconf >/dev/null 2>&1; then
        warn "caelestia shell não instalado (rode install/30-caelestia-build.sh)"
    elif [[ -x "'"$PANDORA_ROOT"'/scripts/start-caelestia-shell.sh" ]]; then
        if "'"$PANDORA_ROOT"'/scripts/start-caelestia-shell.sh" >/dev/null 2>&1; then
            log "caelestia shell iniciado (NVIDIA env)"
        else
            warn "start-caelestia-shell falhou — veja: caelestia shell -l"
        fi
    elif caelestia shell -d >/dev/null 2>&1; then
        log "caelestia shell iniciado"
    else
        warn "caelestia shell falhou ao iniciar — veja: caelestia shell -l"
    fi
'

postinstall_spicetify() {
    deploy_spicetify_inferno || {
        warn "deploy_spicetify_inferno falhou — tentando apply legado"
        command -v spicetify &>/dev/null || return 0
        command -v spotify &>/dev/null || pacman -Qi spotify &>/dev/null || return 0
        if [[ -d /opt/spotify ]]; then
            sudo chmod a+wr /opt/spotify 2>/dev/null || true
            sudo chmod a+wr /opt/spotify/Apps -R 2>/dev/null || true
        fi
        spicetify config current_theme caelestia color_scheme caelestia custom_apps marketplace 2>/dev/null || true
        spicetify backup apply 2>/dev/null || spicetify apply 2>/dev/null || true
    }
}

run_step "Spicetify Inferno (preto/vermelho/branco)" postinstall_spicetify

log "Pós-instalação concluída."
