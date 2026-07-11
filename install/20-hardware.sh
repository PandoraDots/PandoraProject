#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODEL_FILE="$(model_config "$PANDORA_MODEL")"
log "Hardware: $PANDORA_MODEL ($MODEL_FILE)"

NEKRO_REPO="$(jq -r '.packages.nekro.repo' "$MODEL_FILE")"
NEKRO_LLVM="$(jq -r '.packages.nekro.llvm' "$MODEL_FILE")"
NEKRO_SERVICE="$(jq -r '.packages.nekro.service' "$MODEL_FILE")"

if is_cachyos; then
    run_step "Drivers NVIDIA + Intel (CachyOS)" install_cachyos_gpu_drivers "$MODEL_FILE" \
        || die "Falha ao instalar drivers GPU (CachyOS)"
else
    mapfile -t NVIDIA_PKGS < <(jq -r '.packages.nvidia[]' "$MODEL_FILE")
    mapfile -t INTEL_PKGS < <(jq -r '.packages.intel[]' "$MODEL_FILE")
    mapfile -t POWER_PKGS < <(jq -r '.packages.power[]' "$MODEL_FILE")
    KERNEL_HEADERS="$(jq -r '.packages.kernel_headers' "$MODEL_FILE")"
    run_step "Drivers NVIDIA + Intel" pacman_install \
        "${NVIDIA_PKGS[@]}" "${INTEL_PKGS[@]}" "${POWER_PKGS[@]}" "$KERNEL_HEADERS"
fi

run_step "nvidia-powerd" bash -c '
    if systemctl list-unit-files nvidia-powerd.service &>/dev/null; then
        sudo systemctl enable nvidia-powerd.service 2>/dev/null || true
        sudo systemctl start nvidia-powerd.service 2>/dev/null || true
    else
        echo "nvidia-powerd.service não disponível (normal em VM ou sem NVIDIA)"
    fi
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

hardware_install_nekro() {
    if [[ ! -d "$NEKRO_DIR/.git" ]]; then
        clone_or_pull "$NEKRO_REPO" "$NEKRO_DIR"
    fi
    cd "$NEKRO_DIR"
    if [[ "$NEKRO_LLVM" == "true" ]]; then
        if ! make LLVM=1; then
            warn "nekro-sense: compilação falhou — pulando (hardware Predator pode ser necessário)"
            return 0
        fi
        if ! sudo make LLVM=1 install; then
            warn "nekro-sense: install falhou — pulando"
            return 0
        fi
    else
        if ! make; then
            warn "nekro-sense: compilação falhou — pulando"
            return 0
        fi
        if ! sudo make install; then
            warn "nekro-sense: install falhou — pulando"
            return 0
        fi
    fi
    sudo systemctl enable "$NEKRO_SERVICE" 2>/dev/null || warn "nekro-sense: enable do serviço falhou"
    sudo systemctl start "$NEKRO_SERVICE" 2>/dev/null || warn "nekro-sense: start do serviço falhou"
}

run_step "nekro-sense ($NEKRO_DIR)" hardware_install_nekro

log "Hardware $PANDORA_MODEL configurado."
