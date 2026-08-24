#!/usr/bin/env bash
# Sync Monitors settings QML into the installed caelestia shell (needs sudo once).
set -euo pipefail
SRC="${1:-$HOME/shell}"
DEST=/etc/xdg/quickshell/caelestia

sudo mkdir -p "$DEST/modules/nexus/pages/display"
sudo cp -f "$SRC/services/Displays.qml" "$DEST/services/Displays.qml"
sudo cp -f "$SRC/modules/ServiceLoader.qml" "$DEST/modules/ServiceLoader.qml"
sudo cp -f "$SRC/modules/nexus/PageRegistry.qml" "$DEST/modules/nexus/PageRegistry.qml"
sudo cp -f "$SRC/modules/nexus/PageCompRegistry.qml" "$DEST/modules/nexus/PageCompRegistry.qml"
sudo cp -f "$SRC/modules/nexus/NexusState.qml" "$DEST/modules/nexus/NexusState.qml"
sudo cp -f "$SRC/modules/nexus/pages/DisplayPage.qml" "$DEST/modules/nexus/pages/DisplayPage.qml"
sudo cp -f "$SRC/modules/nexus/pages/display/DisplayDetailPage.qml" "$DEST/modules/nexus/pages/display/DisplayDetailPage.qml"

echo "OK — Monitors settings synced to $DEST"
# Prefer installed config again
pkill -x qs 2>/dev/null || true
pkill -f '/usr/bin/qs|/usr/bin/quickshell' 2>/dev/null || true
sleep 1
caelestia shell -d
sleep 2
echo "Shell restarted. Enter para fechar."
read -r
