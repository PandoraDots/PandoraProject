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
    echo "Pandora bridge: nenhum wallpaper encontrado" >&2
    exit 0
fi

WALL="$(readlink -f "$WALL")"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pandora"
mkdir -p "$STATE_DIR"
printf '%s\n' "$WALL" >"$STATE_DIR/waywallen-last.txt"

# Biblioteca padrão = Pictures/Wallpapers (symlink Pandora)
# shellcheck disable=SC1090
[[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" ]] && source "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
PICTURES="${XDG_PICTURES_DIR:-$HOME/Pictures}"
PICTURES="${PICTURES/#\$HOME/$HOME}"
LIB_DIR="$PICTURES/Wallpapers"
mkdir -p "$LIB_DIR"

# Garante cópia/link do wallpaper na library dir
BASE="$(basename "$WALL")"
TARGET="$LIB_DIR/$BASE"
if [[ "$(readlink -f "$TARGET" 2>/dev/null || true)" != "$WALL" && ! -f "$TARGET" ]]; then
    ln -sfn "$WALL" "$TARGET" 2>/dev/null || cp -n "$WALL" "$TARGET" 2>/dev/null || true
fi

DB="${XDG_DATA_HOME:-$HOME/.local/share}/waywallen/waywallen-v2.db"
mkdir -p "$(dirname "$DB")"

ensure_library_root() {
    command -v sqlite3 &>/dev/null || return 1
    [[ -f "$DB" ]] || return 1
    local count
    count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM library WHERE path = '$LIB_DIR';" 2>/dev/null || echo 0)"
    if [[ "${count:-0}" -eq 0 ]]; then
        sqlite3 "$DB" "INSERT OR IGNORE INTO library (plugin_id, path, metadata) VALUES (1, '$LIB_DIR', '{}');" 2>/dev/null || true
    fi
}

BUS="org.waywallen.waywallen.Daemon"
OBJ="/org/waywallen/waywallen/Daemon"
IFACE="org.waywallen.waywallen.Daemon1"

dbus_ok() {
    gdbus introspect --session --dest "$BUS" --object-path "$OBJ" &>/dev/null
}

# Garante daemon ativo
systemctl --user start waywallen.service 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8; do
    dbus_ok && break
    sleep 0.5
done

if ! dbus_ok; then
    echo "Pandora bridge: Waywallen D-Bus indisponível" >&2
    exit 0
fi

ensure_library_root || true

gdbus call --session --dest "$BUS" --object-path "$OBJ" \
    --method "$IFACE.Rescan" &>/dev/null || true
sleep 0.8

# Resolve item id pelo basename
ITEM_ID=""
if command -v sqlite3 &>/dev/null && [[ -f "$DB" ]]; then
    ITEM_ID="$(sqlite3 "$DB" "SELECT id FROM item WHERE path = '$BASE' OR path LIKE '%/$BASE' OR path = '$WALL' LIMIT 1;" 2>/dev/null || true)"
fi

apply_by_id() {
    local id="$1"
    [[ -n "$id" ]] || return 1
    gdbus call --session --dest "$BUS" --object-path "$OBJ" \
        --method "$IFACE.ApplyById" "$id" &>/dev/null
}

apply_via_portal() {
    local key="$1"
    gdbus call --session --dest "$BUS" --object-path "$OBJ" \
        --method "$IFACE.ApplyViaPortal" "$key" &>/dev/null
}

if apply_by_id "$ITEM_ID"; then
    exit 0
fi

# Fallback: id = basename / path
apply_via_portal "$BASE" && exit 0
apply_via_portal "$WALL" && exit 0
apply_via_portal "file://${WALL}" && exit 0

# Portal freedesktop
if command -v busctl >/dev/null 2>&1; then
    busctl --user call org.freedesktop.portal.Desktop \
        /org/freedesktop/portal/desktop \
        org.freedesktop.portal.Wallpaper SetWallpaperURI \
        ssa{sv} "" "file://${WALL}" 2 \
        set-on s "background" show-preview b false 2>/dev/null && exit 0
fi

echo "Pandora bridge: não foi possível aplicar wallpaper no Waywallen ($WALL)" >&2
exit 0
