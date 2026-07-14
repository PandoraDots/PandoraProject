#!/usr/bin/env bash
# Orion Launcher (OrionBE) — sempre a release mais recente do GitHub.
# https://github.com/OrionBedrock/OrionLauncher
set -euo pipefail
PANDORA_ROOT="${PANDORA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export PANDORA_ROOT
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ORION_REPO="${ORION_REPO:-OrionBedrock/OrionLauncher}"

install_orion_runtime_deps() {
    # XVDTool (criação/atualização de instâncias Bedrock) precisa do runtime .NET 8.
    if pacman -Qi dotnet-runtime-8.0 &>/dev/null; then
        log "Já instalado: dotnet-runtime-8.0"
        return 0
    fi
    pacman_install dotnet-runtime-8.0 || warn "dotnet-runtime-8.0 falhou — Orion pode falhar em CIK/XVDTool"
}

run_step "Orion runtime (.NET 8)" install_orion_runtime_deps
run_step "Orion Launcher AppImage (latest GitHub)" install_orion_binary
run_step "Orion no launcher Caelestia (.desktop XDG)" install_orion_launcher

log "Orion Launcher pronto (release mais recente de $ORION_REPO)."
