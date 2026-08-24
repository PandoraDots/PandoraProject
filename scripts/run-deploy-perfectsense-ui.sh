#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-$HOME/shell}"
DEST=/etc/xdg/quickshell/caelestia
PANDORA_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

# Preferir script completo (inclui Battery/Displays/Wallpaper)
if [[ "$(id -u)" -eq 0 ]]; then
    PANDORA_SHELL="$SRC" "$PANDORA_ROOT/scripts/sync-shell-runtime.sh"
    exit 0
fi

echo "Abrindo autenticação para sync do shell…"
pkexec env PANDORA_SHELL="$SRC" "$PANDORA_ROOT/scripts/sync-shell-runtime.sh"
