#!/usr/bin/env bash
set -euo pipefail
cd /home/perfect/PandoraProject
mkdir -p /tmp/pandora-update
echo "=== Pandora system-update ==="
echo "Atualiza: pacotes (kernel 7.2, mesa, qt…) + forks Caelestia + ZapZap/overlays"
echo "Pode pedir senha do sudo. Demora vários minutos."
echo
sudo -v
./scripts/system-update.sh --noconfirm 2>&1 | tee /tmp/pandora-update/system-update.log
echo
echo "EXIT=${PIPESTATUS[0]}"
echo "Log: /tmp/pandora-update/system-update.log"
echo "Pressione Enter para fechar…"
read -r
