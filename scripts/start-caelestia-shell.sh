#!/usr/bin/env bash
# Sobe o caelestia shell com env Qt/NVIDIA.
# Uso: start-caelestia-shell.sh [--software]
#
# Evite --software no dia a dia: Qt Quick software não renderiza MultiEffect
# (workspaces com blur, vários painéis do Nexus/dashboard ficam vazios).
set -euo pipefail

SOFTWARE=0
[[ "${1:-}" == "--software" ]] && SOFTWARE=1

export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/nvidia_icd.json}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
export QT_WAYLAND_DISABLE_WINDOWDECORATION="${QT_WAYLAND_DISABLE_WINDOWDECORATION:-1}"
export QT_AUTO_SCREEN_SCALE_FACTOR="${QT_AUTO_SCREEN_SCALE_FACTOR:-1}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"

if [[ "$SOFTWARE" -eq 1 ]]; then
    export QT_QUICK_BACKEND=software
fi

exec caelestia shell -d
