#!/usr/bin/env bash
# Workspace 1 — dashboard inferno (fastfetch, btop, cava, cmatrix, tty-clock).
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAVA_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/cava/config"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/pandora/dashboard-launched"

command -v hyprctl >/dev/null 2>&1 || exit 0
command -v foot >/dev/null 2>&1 || exit 0

if [[ -f "$STATE" ]]; then
    if hyprctl clients -j 2>/dev/null | jq -e \
        '.[] | select(.workspace.id == 1 and (.class | startswith("pandora-")))' >/dev/null 2>&1; then
        exit 0
    fi
    rm -f "$STATE"
fi

mkdir -p "$(dirname "$STATE")"
touch "$STATE"

launch() {
    hyprctl dispatch exec "[workspace 1 silent] $1" >/dev/null
    sleep 0.35
}

hyprctl dispatch workspace 1 >/dev/null

launch "env PANDORA_DASHBOARD=1 foot -a pandora-info -T pandora-info fish -C 'set -gx PANDORA_DASHBOARD 1; fastfetch; exec fish'"
launch "env PANDORA_DASHBOARD=1 foot -a pandora-btop -T pandora-btop fish -C 'set -x PANDORA_DASHBOARD 1; exec btop'"
launch "env PANDORA_DASHBOARD=1 foot -a pandora-cava -T pandora-cava fish -C 'set -x PANDORA_DASHBOARD 1; exec cava -p ${CAVA_CFG}'"
launch "env PANDORA_DASHBOARD=1 foot -a pandora-cmatrix -T pandora-cmatrix fish -C 'set -x PANDORA_DASHBOARD 1; exec cmatrix -C red -s'"
launch "env PANDORA_DASHBOARD=1 foot -a pandora-clock -T pandora-clock fish -C 'set -x PANDORA_DASHBOARD 1; exec tty-clock -c -C 1 -b -n'"

hyprctl dispatch workspace 1 >/dev/null
