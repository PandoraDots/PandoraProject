#!/usr/bin/env bash
# Força whitekat como wallpaper do login SDDM (independente do desktop Caelestia).
# Preferência: sudo direto no script (NOPASSWD via deploy_sddm_sudoers).
# Fallback: sync.sh com path temporário (já tem NOPASSWD no install).
set -euo pipefail

_SELF="${BASH_SOURCE[0]}"
while [[ -L "$_SELF" ]]; do
    _dir="$(cd -P "$(dirname "$_SELF")" && pwd)"
    _SELF="$(readlink "$_SELF")"
    [[ "$_SELF" != /* ]] && _SELF="$_dir/$_SELF"
done
PANDORA_ROOT="$(cd "$(dirname "$_SELF")/.." && pwd)"

SRC="${PANDORA_SDDM_WALL:-$PANDORA_ROOT/Wallpapers/whitekat.jpg}"
DEST="/usr/share/sddm/themes/caelestia/assets/background"
THEME_DIR="/usr/share/sddm/themes/caelestia"
SYNC="/usr/share/sddm/themes/caelestia/scripts/sync.sh"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/wallpaper"

already_set() {
    [[ -f "$SRC" && -f "$DEST" ]] || return 1
    command -v md5sum &>/dev/null || return 1
    [[ "$(md5sum "$SRC" | awk '{print $1}')" == "$(md5sum "$DEST" | awk '{print $1}')" ]]
}

if [[ ! -f "$SRC" ]]; then
    echo "Pandora SDDM: wallpaper ausente: $SRC" >&2
    exit 0
fi

if [[ ! -d "$THEME_DIR/assets" ]]; then
    echo "Pandora SDDM: tema Caelestia ausente em $THEME_DIR" >&2
    exit 0
fi

if already_set; then
    exit 0
fi

# Caminho 1: root / sudo no script inteiro
if [[ "$(id -u)" -eq 0 ]]; then
    cp -f "$SRC" "$DEST"
    rm -f -- "$THEME_DIR/assets"/background.* 2>/dev/null || true
    echo "Pandora SDDM: login wallpaper = whitekat"
    exit 0
fi

if sudo -n "$0" 2>/dev/null; then
    exit 0
fi

# Caminho 2: fallback via sync.sh (NOPASSWD típico do Pandora)
if [[ -x "$SYNC" ]]; then
    mkdir -p "$STATE"
    desk=""
    [[ -f "$STATE/path.txt" ]] && desk="$(cat "$STATE/path.txt")"
    [[ -z "$desk" && -L "$STATE/current" ]] && desk="$(readlink -f "$STATE/current")"
    ln -sfn "$SRC" "$STATE/current"
    printf '%s\n' "$SRC" >"$STATE/path.txt"
    if sudo -n "$SYNC" --posthook 2>/dev/null || sudo "$SYNC" --posthook 2>/dev/null; then
        if [[ -n "$desk" && -f "$desk" ]]; then
            ln -sfn "$desk" "$STATE/current"
            printf '%s\n' "$desk" >"$STATE/path.txt"
        fi
        if already_set; then
            echo "Pandora SDDM: login wallpaper = whitekat (via sync)"
            exit 0
        fi
    fi
    if [[ -n "$desk" && -f "$desk" ]]; then
        ln -sfn "$desk" "$STATE/current"
        printf '%s\n' "$desk" >"$STATE/path.txt"
    fi
fi

echo "Pandora SDDM: não foi possível aplicar whitekat (precisa sudo)" >&2
exit 1
