#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

run_step "Sessão Wayland (uwsm + Hyprland)" bash -c '
    aur_install uwsm greetd tuigreet

    sudo mkdir -p /etc/greetd
    if [[ ! -f /etc/greetd/config.toml ]] || ! grep -q "tuigreet" /etc/greetd/config.toml 2>/dev/null; then
        sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --cmd uwsm start -F Hyprland"
user = "greeter"
EOF
    fi

    sudo systemctl enable greetd.service

    mkdir -p "$HOME/.config/uwsm"
    if [[ ! -f "$HOME/.config/uwsm/env" ]]; then
        cat >"$HOME/.config/uwsm/env" <<EOF
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
'

log "Sessão configurada (greetd + uwsm + Hyprland)."
