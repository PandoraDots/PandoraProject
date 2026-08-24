#!/usr/bin/env bash
# Alterna variáveis de GPU conforme perfil de energia.
# Sem hyprctl reload (causava loop preto no login com o path unit).
set -euo pipefail

ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/gpu-profile.env"
mkdir -p "$(dirname "$ENV_FILE")"

PROFILE="performance"
if command -v powerprofilesctl >/dev/null 2>&1; then
    PROFILE="$(powerprofilesctl get 2>/dev/null || echo performance)"
fi

# Só-NVIDIA (sem card0/iGPU): não injeta PRIME offload no compositor
nvidia_only=0
if [[ -e /dev/dri/card1 && ! -e /dev/dri/card0 ]]; then
    nvidia_only=1
fi

if [[ "$nvidia_only" -eq 1 ]]; then
    cat >"$ENV_FILE" <<'EOF'
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
EOF
elif [[ "$PROFILE" == "power-saver" ]]; then
    cat >"$ENV_FILE" <<'EOF'
export __NV_PRIME_RENDER_OFFLOAD=0
export __GLX_VENDOR_LIBRARY_NAME=mesa
export DRI_PRIME=0
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.x86_64.json
EOF
else
    cat >"$ENV_FILE" <<'EOF'
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export DRI_PRIME=1
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
EOF
fi

# Sincroniza perfil ACPI do nekro-sense quando disponível (só se mudou).
# PerfectSense é a fonte de verdade dos 5 modos EC.
# Eco (low-power) e Quiet mapeiam ambos para PPD power-saver — NÃO colapsar Eco→Quiet.
if [[ "${PANDORA_PERFECTSENSE:-0}" != "1" ]] \
    && [[ -f /sys/firmware/acpi/platform_profile_choices && -f /sys/firmware/acpi/platform_profile ]]; then
    current="$(tr -d '[:space:]' </sys/firmware/acpi/platform_profile 2>/dev/null || true)"
    state_ec=""
    state_file="${XDG_STATE_HOME:-$HOME/.local/state}/pandora/perfectsense.json"
    if [[ -f "$state_file" ]]; then
        state_ec="$(jq -r '.ec // empty' "$state_file" 2>/dev/null || true)"
    fi
    case "$PROFILE" in
        power-saver)
            # Preservar Eco/Quiet já ativos; senão preferir o último EC salvo
            if [[ "$current" == "low-power" || "$current" == "quiet" ]]; then
                acpi_profile="$current"
            elif [[ "$state_ec" == "low-power" || "$state_ec" == "quiet" ]]; then
                acpi_profile="$state_ec"
            else
                acpi_profile="quiet"
            fi
            ;;
        balanced)    acpi_profile="balanced" ;;
        performance) acpi_profile="performance" ;;
        *)           acpi_profile="performance" ;;
    esac
    if [[ "$current" != "$acpi_profile" ]] \
        && grep -qw "$acpi_profile" /sys/firmware/acpi/platform_profile_choices 2>/dev/null; then
        if [[ -w /sys/firmware/acpi/platform_profile ]]; then
            printf '%s\n' "$acpi_profile" >/sys/firmware/acpi/platform_profile 2>/dev/null || true
        else
            printf '%s\n' "$acpi_profile" | sudo -n tee /sys/firmware/acpi/platform_profile >/dev/null 2>&1 || true
        fi
    fi
fi

# Não recarrega Hyprland aqui — reload no login causa tela preta em loop.
