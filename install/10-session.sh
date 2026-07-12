#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

run_step "Teclado padrão (br-abnt2)" configure_keyboard_layout

session_install_sddm() {
    pacman_install sddm qt6-5compat
    aur_install_one caelestia-sddm-locklike-git

    deploy_pandora_sddm_conf

    sudo systemctl disable greetd.service 2>/dev/null || true
    sudo systemctl enable sddm.service
}

run_step "Display manager (SDDM + tema Caelestia)" session_install_sddm

deploy_sddm_sudoers

run_step "Sessão Hyprland uwsm (-g 0)" install_hyprland_uwsm_session

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

run_step "Sessão Wayland (uwsm + Hyprland)" session_install_uwsm

log "Sessão configurada (SDDM + Caelestia locklike + uwsm + Hyprland)."
