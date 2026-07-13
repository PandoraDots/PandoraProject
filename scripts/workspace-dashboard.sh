#!/usr/bin/env bash
# Workspace 1 — dashboard: info | btop / cava | cmatrix | clock
# Posiciona via hl.dsp (Hyprland ≥0.55). O center=true global do Caelestia
# é sobrescrito depois do spawn.
# Uso: workspace-dashboard.sh [--force]
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/pandora/dashboard-launched"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

command -v hyprctl >/dev/null 2>&1 || exit 0
command -v foot >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

hypr_dispatch() {
    hyprctl dispatch "$1" >/dev/null 2>&1 || true
}

hypr_exec() {
    local cmd="$1"
    cmd="${cmd//\\/\\\\}"
    cmd="${cmd//\"/\\\"}"
    hypr_dispatch "hl.dsp.exec_cmd(\"${cmd}\")"
}

client_by_class() {
    hyprctl clients -j 2>/dev/null | jq -r --arg c "$1" \
        '.[] | select(.class == $c or .initialClass == $c) | .address' | head -1
}

close_addr() {
    local addr="$1"
    [[ -n "$addr" ]] || return 0
    hypr_dispatch "hl.dsp.window.close({ window = \"address:${addr}\" })"
}

close_dashboard() {
    local addr
    while IFS= read -r addr; do
        close_addr "$addr"
    done < <(hyprctl clients -j 2>/dev/null | jq -r '
        .[] | select(
            (.class | test("^pandora-(info|btop|cava|cmatrix|clock)$"))
            or (.initialClass | test("^pandora-(info|btop|cava|cmatrix|clock)$"))
            or (
                .workspace.id == 1 and (.class == "foot") and (
                    (.title | test("cava|btop|cmatrix|tty-clock|pandora-|fastfetch|Brand";"i"))
                )
            )
        ) | .address
    ')
    # info costuma ficar só como "~ - fish" — fecha foots órfãos na ws1 se --force
    if [[ "$FORCE" -eq 1 ]]; then
        while IFS= read -r addr; do
            close_addr "$addr"
        done < <(hyprctl clients -j 2>/dev/null | jq -r '
            .[] | select(.workspace.id == 1 and .class == "foot") | .address
        ')
    fi
    sleep 0.3
}

# Grid = layout tiled de referência (reserved + gaps + border)
compute_tiles() {
    local gaps_in gaps_out border gap
    gaps_in="$(hyprctl getoption general:gaps_in -j 2>/dev/null | jq -r '
        if .int then .int
        elif .custom then (.custom | split(" ")[0] | tonumber)
        elif .css then (.css | split(" ")[0] | tonumber)
        else 5 end
    ')"
    gaps_out="$(hyprctl getoption general:gaps_out -j 2>/dev/null | jq -r '
        if .int then .int
        elif .custom then (.custom | split(" ")[0] | tonumber)
        elif .css then (.css | split(" ")[0] | tonumber)
        else 10 end
    ')"
    border="$(hyprctl getoption general:border_size -j 2>/dev/null | jq -r '.int // 1')"
    gap=$((gaps_in * 2 + border * 2))

    # reserved: [left, top, right, bottom] nesta build
    eval "$(hyprctl monitors -j | jq -r --argjson gout "$gaps_out" --argjson gap "$gap" '
        .[0]
        | ((.width / .scale) | floor) as $mw
        | ((.height / .scale) | floor) as $mh
        | .reserved[0] as $left
        | .reserved[1] as $top
        | .reserved[2] as $right
        | .reserved[3] as $bottom
        | ($left + $gout) as $gx
        | ($top + $gout) as $gy
        | ($mw - $left - $right - 2*$gout) as $uw
        | ($mh - $top - $bottom - 2*$gout) as $uh
        | ((($uw - $gap) / 2) | floor) as $hw
        | ((($uh - $gap) / 2) | floor) as $hh
        | ((($hw - $gap) / 2) | floor) as $qw
        | ($hw - $gap - $qw) as $cw
        | "GX=\($gx); GY=\($gy); HW=\($hw); HH=\($hh); GAP=\($gap); QW=\($qw); CW=\($cw)"
    ')"
}

place() {
    local class="$1" x="$2" y="$3" w="$4" h="$5"
    local addr tries=0
    addr="$(client_by_class "$class")"
    while [[ -z "$addr" && $tries -lt 50 ]]; do
        sleep 0.1
        addr="$(client_by_class "$class")"
        tries=$((tries + 1))
    done
    [[ -n "$addr" ]] || return 1

    hypr_dispatch "hl.dsp.window.float({ action = \"on\", window = \"address:${addr}\" })"
    hypr_dispatch "hl.dsp.window.resize({ x = ${w}, y = ${h}, window = \"address:${addr}\" })"
    hypr_dispatch "hl.dsp.window.move({ x = ${x}, y = ${y}, relative = false, window = \"address:${addr}\" })"
    # Reaplica após o center global
    sleep 0.08
    hypr_dispatch "hl.dsp.window.resize({ x = ${w}, y = ${h}, window = \"address:${addr}\" })"
    hypr_dispatch "hl.dsp.window.move({ x = ${x}, y = ${y}, relative = false, window = \"address:${addr}\" })"
}

wait_class() {
    local class="$1" tries=0
    while [[ -z "$(client_by_class "$class")" && $tries -lt 50 ]]; do
        sleep 0.1
        tries=$((tries + 1))
    done
    [[ -n "$(client_by_class "$class")" ]]
}

place_all() {
    compute_tiles
    # Demais tiles primeiro; terminal vazio (info) por último
    place pandora-btop    "$((GX + HW + GAP))"         "$GY"                        "$HW" "$HH" || true
    place pandora-cava    "$GX"                        "$((GY + HH + GAP))"         "$HW" "$HH" || true
    place pandora-cmatrix "$((GX + HW + GAP))"         "$((GY + HH + GAP))"         "$QW" "$HH" || true
    place pandora-clock   "$((GX + HW + GAP + QW + GAP))" "$((GY + HH + GAP))"      "$CW" "$HH" || true
    place pandora-info    "$GX"                        "$GY"                        "$HW" "$HH" || true
}

if [[ "$FORCE" -eq 1 ]]; then
    rm -f "$STATE"
    close_dashboard
elif [[ -f "$STATE" ]]; then
    if hyprctl clients -j 2>/dev/null | jq -e '
        [.[] | select(.class | test("^pandora-(info|btop|cava|cmatrix|clock)$"))] | length >= 5
    ' >/dev/null 2>&1; then
        place_all
        exit 0
    fi
    rm -f "$STATE"
fi

mkdir -p "$(dirname "$STATE")"
touch "$STATE"

hypr_dispatch "hl.dsp.focus({ workspace = 1 })"
sleep 0.15

launch() { hypr_exec "$1"; }

# Ordem de spawn: tiles de conteúdo primeiro; terminal vazio (info) por último
launch "env PANDORA_DASHBOARD=1 foot -o pad=0x0 -a pandora-btop -T pandora-btop fish -C 'set -x PANDORA_DASHBOARD 1; exec btop'"
wait_class pandora-btop || true

launch "foot -o pad=0x0 -a pandora-cava -T pandora-cava -e bash ${PANDORA_ROOT}/scripts/pandora-cava.sh"
if wait_class pandora-cava; then
    compute_tiles
    place pandora-cava "$GX" "$((GY + HH + GAP))" "$HW" "$HH" || true
    sleep 0.15
    place pandora-cava "$GX" "$((GY + HH + GAP))" "$HW" "$HH" || true
fi

launch "env PANDORA_DASHBOARD=1 foot -o pad=0x0 -a pandora-cmatrix -T pandora-cmatrix fish -C 'set -x PANDORA_DASHBOARD 1; exec cmatrix -C red -s'"
wait_class pandora-cmatrix || true

# Relógio: foot dedicado (alpha=1 + palette vermelha) — evita rosa do schema/transparência
launch "foot -c ${PANDORA_ROOT}/overlays/foot/pandora-clock.ini -a pandora-clock -T pandora-clock -e bash ${PANDORA_ROOT}/scripts/pandora-clock.sh"
wait_class pandora-clock || true

# Terminal vazio (fastfetch + fish) — último a abrir e a ser posicionado
launch "env PANDORA_DASHBOARD=1 foot -o pad=0x0 -a pandora-info -T pandora-info fish -C 'set -gx PANDORA_DASHBOARD 1; fastfetch; exec fish'"
wait_class pandora-info || true

for _ in $(seq 1 40); do
    pgrep -x cava >/dev/null 2>&1 && break
    sleep 0.1
done

sleep 0.15
place_all
sleep 0.35
place_all
# Terminal vazio por último: posição + foco
compute_tiles
place pandora-info "$GX" "$GY" "$HW" "$HH" || true
info_addr="$(client_by_class pandora-info)"
if [[ -n "$info_addr" ]]; then
    hypr_dispatch "hl.dsp.focus({ window = \"address:${info_addr}\" })"
fi

hypr_dispatch "hl.dsp.focus({ workspace = 1 })"
# Refoca info (focus workspace pode mudar o active)
info_addr="$(client_by_class pandora-info)"
if [[ -n "$info_addr" ]]; then
    hypr_dispatch "hl.dsp.focus({ window = \"address:${info_addr}\" })"
fi
