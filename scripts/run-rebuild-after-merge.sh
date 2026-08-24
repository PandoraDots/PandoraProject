#!/usr/bin/env bash
# Rebuild + install após merges (precisa sudo).
set -euo pipefail
cd /home/perfect/PandoraProject
mkdir -p /tmp/pandora-update
LOG=/tmp/pandora-update/rebuild-after-merge.log
exec > >(tee -a "$LOG") 2>&1

echo "=============================================="
echo " Digite a senha do sudo (Cursor NÃO vê a senha)"
echo " Depois: nekro → rebuild cli/shell → overlays"
echo "=============================================="
echo
# Keep sudo ticket alive during long builds
sudo -v
( while true; do sleep 60; sudo -n true 2>/dev/null || exit; done ) &
SUDO_KEEP=$!
trap 'kill $SUDO_KEEP 2>/dev/null || true' EXIT

NEKRO=/home/perfect/nekro-sense
for headers in /lib/modules/*/build; do
    [[ -d "$headers" ]] || continue
    k="$(basename "$(dirname "$headers")")"
    mdir="/lib/modules/$k/kernel/drivers/platform/x86"
    echo "--- nekro → $k ---"
    make -C "$NEKRO" LLVM=1 KVER="$k" clean all
    if [[ "$k" == "$(uname -r)" ]]; then
        (cd "$NEKRO" && sudo make LLVM=1 KVER="$k" install)
    else
        sudo install -d "$mdir"
        sudo install -m 644 "$NEKRO/src/nekro_sense.ko" "$mdir/nekro_sense.ko"
        sudo depmod -a "$k"
    fi
done
sudo systemctl enable --now nekro_sense.service 2>/dev/null || true

if ! pacman -Q pwvucontrol &>/dev/null; then
    sudo pacman -S --noconfirm --needed pwvucontrol || true
fi

echo "=== rebuild cli/shell (force) ==="
export PANDORA_FORCE_REBUILD=1
bash install/30-caelestia-build.sh

echo "=== overlays + zapzap + dots ==="
export PANDORA_ROOT="/home/perfect/PandoraProject"
# shellcheck source=/dev/null
source "$PANDORA_ROOT/install/lib.sh"
deploy_overlays
deploy_zapzap_theme
if command -v caelestia >/dev/null; then
    caelestia update --noconfirm --aur-helper paru || true
    caelestia scheme set -n inferno -f default -m dark || true
fi

echo "=== verify ==="
bash "$PANDORA_ROOT/scripts/verify-install.sh" --model phn16-72 || true

echo
echo "CONCLUÍDO. Shell novo já instalado; se a UI estiver estranha: caelestia shell -k && caelestia shell -d"
echo "Log: $LOG"
echo "Enter para fechar…"
read -r
