#!/usr/bin/env bash
# Pós-hook do Caelestia: Waywallen + sync do tema SDDM Caelestia.
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$PANDORA_ROOT/scripts/waywallen-bridge.sh" "$@" || true

SDDM_SYNC="/usr/share/sddm/themes/caelestia/scripts/sync.sh"
if [[ -x "$SDDM_SYNC" ]]; then
    sudo "$SDDM_SYNC" --posthook 2>/dev/null || true
fi
