#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

run_step "Verificação pós-instalação" bash "$PANDORA_ROOT/scripts/verify-install.sh" \
    --model "$PANDORA_MODEL" \
    --log-dir "${XDG_STATE_HOME:-$HOME/.local/state}/pandora" \
    || warn "Verificação encontrou falhas — veja verify-install-latest.log"

log "Relatório salvo em ${XDG_STATE_HOME:-$HOME/.local/state}/pandora/verify-install-latest.log"
