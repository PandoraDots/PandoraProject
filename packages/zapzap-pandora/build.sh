#!/usr/bin/env bash
# Build and install zapzap-pandora (upstream ZapZap + Inferno patches).
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKGDIR="$PANDORA_ROOT/packages/zapzap-pandora"
export PANDORA_ROOT

cd "$PKGDIR"

# Sync desktop nogpu from cache if missing
if [[ ! -f com.rtosta.zapzap.nogpu.desktop ]]; then
  if [[ -f "$HOME/.cache/paru/clone/zapzap/com.rtosta.zapzap.nogpu.desktop" ]]; then
    cp "$HOME/.cache/paru/clone/zapzap/com.rtosta.zapzap.nogpu.desktop" .
  else
    cat >com.rtosta.zapzap.nogpu.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Name=ZapZapNoGpu
Comment=WhatsApp Desktop for Linux NoGpu
Exec=env QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu" zapzap %u
Icon=com.rtosta.zapzap
Type=Application
Categories=Chat;Network;InstantMessaging;Qt;
StartupWMClass=zapzap
Terminal=false
EOF
  fi
fi

cp -f patches/0001-inferno-palette.patch 0001-inferno-palette.patch
cp -f patches/0002-default-dark-theme.patch 0002-default-dark-theme.patch

echo "==> makepkg zapzap-pandora"
makepkg -sf --noconfirm

pkgfile=$(ls -1t zapzap-pandora-*.pkg.tar.* 2>/dev/null | head -1)
[[ -n "$pkgfile" ]] || { echo "pacote não gerado" >&2; exit 1; }

echo "==> instalando $pkgfile"
# Substitui zapzap AUR/community (conflicts+replaces; --noconfirm sozinho responde N no conflito)
if pacman -Q zapzap &>/dev/null && ! pacman -Q zapzap-pandora &>/dev/null; then
  sudo pacman -R --noconfirm zapzap || true
fi
sudo pacman -U --noconfirm "$pkgfile"

# Redeploy WA Web Inferno CSS/JS into user data
# shellcheck source=/dev/null
source "$PANDORA_ROOT/install/lib.sh"
deploy_zapzap_theme

echo "OK — zapzap-pandora instalado + tema Inferno aplicado"
echo "Feche e reabra o ZapZap para carregar o CSS."
