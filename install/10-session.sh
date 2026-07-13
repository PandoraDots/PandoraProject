#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

run_step "Teclado padrão (br-abnt2)" configure_keyboard_layout

session_install_greetd() {
    pacman_install greetd greetd-tuigreet
    # Pacote SDDM/tema opcional (lock futuro); não é o greeter de boot
    pacman_install sddm qt6-5compat 2>/dev/null || true
    install_caelestia_sddm_fork 2>/dev/null || warn "Fork caelestia-sddm não instalado (ok — greeter é tuigreet)"

    enable_greetd_disable_sddm
}

run_step "Display manager (greetd + tuigreet → start-hyprland)" session_install_greetd

deploy_sddm_sudoers 2>/dev/null || true

run_step "Sessão Hyprland (start-hyprland desktop)" install_hyprland_session

session_install_uwsm() {
    if pkg_in_repos uwsm; then
        pacman_install uwsm
    else
        aur_install_one uwsm
    fi

    mkdir -p "$HOME/.config/uwsm"
    local local_uwsm="$PANDORA_ROOT/../caelestia/uwsm"
    if [[ -d "$local_uwsm" ]]; then
        for f in env env-hyprland; do
            [[ -f "$local_uwsm/$f" ]] && cp -n "$local_uwsm/$f" "$HOME/.config/uwsm/$f" 2>/dev/null || true
        done
    fi

    if [[ ! -f "$HOME/.config/uwsm/env" ]]; then
        cat >"$HOME/.config/uwsm/env" <<'EOF'
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=Hyprland
EOF
    fi

    if command -v fish >/dev/null 2>&1 && [[ "$(basename "$(readlink -f "$(command -v fish)")")" != "fish" ]]; then
        if ! grep -q "$(command -v fish)" /etc/shells 2>/dev/null; then
            echo "$(command -v fish)" | sudo tee -a /etc/shells >/dev/null
        fi
        chsh -s "$(command -v fish)" "$USER" || warn "Não foi possível definir fish como shell padrão"
    fi
}

run_step "Sessão Wayland (uwsm configs + Hyprland)" session_install_uwsm

log "Sessão configurada (greetd autologin → start-hyprland → lock Caelestia)."
