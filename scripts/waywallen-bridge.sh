#!/usr/bin/env bash
# Bridge: aplica wallpaper no Caelestia (renderer confiável no NVIDIA).
# NÃO inicia o daemon Waywallen — o layer-shell fica preto e cobre o fundo.
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# Biblioteca Waywallen (app UI no launcher)
# shellcheck disable=SC1090
[[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" ]] && source "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
PICTURES="${XDG_PICTURES_DIR:-$HOME/Pictures}"
PICTURES="${PICTURES/#\$HOME/$HOME}"
LIB_DIR="$PICTURES/Wallpapers"
mkdir -p "$LIB_DIR"

BASE="$(basename "$WALL")"
TARGET="$LIB_DIR/$BASE"
if [[ "$(readlink -f "$TARGET" 2>/dev/null || true)" != "$WALL" && ! -f "$TARGET" ]]; then
    ln -sfn "$WALL" "$TARGET" 2>/dev/null || cp -n "$WALL" "$TARGET" 2>/dev/null || true
fi

# Se já estamos no postHook do CLI (SCHEME_* setado), o wallpaper já foi aplicado.
# Caso contrário (hypr start / polish), aplica via caelestia com guard anti-loop.
if [[ -z "${SCHEME_NAME:-}" ]] && command -v caelestia &>/dev/null; then
    PANDORA_SKIP_WALLPAPER_POSTHOOK=1 caelestia wallpaper -f "$WALL" -N 2>/dev/null \
        || PANDORA_SKIP_WALLPAPER_POSTHOOK=1 caelestia wallpaper -f "$WALL" 2>/dev/null \
        || true
fi

# Sync opcional se o daemon Waywallen já estiver ativo (não iniciar)
BUS="org.waywallen.waywallen.Daemon"
OBJ="/org/waywallen/waywallen/Daemon"
IFACE="org.waywallen.waywallen.Daemon1"
DB="${XDG_DATA_HOME:-$HOME/.local/share}/waywallen/waywallen-v2.db"

dbus_ok() {
    gdbus introspect --session --dest "$BUS" --object-path "$OBJ" &>/dev/null
}

if ! dbus_ok; then
    exit 0
fi

if command -v sqlite3 &>/dev/null && [[ -f "$DB" ]]; then
    sqlite3 "$DB" "INSERT OR IGNORE INTO library (plugin_id, path, metadata) VALUES (1, '$LIB_DIR', '{}');" 2>/dev/null || true
fi

gdbus call --session --dest "$BUS" --object-path "$OBJ" \
    --method "$IFACE.Rescan" &>/dev/null || true

ITEM_ID=""
if command -v sqlite3 &>/dev/null && [[ -f "$DB" ]]; then
    ITEM_ID="$(sqlite3 "$DB" "SELECT id FROM item WHERE path = '$BASE' OR path LIKE '%/$BASE' OR path = '$WALL' LIMIT 1;" 2>/dev/null || true)"
fi

if [[ -n "$ITEM_ID" ]]; then
    gdbus call --session --dest "$BUS" --object-path "$OBJ" \
        --method "$IFACE.ApplyById" "$ITEM_ID" &>/dev/null || true
fi

exit 0
