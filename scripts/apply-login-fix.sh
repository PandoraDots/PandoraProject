#!/usr/bin/env bash
# Aplica fixes de login SDDM/UWSM que exigem root (uma vez).
# Uso: bash scripts/apply-login-fix.sh
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PANDORA_ROOT
source "$PANDORA_ROOT/install/lib.sh"

chmod +x "$PANDORA_ROOT/scripts/sddm-set-login-wall.sh" \
    "$PANDORA_ROOT/scripts/pandora-wayland-session.sh"

log "SDDM DisplayServer=x11-user + SessionCommand pandora..."
deploy_pandora_sddm_conf

log "Sudoers SDDM + whitekat..."
deploy_sddm_sudoers

log "Sessão uwsm -g -1 + wrapper wayland-session..."
install_hyprland_uwsm_session

log "Sync tema + whitekat..."
sync_sddm_theme

log "Systemd GPU (timer, sem path loop)..."
deploy_systemd_units

log "Overlays..."
deploy_overlays

bash "$PANDORA_ROOT/scripts/gpu-profile.sh" || true

log "Pronto. Reboot e valide: 1 login, Session started true, sem greeter restart."
log "Verifique: bash $PANDORA_ROOT/scripts/verify-install.sh"
