#!/usr/bin/env bash
# 70 — Apps: codecs, media, gaming, chat, VPN, ZapFast, Serein, Spotifast, etc.
#      (gerenciador de arquivos: módulo 55-strata — Dolphin não é mais instalado)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user

hydra_appimage_ready() {
  local img="$REAL_HOME/.local/opt/hydra/hydralauncher.AppImage"
  local bin="$REAL_HOME/.local/bin/hydralauncher"
  [[ -s "$img" && -x "$img" && -x "$bin" ]] || return 1
  bash -n "$bin" && grep -qF "exec \"$img\"" "$bin" || return 1
  as_user timeout 10 "$img" --appimage-version >/dev/null 2>&1
}

install_hydra_appimage() {
  resolve_user
  local dest="$REAL_HOME/.local/opt/hydra"
  local bin="$REAL_HOME/.local/bin/hydralauncher"
  if hydra_appimage_ready; then
    already_ok
    return 0
  fi
  as_user mkdir -p "$dest" "$REAL_HOME/.local/bin" || return 1
  local url
  url="$(curl -fsSL https://api.github.com/repos/hydralauncher/hydra/releases/latest \
    | jq -r '.assets[] | select(.name|test("AppImage$")) | .browser_download_url' | head -1)" || return 1
  [[ -n "$url" && "$url" != null ]] || return 1
  local img="$dest/hydralauncher.AppImage"
  local download
  download="$(as_user mktemp "$dest/.download-XXXXXX")" || return 1
  if ! as_user curl -fL "$url" -o "$download"; then
    rm -f -- "$download"
    return 1
  fi
  mv -- "$download" "$img" || return 1
  chmod +x "$img" || return 1
  chown "$REAL_UID:$REAL_GID" "$img" || return 1
  cat >"$bin" <<EOF || return 1
#!/usr/bin/env bash
exec "$img" "\$@"
EOF
  chmod +x "$bin" || return 1
  chown "$REAL_UID:$REAL_GID" "$bin" || return 1
  hydra_appimage_ready || return 1
  ok "Hydra AppImage → $bin"
}

# Replaced apps: ZapZap → zapfast-bin, Concord → Serein (fork, módulo 56-serein), Sung → spotifast-bin.

remove_legacy_apps() {
  # ZapZap/Concord/Sung were replaced; drop their installs (user data is kept).
  resolve_user
  local pkg
  for pkg in zapzap concord concord-bin; do
    if pkg_installed "$pkg"; then
      pacman -Rns --noconfirm "$pkg" || warn "remoção de $pkg falhou"
    fi
  done
  rm -f "$REAL_HOME/.cargo/bin/concord" "$REAL_HOME/.local/bin/concord" /usr/local/bin/concord /usr/local/bin/concord-nvidia
  if [[ -f "$BUILD_DIR/Sung/build/install_manifest.txt" ]]; then
    xargs -a "$BUILD_DIR/Sung/build/install_manifest.txt" rm -f 2>/dev/null || true
  fi
  rm -rf "$REAL_HOME/.local/lib/sung"
  rm -f "$REAL_HOME/.local/bin/sung" "$REAL_HOME/.local/share/applications/sung.desktop"
}

log "Codecs e apps de mídia/sistema"
pac_install \
  ffmpeg gst-libav gst-plugins-base gst-plugins-good \
  gst-plugins-bad gst-plugins-ugly \
  libdvdread libdvdnav \
  vlc \
  ark unzip 7zip unrar \
  firefox \
  steam \
  wine-staging winetricks \
  lib32-mesa lib32-vulkan-icd-loader
# steam-native-runtime is not always on the mirror; ignore if missing
pac_install steam-native-runtime || true

install_prefer libdvdcss || warn "libdvdcss indisponível (ok)"

install_prefer heroic-games-launcher-bin || warn "heroic falhou"
install_prefer stremio || warn "stremio falhou"
install_prefer blockbench-bin || warn "blockbench falhou"
install_prefer zapfast-bin || warn "zapfast-bin falhou"
install_prefer spotifast-bin || warn "spotifast-bin falhou"
install_prefer proton-vpn-gtk-app || install_prefer protonvpn-cli || warn "Proton VPN falhou"
install_prefer labymodlauncher-bin || warn "LabyMod falhou"
if hydra_appimage_ready; then
  already_ok
else
install_prefer hydra-launcher-bin || {
  warn "hydra-launcher-bin AUR falhou — tentando AppImage do GitHub"
  install_hydra_appimage || warn "Hydra AppImage falhou"
}

fi

remove_legacy_apps

ok "Apps instalados"
