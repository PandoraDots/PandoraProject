#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if is_cachyos; then
    run_step "Repositórios CachyOS" ensure_cachyos_repos
fi

prereqs_install_packages() {
    pacman_install \
        base-devel git cmake ninja python python-pip python-build python-installer \
        python-hatch python-hatch-vsc \
        libnotify swappy grim dart-sass wl-clipboard slurp gpu-screen-recorder \
        glib2 cliphist fuzzel jq \
        networkmanager bluez bluez-utils gnome-keyring polkit-gnome \
        fish eza zoxide direnv starship \
        noto-fonts noto-fonts-cjk noto-fonts-emoji \
        curl trash-cli lazygit bat ripgrep ydotool hyprpicker xdg-user-dirs \
        hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
        ttf-jetbrains-mono-nerd foot fastfetch btop micro thunar \
        adw-gtk-theme papirus-icon-theme \
        qt6-base qt6-declarative qt6-wayland \
        qtengine frameworkintegration darkly-bin \
        quickshell-git ddcutil brightnessctl libcava lm-sensors aubio \
        material-symbols caskaydia-cove-nerd-fonts \
        libqalculate bash \
        cava cmatrix tty-clock \
        power-profiles-daemon

    install_audio_stack
    ensure_paru
}

run_step "Pré-requisitos do sistema" prereqs_install_packages

mkdir -p "$PANDORA_STATE" "$PANDORA_BUILD"
log "Pré-requisitos instalados."
