#!/usr/bin/env bash
# Sincroniza QML Pandora do fork shell → /etc/xdg/quickshell/caelestia e reinicia o qs.
# Uso: sync-shell-runtime.sh [--no-restart]
set -euo pipefail

SRC="${PANDORA_SHELL:-$HOME/shell}"
DEST=/etc/xdg/quickshell/caelestia
RESTART=1
[[ "${1:-}" == "--no-restart" ]] && RESTART=0

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Precisa de root (sudo/pkexec)." >&2
    exit 1
fi

[[ -d "$SRC" ]] || { echo "fork shell ausente: $SRC" >&2; exit 1; }
[[ -d "$DEST" ]] || { echo "dest ausente: $DEST" >&2; exit 1; }

files=(
    services/PerfectSense.qml
    services/Displays.qml
    services/GameMode.qml
    modules/ServiceLoader.qml
    modules/dashboard/PerfectSense.qml
    modules/dashboard/Content.qml
    modules/bar/popouts/Battery.qml
    modules/bar/components/status/BatteryStatus.qml
    modules/nexus/pages/PerfectSensePage.qml
    modules/nexus/pages/DisplayPage.qml
    modules/nexus/pages/display/DisplayDetailPage.qml
    modules/nexus/pages/panels/DashboardPanel.qml
    modules/nexus/NexusState.qml
    modules/nexus/PageRegistry.qml
    modules/nexus/PageCompRegistry.qml
    modules/background/Wallpaper.qml
)

copied=0
for f in "${files[@]}"; do
    [[ -f "$SRC/$f" ]] || continue
    mkdir -p "$(dirname "$DEST/$f")"
    if [[ ! -f "$DEST/$f" ]] || ! cmp -s "$SRC/$f" "$DEST/$f"; then
        cp -f "$SRC/$f" "$DEST/$f"
        echo "sync $f"
        copied=$((copied + 1))
    fi
done

# Overlay Wallpaper NVIDIA-safe (se fork não tiver o patch)
overlay_wall="$HOME/PandoraProject/overlays/quickshell/modules/background/Wallpaper.qml"
if [[ -f "$overlay_wall" ]]; then
    mkdir -p "$DEST/modules/background"
    if ! cmp -s "$overlay_wall" "$DEST/modules/background/Wallpaper.qml" 2>/dev/null; then
        # só sobrescreve se o fork não trouxe um mais novo com o mesmo patch
        if ! grep -q 'file://' "$DEST/modules/background/Wallpaper.qml" 2>/dev/null; then
            cp -f "$overlay_wall" "$DEST/modules/background/Wallpaper.qml"
            echo "sync Wallpaper.qml (overlay)"
            copied=$((copied + 1))
        fi
    fi
fi

echo "synced_files=$copied"

if [[ "$RESTART" -eq 1 ]]; then
    local_user="${SUDO_USER:-perfect}"
    local_uid="$(id -u "$local_user")"
    runtime="/run/user/${local_uid}"
    # Preserva Wayland/Hypr da sessão (runuser limpo quebra qs)
    hypr_sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
    if [[ -z "$hypr_sig" && -d "${runtime}/hypr" ]]; then
        hypr_sig="$(find "${runtime}/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | head -n1 || true)"
    fi
    runuser -u "$local_user" -- env \
        XDG_RUNTIME_DIR="$runtime" \
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" \
        DISPLAY="${DISPLAY:-:0}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime}/bus" \
        HYPRLAND_INSTANCE_SIGNATURE="$hypr_sig" \
        __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}" \
        QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}" \
        QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
        bash -lc 'qs -c caelestia kill 2>/dev/null || true; sleep 0.2; "$HOME/PandoraProject/scripts/start-caelestia-shell.sh"' \
        || true
    echo "shell restarted"
fi
