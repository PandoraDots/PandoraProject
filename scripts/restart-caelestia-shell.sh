#!/usr/bin/env bash
# Reinicia o Quickshell Caelestia e avisa se o fork divergiu do instalado.
set -euo pipefail

SRC="${PANDORA_SHELL:-$HOME/shell}"
DEST=/etc/xdg/quickshell/caelestia
PANDORA_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

drift=()
for f in \
    services/PerfectSense.qml \
    modules/dashboard/PerfectSense.qml \
    modules/bar/popouts/Battery.qml \
    modules/nexus/pages/PerfectSensePage.qml \
    modules/nexus/pages/display/DisplayDetailPage.qml
do
    [[ -f "$SRC/$f" && -f "$DEST/$f" ]] || continue
    if ! cmp -s "$SRC/$f" "$DEST/$f"; then
        drift+=("$f")
    fi
done

qs -c caelestia kill 2>/dev/null || true
sleep 0.2
# Env NVIDIA (restart “nu” quebra EGL/RHI neste laptop)
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/nvidia_icd.json}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
export QT_WAYLAND_DISABLE_WINDOWDECORATION="${QT_WAYLAND_DISABLE_WINDOWDECORATION:-1}"
export QT_AUTO_SCREEN_SCALE_FACTOR="${QT_AUTO_SCREEN_SCALE_FACTOR:-1}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
caelestia shell -d

if ((${#drift[@]})); then
    msg="Fork shell à frente de /etc/xdg (${#drift[@]} arquivo(s)). Rode: $PANDORA_ROOT/scripts/run-deploy-perfectsense-ui.sh"
    notify-send -a Pandora -u normal "Shell restart" "$msg" 2>/dev/null || true
    echo "$msg" >&2
fi
