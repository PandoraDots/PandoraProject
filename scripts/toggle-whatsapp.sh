#!/usr/bin/env bash
# Alterna special:whatsapp e abre ZapZap se necessário.
set -euo pipefail

if ! command -v hyprctl >/dev/null 2>&1; then
    exec zapzap
fi

if ! hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.class == "zapzap")' >/dev/null; then
    hyprctl dispatch 'hl.dsp.exec_cmd("zapzap")' >/dev/null
fi

hyprctl dispatch 'hl.dsp.workspace.toggle_special("whatsapp")' >/dev/null
