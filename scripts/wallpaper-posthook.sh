#!/usr/bin/env bash
# Pós-hook do Caelestia: sync state + SDDM (sem reaplicar wallpaper — evita loop).
set -euo pipefail

# Evita recursão: bridge pode chamar `caelestia wallpaper`, que dispara este hook.
if [[ -n "${PANDORA_SKIP_WALLPAPER_POSTHOOK:-}" ]]; then
    exit 0
fi

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$PANDORA_ROOT/scripts/waywallen-bridge.sh" "$@" || true

SDDM_SYNC="/usr/share/sddm/themes/caelestia/scripts/sync.sh"
if [[ -x "$SDDM_SYNC" ]]; then
    sudo "$SDDM_SYNC" --posthook 2>/dev/null || true
fi
