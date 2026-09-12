#!/usr/bin/env bash
# 70 — Apps: codecs, media, gaming, chat, VPN, Sung, Concord, etc.
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

install_concord_from_git() {
  # Fork do usuário (upstream: chojs23/concord) — Discord TUI em Rust
  resolve_user
  local src="$BUILD_DIR/concord"
  if native_binary_ready "$src/target/release/concord"; then
    install_if_changed 755 "$src/target/release/concord" "$REAL_HOME/.cargo/bin/concord" || return 1
    chown "$REAL_UID:$REAL_GID" "$REAL_HOME/.cargo/bin/concord"
    return 0
  fi
  if [[ ! -d "$src/.git" ]]; then
    as_user git clone --depth=1 https://github.com/yPerfectBR/concord.git "$src" \
      || as_user git clone --depth=1 https://github.com/chojs23/concord.git "$src" \
      || return 1
  fi
  if [[ -f "$src/Cargo.toml" ]]; then
    pac_install alsa-lib pkgconf || return 1
    as_user bash -lc 'cd "$1" && cargo install --path . --locked' bash "$src" || return 1
    ok "Concord via cargo (yPerfectBR/concord)"
    return 0
  fi
  return 1
}

install_concord() {
  # Preferência: binário AUR estável → build do fork do usuário
  # NÃO usar aur/concord-git (é outra coisa: lib C Discord API)
  if pkg_installed concord || pkg_installed concord-bin || native_binary_ready "$REAL_HOME/.cargo/bin/concord"; then
    already_ok
  elif native_binary_ready "$BUILD_DIR/concord/target/release/concord"; then
    install_concord_from_git || return 1
  else
    install_prefer concord-bin \
      || install_prefer concord \
      || install_concord_from_git \
      || return 1
  fi
  if native_binary_ready "$REAL_HOME/.cargo/bin/concord" && ! command -v concord >/dev/null; then
    as_user mkdir -p "$REAL_HOME/.local/bin"
    as_user ln -sfn "$REAL_HOME/.cargo/bin/concord" "$REAL_HOME/.local/bin/concord"
  fi
  # Offload explícito (voice/stream na dGPU quando fizer sentido)
  install_if_changed 755 /dev/stdin /usr/local/bin/concord-nvidia <<'EOF' || return 1
#!/usr/bin/env bash
exec prime-run concord "$@"
EOF
  ok "Concord + concord-nvidia (prime-run)"
}

install_sung() {
  resolve_user
  if sung_ready; then
    already_ok
    return 0
  fi
  log "Validando/reparando instalação do Sung"
  pac_install \
    cmake ninja python nodejs ffmpeg \
    qt6-base qt6-declarative qt6-multimedia qt6-svg \
    qt6-wayland qt6-imageformats || return 1
  local src="$BUILD_DIR/Sung"
  if [[ ! -d "$src/.git" ]]; then
    as_user git clone --depth=1 "$SUNG_REPO_URL" "$src" || return 1
  fi
  if ! native_binary_ready "$src/build/sung" || [[ ! -s "$src/build/cmake_install.cmake" ]]; then
    as_user bash "$src/scripts/build.sh" || return 1
  else
    log "Reutilizando build validado do Sung"
  fi
  as_user cmake --install "$src/build" --prefix "$REAL_HOME/.local" || return 1
  as_user python3 -m venv "$REAL_HOME/.local/lib/sung/runtime" || return 1
  as_user "$REAL_HOME/.local/lib/sung/runtime/bin/python" -m pip install \
    --disable-pip-version-check -r "$REAL_HOME/.local/lib/sung/requirements.txt" || return 1
  sung_ready || return 1
  ok "Sung instalado em ~/.local/bin/sung"
}

log "Codecs e apps de mídia/sistema"
pac_install \
  ffmpeg gst-libav gst-plugins-base gst-plugins-good \
  gst-plugins-bad gst-plugins-ugly \
  libdvdread libdvdnav \
  vlc dolphin \
  ark unzip 7zip unrar \
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
if hydra_appimage_ready; then
  already_ok
else
install_prefer hydra-launcher-bin || {
  warn "hydra-launcher-bin AUR falhou — tentando AppImage do GitHub"
  install_hydra_appimage || warn "Hydra AppImage falhou"
}

fi

install_concord || warn "Concord falhou"

install_sung || warn "Sung falhou"

ok "Apps instalados"
