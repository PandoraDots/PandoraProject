#!/usr/bin/env bash
# Abre o Waywallen só como seletor. No Hyprland+NVIDIA o layer-shell fica preto
# e cobre o Caelestia — por isso sempre usamos --no-display e aplicamos via CLI.
set -euo pipefail

# Resolve symlink (~/.local/bin/waywallen-ui → scripts/waywallen-ui.sh)
_SELF="${BASH_SOURCE[0]}"
while [[ -L "$_SELF" ]]; do
    _dir="$(cd -P "$(dirname "$_SELF")" && pwd)"
    _SELF="$(readlink "$_SELF")"
    [[ "$_SELF" != /* ]] && _SELF="$_dir/$_SELF"
done
PANDORA_ROOT="$(cd "$(dirname "$_SELF")/.." && pwd)"
BIN="${WAYWALLEN_BIN:-$HOME/.local/bin/waywallen}"
BUS="org.waywallen.waywallen.Daemon"
OBJ="/org/waywallen/waywallen/Daemon"
IFACE="org.waywallen.waywallen.Daemon1"
DB="${XDG_DATA_HOME:-$HOME/.local/share}/waywallen/waywallen-v2.db"

if [[ ! -x "$BIN" ]]; then
    echo "Waywallen não encontrado: $BIN" >&2
    exit 1
fi

# Segurança: nunca deixar o renderer quebrado no fundo
kill_display_engine() {
    pkill -u "$USER" -f 'waywallen-layer-shell' 2>/dev/null || true
    pkill -u "$USER" -f 'waywallen-image-renderer' 2>/dev/null || true
}

resolve_item_path() {
    local id="$1"
    [[ -z "$id" || ! -f "$DB" ]] && return 1
    command -v sqlite3 &>/dev/null || return 1
    sqlite3 "$DB" "
        SELECT CASE
            WHEN i.path LIKE '/%' THEN i.path
            ELSE l.path || '/' || i.path
        END
        FROM item i
        JOIN library l ON l.id = i.library_id
        WHERE i.id = $id
        LIMIT 1;
    " 2>/dev/null
}

apply_to_caelestia() {
    local wall="$1"
    [[ -n "$wall" && -f "$wall" ]] || return 0
    wall="$(readlink -f "$wall")"
    if command -v caelestia &>/dev/null; then
        PANDORA_SKIP_WALLPAPER_POSTHOOK=1 caelestia wallpaper -f "$wall" -N 2>/dev/null \
            || PANDORA_SKIP_WALLPAPER_POSTHOOK=1 caelestia wallpaper -f "$wall" 2>/dev/null \
            || true
    fi
    # State/lib only — SCHEME_NAME evita reaplicar via caelestia
    SCHEME_NAME=pandora-ui bash "$PANDORA_ROOT/scripts/waywallen-bridge.sh" "$wall" || true
    kill_display_engine
}

current_id() {
    busctl --user get-property "$BUS" "$OBJ" "$IFACE" CurrentWallpaperId 2>/dev/null \
        | sed -n 's/^s "\(.*\)"$/\1/p'
}

# Escuta Apply na UI e redireciona para o renderer do Caelestia
watch_applies() {
    local last="" id wall
    # Espera o D-Bus do daemon
    for _ in $(seq 1 30); do
        if busctl --user get-property "$BUS" "$OBJ" "$IFACE" Version &>/dev/null; then
            break
        fi
        sleep 0.2
    done
    last="$(current_id || true)"
    while true; do
        sleep 0.6
        kill_display_engine
        id="$(current_id || true)"
        [[ -z "$id" || "$id" == "$last" ]] && continue
        last="$id"
        wall="$(resolve_item_path "$id" || true)"
        apply_to_caelestia "$wall"
    done
}

kill_display_engine

WATCHER_PID=""
cleanup() {
    [[ -n "$WATCHER_PID" ]] && kill "$WATCHER_PID" 2>/dev/null || true
    kill_display_engine
}
trap cleanup EXIT INT TERM

watch_applies &
WATCHER_PID=$!

# Filtra flags de display se o usuário passar algo conflitante
args=()
for a in "$@"; do
    case "$a" in
        --no-ui|--no-display) ;;
        *) args+=("$a") ;;
    esac
done

"$BIN" --no-display "${args[@]}"
status=$?
cleanup
trap - EXIT INT TERM
exit "$status"
