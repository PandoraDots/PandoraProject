#!/usr/bin/env bash
# Alterna special:whatsapp e abre ZapZap (tema Pandora) se necessário.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZAPZAP_BIN="$ROOT/scripts/zapzap-pandora"
[[ -x "$ZAPZAP_BIN" ]] || ZAPZAP_BIN="$(command -v zapzap || true)"

if ! command -v hyprctl >/dev/null 2>&1; then
    exec "$ZAPZAP_BIN"
fi

if ! hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.class == "zapzap")' >/dev/null; then
    hyprctl dispatch "hl.dsp.exec_cmd(\"$ZAPZAP_BIN\")" >/dev/null
fi

hyprctl dispatch 'hl.dsp.workspace.toggle_special("whatsapp")' >/dev/null
