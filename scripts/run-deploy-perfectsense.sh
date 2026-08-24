#!/usr/bin/env bash
# Deploy PerfectSense: perms + rebuild shell + overlays + reload
set -euo pipefail
cd /home/perfect/PandoraProject
export PANDORA_ROOT=/home/perfect/PandoraProject
export PANDORA_FORCE_REBUILD=1
LOG=/tmp/pandora-update/perfectsense-deploy.log
mkdir -p /tmp/pandora-update
exec > >(tee -a "$LOG") 2>&1

echo "=== PerfectSense deploy $(date) ==="
echo "Digite a senha do sudo se pedir."
# Remove sudoers quebrado antes de pedir senha
if [[ -f /etc/sudoers.d/pandora-perfectsense ]]; then
    sudo rm -f /etc/sudoers.d/pandora-perfectsense || true
fi
sudo -v
( while true; do sleep 50; sudo -n true 2>/dev/null || exit; done ) &
KEEP=$!
trap 'kill $KEEP 2>/dev/null || true' EXIT

bash scripts/setup-perfectsense-perms.sh
ln -sfn "$PANDORA_ROOT/scripts/perfectsense" "$HOME/.local/bin/perfectsense"

echo "=== rebuild shell (plugin + QML) ==="
bash install/30-caelestia-build.sh

echo "=== overlays + keybinds ==="
# shellcheck source=/dev/null
source install/lib.sh
deploy_overlays
if [[ -f /home/perfect/caelestia/hypr/hyprland/keybinds.lua ]]; then
    mkdir -p "$HOME/.config/hypr/hyprland"
    cp -f /home/perfect/caelestia/hypr/hyprland/keybinds.lua "$HOME/.config/hypr/hyprland/keybinds.lua"
    echo "keybinds.lua synced"
fi
if [[ -d "$HOME/.local/state/caelestia/dots/hypr/hyprland" ]]; then
    cp -f /home/perfect/caelestia/hypr/hyprland/keybinds.lua \
        "$HOME/.local/state/caelestia/dots/hypr/hyprland/keybinds.lua" 2>/dev/null || true
fi

echo "=== reload ==="
hyprctl reload 2>/dev/null || true
caelestia shell -k 2>/dev/null || true
sleep 1
caelestia shell -d >/dev/null 2>&1 || true
sleep 2

echo "=== smoke ==="
ls -la /etc/xdg/quickshell/caelestia/services/PerfectSense.qml \
       /etc/xdg/quickshell/caelestia/modules/dashboard/PerfectSense.qml
perfectsense status | head -c 500; echo
echo "EC=$(perfectsense mode get)"
rg -n 'screenshotFreezeClip|screenshotClip|PerfectSense|kbScreenshot' \
    "$HOME/.config/hypr/hyprland/keybinds.lua" \
    "$HOME/.config/caelestia/hypr-vars.lua" \
    /etc/xdg/quickshell/caelestia/modules/dashboard/Content.qml | head

echo
echo "CONCLUÍDO. Log: $LOG"
echo "Enter…"
read -r
