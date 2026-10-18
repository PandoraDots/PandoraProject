#!/usr/bin/env bash
# 55 — Strata: gerenciador de arquivos padrão (fork yPerfectBR/strata) — substitui Dolphin & cia.
#   • compila do fork (cargo, 16 threads, prioridade alta) e instala em /usr/local
#   • define como padrão para pastas (xdg-mime), "Mostrar na pasta" (org.freedesktop.FileManager1)
#     e seletor de arquivos do portal (strata --install-portal)
# Upstream: https://github.com/lgse/strata  (o fork carrega as correções ainda não aceitas)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user
resolve_stack_paths

STRATA_SRC="${STRATA_SRC:-$NOCTALIA_BASE_DIR/strata}"
STRATA_DESKTOP_ID="io.github.lgse.Strata.desktop"
STRATA_PREFIX=/usr/local

log "Strata: dependências de execução e build"
pac_install \
  rust pkgconf base-devel \
  bubblewrap fontconfig gtk4 gtksourceview5 gvfs gvfs-smb poppler-glib \
  gstreamer gst-plugins-base gst-plugins-good gst-libav \
  ffmpeg ffmpegthumbnailer imagemagick xdg-utils desktop-file-utils

build_and_install_strata() {
  ensure_source_repo "$STRATA_SRC" "$STRATA_REPO_URL" || die "Falha ao obter o repositório do Strata"
  local bin="$STRATA_SRC/target/release/strata" head built
  head="$(as_user git -C "$STRATA_SRC" rev-parse --short HEAD)"
  built="$(cat "$STRATA_SRC/target/.pandora-built-rev" 2>/dev/null || true)"
  if [[ ! -x "$bin" || "$built" != "$head" || "${PANDORA_REFRESH_STACK:-0}" == "1" ]]; then
    log "Compilando Strata ($head) com $(pandora_build_jobs) threads"
    # Thin LTO + 16 codegen units: ~3x mais rápido que fat LTO, binário ~igual na prática.
    # shellcheck disable=SC2046
    as_user_fast env $(pandora_build_job_env) \
      CARGO_PROFILE_RELEASE_LTO="${STRATA_LTO:-thin}" \
      CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 \
      bash -c 'cd "$1" && cargo build --release --locked --bin strata' bash "$STRATA_SRC" \
      || die "Falha na compilação do Strata"
    printf '%s\n' "$head" | as_user tee "$STRATA_SRC/target/.pandora-built-rev" >/dev/null
  else
    log "Strata $head já compilado — reutilizando o binário"
  fi

  install_if_changed 755 "$bin" "$STRATA_PREFIX/bin/strata" || die "Falha ao instalar o binário do Strata"
  # Launcher: o .desktop do projeto usa "Exec=strata %U" (resolve via PATH).
  install_if_changed 644 "$STRATA_SRC/data/$STRATA_DESKTOP_ID" \
    "$STRATA_PREFIX/share/applications/$STRATA_DESKTOP_ID"
  install_if_changed 644 "$STRATA_SRC/data/icons/scalable/apps/io.github.lgse.Strata.svg" \
    "$STRATA_PREFIX/share/icons/hicolor/scalable/apps/io.github.lgse.Strata.svg"
  update-desktop-database "$STRATA_PREFIX/share/applications" 2>/dev/null || true
  gtk-update-icon-cache -q -t -f "$STRATA_PREFIX/share/icons/hicolor" 2>/dev/null || true
  ok "Strata → $STRATA_PREFIX/bin/strata"
}

user_bus_env() {
  # Sob sudo não há sessão de usuário: aponta para o barramento da sessão do usuário real.
  printf 'XDG_RUNTIME_DIR=/run/user/%s DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%s/bus' \
    "$REAL_UID" "$REAL_UID"
}

set_strata_default() {
  log "Strata como padrão: pastas, 'mostrar na pasta' (FileManager1) e seletor de arquivos"
  # 1) pastas → Strata (xdg-mime grava em ~/.config/mimeapps.list)
  # shellcheck disable=SC2046
  as_user env $(user_bus_env) xdg-mime default "$STRATA_DESKTOP_ID" \
    inode/directory application/x-gnome-saved-search
  # 2) org.freedesktop.FileManager1: o serviço do usuário vence o do Dolphin em /usr/share
  local svc_dir="$REAL_HOME/.local/share/dbus-1/services"
  as_user mkdir -p "$svc_dir"
  install_if_changed 644 /dev/stdin "$svc_dir/org.freedesktop.FileManager1.service" <<EOF
[D-BUS Service]
Name=org.freedesktop.FileManager1
Exec=$STRATA_PREFIX/bin/strata --gapplication-service
EOF
  chown "$REAL_UID:$REAL_GID" "$svc_dir/org.freedesktop.FileManager1.service"
  # 3) portal FileChooser por usuário (Firefox, Discord, etc. passam a abrir o seletor do Strata)
  # shellcheck disable=SC2046
  as_user env $(user_bus_env) "$STRATA_PREFIX/bin/strata" --install-portal \
    || warn "strata --install-portal falhou (rode dentro da sessão gráfica)"
  # shellcheck disable=SC2046
  as_user env $(user_bus_env) xdg-mime query default inode/directory | grep -qx "$STRATA_DESKTOP_ID" \
    && ok "inode/directory → Strata" || warn "inode/directory ainda não aponta para o Strata"
}

build_and_install_strata
set_strata_default
ok "Strata instalado e definido como gerenciador de arquivos padrão"
