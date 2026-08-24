#!/usr/bin/env bash
# Continua o update após Syu (qs já rebuildado). Precisa de sudo interativo.
set -euo pipefail
cd /home/perfect/PandoraProject
mkdir -p /tmp/pandora-update
LOG=/tmp/pandora-update/system-update-continue.log
exec > >(tee -a "$LOG") 2>&1

echo "=== Continuar Pandora update ==="
echo "1) nekro_sense p/ kernels instalados"
echo "2) merge forks Caelestia + rebuild shell/cli"
echo "3) overlays + ZapZap + verify"
echo
sudo -v

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
        echo "instalado (próximo boot): $mdir/nekro_sense.ko"
    fi
done
sudo systemctl enable --now nekro_sense.service 2>/dev/null || true

# pwvucontrol (Caelestia dots novos)
if ! pacman -Q pwvucontrol &>/dev/null; then
    sudo pacman -S --noconfirm --needed pwvucontrol || true
fi

echo
echo "=== Pandora forks + shell ==="
./scripts/system-update.sh --noconfirm --skip-system

echo
echo "EXIT=0"
echo "Log: $LOG"
echo "Reinicie (kernel 7.2 + nekro). Pressione Enter…"
read -r
