#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WAYWALLEN_VERSION="${WAYWALLEN_VERSION:-0.2.4}"
WAYWALLEN_BIN="$HOME/.local/bin/waywallen"
WAYWALLEN_URL="https://github.com/waywallen/waywallen/releases/download/v${WAYWALLEN_VERSION}/waywallen-${WAYWALLEN_VERSION}-x86_64.AppImage"

install_waywallen_binary() {
    if waywallen_ready; then
        log "Waywallen já existe: $WAYWALLEN_BIN"
        return 0
    fi

    mkdir -p "$(dirname "$WAYWALLEN_BIN")"
    curl -fsSL "$WAYWALLEN_URL" -o "$WAYWALLEN_BIN"
    chmod +x "$WAYWALLEN_BIN"
}

run_step "Waywallen AppImage" install_waywallen_binary

mkdir -p "$HOME/.config/systemd/user"
cat >"$HOME/.config/systemd/user/waywallen.service" <<EOF
[Unit]
Description=Waywallen wallpaper daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=${WAYWALLEN_BIN} --no-ui
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

systemctl --user daemon-reload
if user_unit_enabled waywallen.service; then
    log "waywallen.service já habilitado"
else
    systemctl --user enable waywallen.service
fi

log "Waywallen instalado em $WAYWALLEN_BIN"
