#!/usr/bin/env bash
# Configura RGB, logo, ventoinhas e perfil de plataforma do nekro-sense.
set -euo pipefail

MODEL_FILE="${1:-}"
PANDORA_ROOT="${PANDORA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if [[ -z "$MODEL_FILE" || ! -f "$MODEL_FILE" ]]; then
    MODEL_FILE="$PANDORA_ROOT/models/phn16-72.json"
fi

NEKRO_DIR="${PANDORA_BUILD:-$HOME/.local/state/pandora/build}/nekro-sense"
if [[ ! -f "$NEKRO_DIR/tools/nekroctl.py" ]]; then
    NEKRO_DIR="$PANDORA_ROOT/../nekro-sense"
fi
if [[ ! -f "$NEKRO_DIR/tools/nekroctl.py" ]]; then
    printf 'nekro-setup: nekroctl não encontrado em %s\n' "$NEKRO_DIR" >&2
    exit 0
fi

NEKROCTL=(sudo python3 "$NEKRO_DIR/tools/nekroctl.py")

Z1="$(jq -r '.nekro_defaults.rgb_zones[0]' "$MODEL_FILE")"
Z2="$(jq -r '.nekro_defaults.rgb_zones[1]' "$MODEL_FILE")"
Z3="$(jq -r '.nekro_defaults.rgb_zones[2]' "$MODEL_FILE")"
Z4="$(jq -r '.nekro_defaults.rgb_zones[3]' "$MODEL_FILE")"
BRIGHT="$(jq -r '.nekro_defaults.rgb_brightness' "$MODEL_FILE")"
LOGO_COLOR="$(jq -r '.nekro_defaults.logo_color' "$MODEL_FILE")"
LOGO_BRIGHT="$(jq -r '.nekro_defaults.logo_brightness' "$MODEL_FILE")"
PROFILE="$(jq -r '.nekro_defaults.platform_profile' "$MODEL_FILE")"

"${NEKROCTL[@]}" fan auto 2>/dev/null || true
"${NEKROCTL[@]}" rgb per-zone "$Z1" "$Z2" "$Z3" "$Z4" -b "$BRIGHT" 2>/dev/null || true
"${NEKROCTL[@]}" logo set "$LOGO_COLOR" -b "$LOGO_BRIGHT" --on 2>/dev/null || true

if [[ -f /sys/firmware/acpi/platform_profile_choices ]]; then
    if grep -qw "$PROFILE" /sys/firmware/acpi/platform_profile_choices 2>/dev/null; then
        echo "$PROFILE" | sudo tee /sys/firmware/acpi/platform_profile >/dev/null 2>&1 || true
    fi
fi

powerprofilesctl set "$PROFILE" 2>/dev/null || true
