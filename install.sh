#!/usr/bin/env bash
# PandoraProject — instalação completa do ecossistema Caelestia personalizado.
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PANDORA_ROOT

PANDORA_MODEL="phn16-72"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)
            PANDORA_MODEL="$2"
            shift 2
            ;;
        --model=*)
            PANDORA_MODEL="${1#*=}"
            shift
            ;;
        -h|--help)
            echo "Uso: $0 [--model phn16-72]"
            exit 0
            ;;
        *)
            echo "Argumento desconhecido: $1" >&2
            exit 1
            ;;
    esac
done
export PANDORA_MODEL

source "$PANDORA_ROOT/install/lib.sh"

pandora_helpers_reachable || die "Helpers do lib.sh não alcançam subshells (bash -c). Verifique install/lib.sh."

log "PandoraProject install — modelo: $PANDORA_MODEL"
log "Raiz: $PANDORA_ROOT"

chmod +x "$PANDORA_ROOT"/scripts/*.sh 2>/dev/null || true
chmod +x "$PANDORA_ROOT"/install/*.sh 2>/dev/null || true

steps=(
    "$PANDORA_ROOT/install/00-prereqs.sh"
    "$PANDORA_ROOT/install/10-session.sh"
    "$PANDORA_ROOT/install/15-apps.sh"
    "$PANDORA_ROOT/install/20-hardware.sh"
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

log "Instalação concluída. Reinicie a sessão para aplicar tudo."
log "Atualizações futuras: $PANDORA_ROOT/scripts/update.sh"
