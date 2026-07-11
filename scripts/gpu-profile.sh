#!/usr/bin/env bash
# Alterna variáveis de GPU: Intel em power-saver, NVIDIA nos demais perfis.
set -euo pipefail

ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/gpu-profile.env"
mkdir -p "$(dirname "$ENV_FILE")"

PROFILE="performance"
if command -v powerprofilesctl >/dev/null 2>&1; then
    PROFILE="$(powerprofilesctl get 2>/dev/null || echo performance)"
fi

if [[ "$PROFILE" == "power-saver" ]]; then
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

# Sincroniza perfil ACPI do nekro-sense quando disponível
if [[ -f /sys/firmware/acpi/platform_profile_choices ]]; then
    case "$PROFILE" in
        power-saver) acpi_profile="quiet" ;;
        balanced)    acpi_profile="balanced" ;;
        performance) acpi_profile="performance" ;;
        *)           acpi_profile="performance" ;;
    esac
    if grep -qw "$acpi_profile" /sys/firmware/acpi/platform_profile_choices 2>/dev/null; then
        echo "$acpi_profile" | sudo tee /sys/firmware/acpi/platform_profile >/dev/null 2>&1 || true
    fi
fi

# Recarrega Hyprland env se sessão ativa
if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
fi
