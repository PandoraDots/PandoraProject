#!/usr/bin/env bash
# 70 — Apps: codecs, media, gaming, chat, VPN, Sung, Concord, etc.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user

install_hydra_appimage() {
  resolve_user
  local dest="$REAL_HOME/.local/opt/hydra"
  local bin="$REAL_HOME/.local/bin/hydralauncher"
  as_user mkdir -p "$dest" "$REAL_HOME/.local/bin"
  local url
  url="$(curl -fsSL https://api.github.com/repos/hydralauncher/hydra/releases/latest \
    | jq -r '.assets[] | select(.name|test("AppImage$")) | .browser_download_url' | head -1)"
  [[ -n "$url" && "$url" != null ]] || return 1
  local img="$dest/hydralauncher.AppImage"
  as_user curl -fL "$url" -o "$img"
  chmod +x "$img"
  chown "$REAL_UID:$REAL_GID" "$img"
  cat >"$bin" <<EOF
#!/usr/bin/env bash
exec "$img" "\$@"
EOF
  chmod +x "$bin"
  chown "$REAL_UID:$REAL_GID" "$bin"
  ok "Hydra AppImage → $bin"
}

install_concord_from_git() {
  # Fork do usuário (upstream: chojs23/concord) — Discord TUI em Rust
  resolve_user
  local src="$BUILD_DIR/concord"
  rm -rf "$src"
  as_user git clone --depth=1 https://github.com/yPerfectBR/concord.git "$src" \
    || as_user git clone --depth=1 https://github.com/chojs23/concord.git "$src" \
    || return 1
  if [[ -f "$src/Cargo.toml" ]]; then
    pac_install alsa-lib pkgconf
    as_user bash -lc "cd '$src' && cargo install --path . --locked" || return 1
    ok "Concord via cargo (yPerfectBR/concord)"
    return 0
  fi
  return 1
}

install_concord() {
  # Preferência: binário AUR estável → build do fork do usuário
  # NÃO usar aur/concord-git (é outra coisa: lib C Discord API)
  if pkg_installed concord || pkg_installed concord-bin; then
    ok "Concord já instalado"
  else
    install_prefer concord-bin \
      || install_prefer concord \
      || install_concord_from_git \
      || return 1
  fi
  # Offload explícito (voice/stream na dGPU quando fizer sentido)
  install -Dm755 /dev/stdin /usr/local/bin/concord-nvidia <<'EOF'
#!/usr/bin/env bash
exec prime-run concord "$@"
EOF
  ok "Concord + concord-nvidia (prime-run)"
}

install_sung() {
  resolve_user
  if [[ -x "$REAL_HOME/.local/bin/sung" ]]; then
    ok "Sung já em ~/.local/bin/sung"
    return 0
  fi
  log "Compilando Sung (user install)"
  pac_install \
    cmake ninja python nodejs ffmpeg \
    qt6-base qt6-declarative qt6-multimedia qt6-svg \
    qt6-wayland qt6-imageformats
  local src="$BUILD_DIR/Sung"
  rm -rf "$src"
  as_user git clone --depth=1 "$SUNG_REPO_URL" "$src"
  as_user bash -lc "cd '$src' && ./scripts/install.sh"
  [[ -x "$REAL_HOME/.local/bin/sung" ]] || return 1
  ok "Sung instalado em ~/.local/bin/sung"
}

log "Codecs e apps de mídia/sistema"
pac_install \
  ffmpeg gst-libav gst-plugins-base gst-plugins-good \
  gst-plugins-bad gst-plugins-ugly \
  libdvdread libdvdnav \
  vlc dolphin \
  ark unzip p7zip unrar \
  firefox \
  steam \
  wine-staging winetricks \
  lib32-mesa lib32-vulkan-icd-loader
# steam-native-runtime nem sempre está no mirror; ignore se faltar
pac_install steam-native-runtime || true

install_prefer libdvdcss || warn "libdvdcss indisponível (ok)"

install_prefer heroic-games-launcher-bin || warn "heroic falhou"
install_prefer stremio || warn "stremio falhou"
install_prefer blockbench-bin || warn "blockbench falhou"
install_prefer zapzap || warn "zapzap falhou"
install_prefer proton-vpn-gtk-app || install_prefer protonvpn-cli || warn "Proton VPN falhou"
install_prefer labymodlauncher-bin || warn "LabyMod falhou"
install_prefer hydra-launcher-bin || {
  warn "hydra-launcher-bin AUR falhou — tentando AppImage do GitHub"
  install_hydra_appimage || warn "Hydra AppImage falhou"
}

install_concord || warn "Concord falhou"

install_sung || warn "Sung falhou"

ok "Apps instalados"
