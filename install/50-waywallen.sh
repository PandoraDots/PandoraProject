#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WAYWALLEN_VERSION="${WAYWALLEN_VERSION:-0.2.4}"
WAYWALLEN_BIN="$HOME/.local/bin/waywallen"
WAYWALLEN_URL="https://github.com/waywallen/waywallen/releases/download/v${WAYWALLEN_VERSION}/waywallen-${WAYWALLEN_VERSION}-x86_64.AppImage"

ensure_fuse_for_appimage() {
    if command -v fusermount &>/dev/null || command -v fusermount3 &>/dev/null; then
        return 0
    fi
    warn "fusermount ausente — instalando fuse2 (necessário para AppImage Waywallen)"
    pacman_install fuse2 || true
}

install_waywallen_binary() {
    ensure_fuse_for_appimage

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

# Seed library root (Pictures/Wallpapers) para Rescan/ApplyById
seed_waywallen_library() {
    local dirs_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    # shellcheck disable=SC1090
    [[ -f "$dirs_file" ]] && source "$dirs_file"
    local pictures="${XDG_PICTURES_DIR:-$HOME/Pictures}"
    pictures="${pictures/#\$HOME/$HOME}"
    local lib="$pictures/Wallpapers"
    local db="${XDG_DATA_HOME:-$HOME/.local/share}/waywallen/waywallen-v2.db"
    mkdir -p "$lib" "$(dirname "$db")"
    link_wallpapers || true
    if [[ -f "$db" ]] && command -v sqlite3 &>/dev/null; then
        sqlite3 "$db" "INSERT OR IGNORE INTO library (plugin_id, path, metadata) VALUES (1, '$lib', '{}');" 2>/dev/null || true
    fi
}
seed_waywallen_library

log "Waywallen instalado em $WAYWALLEN_BIN"
