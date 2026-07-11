#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODEL_FILE="$(model_config "$PANDORA_MODEL")"
log "Hardware: $PANDORA_MODEL ($MODEL_FILE)"

mapfile -t NVIDIA_PKGS < <(jq -r '.packages.nvidia[]' "$MODEL_FILE")
mapfile -t INTEL_PKGS < <(jq -r '.packages.intel[]' "$MODEL_FILE")
mapfile -t POWER_PKGS < <(jq -r '.packages.power[]' "$MODEL_FILE")
KERNEL_HEADERS="$(jq -r '.packages.kernel_headers' "$MODEL_FILE")"
NEKRO_REPO="$(jq -r '.packages.nekro.repo' "$MODEL_FILE")"
NEKRO_LLVM="$(jq -r '.packages.nekro.llvm' "$MODEL_FILE")"
NEKRO_SERVICE="$(jq -r '.packages.nekro.service' "$MODEL_FILE")"

run_step "Drivers NVIDIA + Intel" pacman_install "${NVIDIA_PKGS[@]}" "${INTEL_PKGS[@]}" "${POWER_PKGS[@]}" "$KERNEL_HEADERS"

run_step "nvidia-powerd" bash -c '
    sudo systemctl enable nvidia-powerd.service
    sudo systemctl start nvidia-powerd.service 2>/dev/null || true
'

run_step "power-profiles-daemon" bash -c '
    sudo systemctl enable power-profiles-daemon.service
    sudo systemctl start power-profiles-daemon.service 2>/dev/null || true
'

NEKRO_DIR="$PANDORA_BUILD/nekro-sense"
LOCAL_NEKRO="$PANDORA_ROOT/../nekro-sense"
if [[ -d "$LOCAL_NEKRO/.git" ]]; then
    NEKRO_DIR="$LOCAL_NEKRO"
fi

run_step "nekro-sense ($NEKRO_DIR)" bash -c "
    if [[ ! -d '$NEKRO_DIR/.git' ]]; then
        clone_or_pull '$NEKRO_REPO' '$NEKRO_DIR'
    fi
    cd '$NEKRO_DIR'
    if [[ '$NEKRO_LLVM' == 'true' ]]; then
        make LLVM=1
        sudo make LLVM=1 install
    else
        make
        sudo make install
    fi
    sudo systemctl enable '$NEKRO_SERVICE'
    sudo systemctl start '$NEKRO_SERVICE' 2>/dev/null || true
"

log "Hardware $PANDORA_MODEL configurado."
