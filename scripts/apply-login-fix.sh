#!/usr/bin/env bash
# Aplica greetd autologin → Hyprland → lock Caelestia (tuigreet só após logout).
# Uso: bash scripts/apply-login-fix.sh
# Não-interativo: PANDORA_LOGIN_USER=... PANDORA_LOGIN_PASS=... bash scripts/apply-login-fix.sh
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PANDORA_ROOT
source "$PANDORA_ROOT/install/lib.sh"

chmod +x "$PANDORA_ROOT/scripts/sddm-set-login-wall.sh" \
    "$PANDORA_ROOT/scripts/pandora-wayland-session.sh" 2>/dev/null || true

run_step "Usuário e senha de login (greetd autologin)" ensure_pandora_login_user

log "Pacotes greetd + tuigreet..."
pacman_install greetd greetd-tuigreet

log "Sessão start-hyprland em /usr/local..."
install_hyprland_session

log "greetd autologin + PAM keyring + enable; disable sddm..."
enable_greetd_disable_sddm

log "Systemd GPU (timer, sem path loop)..."
deploy_systemd_units

log "Overlays (inclui lock Caelestia no hyprland.start)..."
deploy_overlays

bash "$PANDORA_ROOT/scripts/gpu-profile.sh" || true

log "Pronto. Reboot → autologin ($PANDORA_LOGIN_USER) → Hyprland → lock Caelestia."
log "Após logout: tuigreet (login manual)."
log "Verifique: bash $PANDORA_ROOT/scripts/verify-install.sh"
