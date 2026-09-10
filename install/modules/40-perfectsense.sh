#!/usr/bin/env bash
# 40 — PerfectSense (clone + makepkg from packaging/arch)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user

if pkg_installed perfectsense; then
  ok "perfectsense já instalado"
  systemd_enable perfectsensed.service || true
  exit 0
fi

log "Instalando PerfectSense a partir do GitHub"
pac_install dkms meson ninja systemd linux-zen-headers

src="$BUILD_DIR/PerfectSense"
rm -rf "$src"
as_user git clone --depth=1 "$PS_REPO_URL" "$src"

# Build as user with PERFECTSENSE_SRC
(
  cd "$src/packaging/arch"
  as_user env PERFECTSENSE_SRC="$src" makepkg -f --noconfirm --syncdeps
)

pkg="$(ls -1t "$src/packaging/arch"/perfectsense-*.pkg.tar.* 2>/dev/null | head -1 || true)"
[[ -n "$pkg" ]] || die "PKG PerfectSense não gerado"
pacman -U --noconfirm "$pkg"

# DKMS rebuild for zen if needed
if command -v dkms >/dev/null; then
  dkms autoinstall -k "$(uname -r)" 2>/dev/null || true
  # Prefer zen if booted on something else
  zen_kver="$(pacman -Q linux-zen 2>/dev/null | awk '{print $2}' | sed 's/-.*//;s/\.zen/.zen/' || true)"
  # Better: find installed zen modules dir
  for k in /usr/lib/modules/*-zen*/build; do
    [[ -e "$k" ]] || continue
    kv="$(basename "$(dirname "$k")")"
    dkms autoinstall -k "$kv" 2>/dev/null || warn "DKMS autoinstall $kv falhou"
  done
fi

systemd_enable perfectsensed.service || true
ok "PerfectSense instalado"
