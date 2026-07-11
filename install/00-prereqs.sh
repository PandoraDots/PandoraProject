#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if is_cachyos; then
    run_step "Repositórios CachyOS" ensure_cachyos_repos
fi

prereqs_install_packages() {
    ensure_paru

    pacman_install \
        base-devel git cmake ninja python python-pip python-build python-installer \
        python-hatch python-hatchling python-hatch-vcs \
        libnotify swappy grim dart-sass wl-clipboard slurp gpu-screen-recorder \
        glib2 cliphist fuzzel jq \
        networkmanager bluez bluez-utils gnome-keyring polkit-gnome \
        fish eza zoxide direnv starship \
        noto-fonts noto-fonts-cjk noto-fonts-emoji \
        curl trash-cli lazygit bat ripgrep ydotool hyprpicker xdg-user-dirs \
        hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
        ttf-jetbrains-mono-nerd foot fastfetch btop micro thunar \
        adw-gtk-theme papirus-icon-theme papirus-folders \
        qt6-base qt6-declarative qt6-wayland qt6-shadertools \
        frameworkintegration libpipewire \
        quickshell-git ddcutil brightnessctl lm_sensors aubio \
        ttf-material-symbols-variable ttf-cascadia-code-nerd \
        libqalculate bash python-pillow \
        cava cmatrix tty-clock \
        power-profiles-daemon

    # AUR com providers conhecidos — um por vez, ordem importa para Qt/KDE.
    aur_install_one qtengine
    aur_install_one libcava
    aur_install_one darkly-bin

    install_audio_stack
}

run_step "Pré-requisitos do sistema" prereqs_install_packages

mkdir -p "$PANDORA_STATE" "$PANDORA_BUILD"
log "Pré-requisitos instalados."
