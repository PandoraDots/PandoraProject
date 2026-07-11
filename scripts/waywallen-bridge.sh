#!/usr/bin/env bash
# Bridge: sincroniza wallpaper do Caelestia (Nexus/CLI) com o daemon Waywallen.
set -euo pipefail

WALL="${WALLPAPER_PATH:-${1:-}}"
if [[ -z "$WALL" || ! -f "$WALL" ]]; then
    STATE="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/wallpaper/path.txt"
    if [[ -f "$STATE" ]]; then
        WALL="$(cat "$STATE")"
    fi
fi

if [[ -z "$WALL" || ! -f "$WALL" ]]; then
    exit 0
fi

WALL="$(readlink -f "$WALL")"
URI="file://${WALL}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pandora"
mkdir -p "$STATE_DIR"
printf '%s\n' "$WALL" >"$STATE_DIR/waywallen-last.txt"

# Garante daemon ativo
systemctl --user start waywallen.service 2>/dev/null || true
sleep 0.5

BUS="org.waywallen.waywallen"
OBJ="/org/waywallen/waywallen/Daemon"

apply_via_portal() {
    gdbus call --session \
        --dest "$BUS" \
        --object-path "$OBJ" \
        --method org.waywallen.waywallen.Daemon1.ApplyViaPortal \
        "$URI" 2>/dev/null && return 0

    gdbus call --session \
        --dest "$BUS" \
        --object-path "$OBJ" \
        --method org.waywallen.waywallen.Daemon.ApplyViaPortal \
        "$URI" 2>/dev/null && return 0

    return 1
}

if apply_via_portal; then
    exit 0
fi

# Fallback: portal freedesktop (Hyprland/xdg-desktop-portal)
if command -v busctl >/dev/null 2>&1; then
    busctl --user call org.freedesktop.portal.Desktop \
        /org/freedesktop/portal/desktop \
        org.freedesktop.portal.Wallpaper SetWallpaperURI \
        ssa{sv} "" "$URI" 2 \
        set-on s "background" show-preview b false 2>/dev/null && exit 0
fi

printf 'Pandora bridge: não foi possível aplicar wallpaper no Waywallen (%s)\n' "$WALL" >&2
exit 0
