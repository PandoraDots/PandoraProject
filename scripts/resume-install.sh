#!/usr/bin/env bash
# Retoma instalação PandoraProject a partir do passo 30 (após falha em build/cli).
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PANDORA_ROOT
export PANDORA_MODEL="${PANDORA_MODEL:-phn16-72}"

source "$PANDORA_ROOT/install/lib.sh"

log "Retomando instalação Pandora — modelo: $PANDORA_MODEL"

steps=(
    "$PANDORA_ROOT/install/30-caelestia-build.sh"
    "$PANDORA_ROOT/install/40-caelestia-install.sh"
    "$PANDORA_ROOT/install/50-waywallen.sh"
    "$PANDORA_ROOT/install/90-postinstall.sh"
    "$PANDORA_ROOT/install/99-verify.sh"
)

for step in "${steps[@]}"; do
    [[ -x "$step" ]] || chmod +x "$step"
    bash "$step"
done

log "Retomada concluída. Veja ~/.local/state/pandora/verify-install-latest.log"
