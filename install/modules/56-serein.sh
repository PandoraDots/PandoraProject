#!/usr/bin/env bash
# 56 — Serein (fork yPerfectBR/Serein): cliente Discord nativo com rota de rede configurável.
#   • compila do fork (cargo, 16 threads, prioridade máxima) e instala em /usr/local
#   • substitui o pacote `serein` (AUR/release) — o fork é um superconjunto do upstream
#   • instala serein-route / serein-probe e o serviço opcional serein-wireproxy
#   • instala o auxiliar serein-vpn (+ política polkit): Configurações → Rede → WireGuard reinicia
#     o Serein dentro de um namespace de rede com o túnel (gateway, voz e vídeo pelo mesmo IP)
# O fork acrescenta SEREIN_PROXY (SOCKS5/HTTP CONNECT) ao gateway, voz (sinalização), REST e CDN.
# Upstream: https://github.com/ViceVerse-cz/Serein
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user
resolve_stack_paths

SEREIN_SRC="${SEREIN_SRC:-$NOCTALIA_BASE_DIR/serein}"
SEREIN_PREFIX=/usr/local

log "Serein: dependências de execução e build"
SEREIN_DEPS=(
  rust cmake pkgconf git python desktop-file-utils
  alsa-lib dbus glib2 gst-plugin-pipewire gst-plugins-base gst-plugins-base-libs gst-plugins-good
  gstreamer gst-plugins-bad gst-plugin-va gtk4 hicolor-icon-theme libpulse libsoup3 libxkbcommon-x11 webkitgtk-6.0
  xdg-desktop-portal wireproxy wireguard-tools iproute2 polkit polkit-gnome python util-linux
)
pac_install "${SEREIN_DEPS[@]}"
# Dependências do pacote `serein` ficam marcadas como "instaladas como dependência": ao remover o
# pacote elas virariam órfãs e sairiam junto (foi assim que o webkitgtk-6.0 sumiu). O fork usa
# todas elas, então passam a ser explícitas.
pacman -D --asexplicit "${SEREIN_DEPS[@]}" >/dev/null 2>&1 || true

SEREIN_UPSTREAM_URL="${SEREIN_UPSTREAM_URL:-https://github.com/ViceVerse-cz/Serein.git}"

# O Serein compara a própria versão (Cargo.toml: sempre 0.1.0 nas fontes) com as releases nightly do
# upstream e, num build local, avisaria "atualização disponível" para sempre. Descobre a release mais
# recente cujo commit já está neste checkout e a informa ao build (SEREIN_BUILD_VERSION).
serein_build_version() {
  local json tag commit
  as_user git -C "$SEREIN_SRC" remote get-url upstream >/dev/null 2>&1 \
    || as_user git -C "$SEREIN_SRC" remote add upstream "$SEREIN_UPSTREAM_URL" >/dev/null 2>&1 || true
  as_user git -C "$SEREIN_SRC" fetch -q upstream >/dev/null 2>&1 || true
  json="$(curl -fsS --max-time 15 'https://api.github.com/repos/ViceVerse-cz/Serein/releases?per_page=30' 2>/dev/null)" || return 0
  while IFS=$'\t' read -r tag commit; do
    [[ -n "$tag" && -n "$commit" ]] || continue
    if as_user git -C "$SEREIN_SRC" merge-base --is-ancestor "$commit" HEAD 2>/dev/null; then
      printf '%s' "${tag#v}"
      return 0
    fi
  done < <(python3 -c 'import json,sys
for r in json.load(sys.stdin):
    print(r.get("tag_name",""), r.get("target_commitish",""), sep="\t")' <<<"$json" 2>/dev/null)
}

build_and_install_serein() {
  ensure_source_repo "$SEREIN_SRC" "$SEREIN_REPO_URL" || die "Falha ao obter o repositório do Serein"
  local head built exe="$SEREIN_SRC/target/release/serein" probe="$SEREIN_SRC/target/release/examples/probe"
  head="$(as_user git -C "$SEREIN_SRC" rev-parse --short HEAD)"
  local version stamp
  version="$(serein_build_version || true)"
  stamp="$head ${version:-unversioned}"
  built="$(cat "$SEREIN_SRC/target/.pandora-built-rev" 2>/dev/null || true)"
  if [[ ! -x "$exe" || ! -x "$probe" || "$built" != "$stamp" || "${PANDORA_REFRESH_STACK:-0}" == "1" ]]; then
    log "Compilando Serein ($head, versão ${version:-0.1.0}) com $(pandora_build_jobs) threads"
    # Thin LTO + 16 codegen units: bem mais rápido e leve em RAM que fat LTO (o crate final do
    # Serein passa de 7 GiB com fat LTO + 1 unidade); override por env, sem tocar no Cargo.toml.
    # shellcheck disable=SC2046
    as_user_fast env $(pandora_build_job_env) \
      ${version:+SEREIN_BUILD_VERSION="$version"} \
      SEREIN_UPDATE_HINT="sync the fork with upstream, then run: sudo $INSTALL_ROOT/install.sh 56-serein" \
      CARGO_PROFILE_RELEASE_LTO="${SEREIN_LTO:-thin}" \
      CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 \
      bash -c 'cd "$1" && cargo build --release --locked -p serein --no-default-features \
        && cargo build --release --locked -p net-route --example probe' bash "$SEREIN_SRC" \
      || die "Falha na compilação do Serein"
    printf '%s\n' "$stamp" | as_user tee "$SEREIN_SRC/target/.pandora-built-rev" >/dev/null
  else
    log "Serein $head já compilado — reutilizando os binários"
  fi

  # O fork substitui o pacote: o mesmo caminho em /usr não pode ficar com dono duplicado.
  local pkg
  for pkg in serein serein-git serein-bin; do
    if pkg_installed "$pkg"; then
      log "Removendo o pacote $pkg (substituído pelo fork)"
      # -Rn (sem -s): nunca arrasta dependências junto
      pacman -Rn --noconfirm "$pkg" || warn "remoção de $pkg falhou"
    fi
  done

  install_if_changed 755 "$exe" "$SEREIN_PREFIX/bin/serein" || die "Falha ao instalar o binário do Serein"
  install_if_changed 755 "$probe" "$SEREIN_PREFIX/bin/serein-probe"
  install_if_changed 644 "$SEREIN_SRC/packaging/linux/serein.desktop" \
    "$SEREIN_PREFIX/share/applications/cz.viceverse.serein.desktop"
  local icon rel
  while IFS= read -r -d '' icon; do
    rel="${icon#"$SEREIN_SRC/packaging/linux/hicolor/"}"
    install_if_changed 644 "$icon" "$SEREIN_PREFIX/share/icons/hicolor/$rel"
  done < <(find "$SEREIN_SRC/packaging/linux/hicolor" -type f -print0)
  install_if_changed 644 "$SEREIN_SRC/docs/network-route.md" "$SEREIN_PREFIX/share/doc/serein/network-route.md"
  install_if_changed 755 "$INSTALL_ROOT/assets/serein/serein-route" "$SEREIN_PREFIX/bin/serein-route"
  # Helper que roda o Serein inteiro (voz/vídeo incluídos) dentro de um namespace com WireGuard.
  # Só root o executa (pkexec/sudo); o comando final roda como o usuário que chamou.
  install -d -m 755 "$SEREIN_PREFIX/libexec"
  install_if_changed 755 "$SEREIN_SRC/packaging/linux/vpn/serein-vpn" "$SEREIN_PREFIX/libexec/serein-vpn"
  install_if_changed 644 "$SEREIN_SRC/packaging/linux/vpn/cz.viceverse.serein.vpn.policy" \
    /usr/share/polkit-1/actions/cz.viceverse.serein.vpn.policy
  update-desktop-database "$SEREIN_PREFIX/share/applications" 2>/dev/null || true
  gtk-update-icon-cache -q -t -f "$SEREIN_PREFIX/share/icons/hicolor" 2>/dev/null || true
  ok "Serein → $SEREIN_PREFIX/bin/serein (+ serein-probe, serein-route)"
}

install_wireproxy_unit() {
  # Serviço de usuário opcional: só inicia se ~/.config/serein/wireproxy.conf existir
  # (use `serein-route wireproxy <wg.conf>` para configurar e ativar).
  local unit_dir="$REAL_HOME/.config/systemd/user"
  as_user mkdir -p "$unit_dir"
  install_if_changed 644 "$INSTALL_ROOT/assets/serein/serein-wireproxy.service" "$unit_dir/serein-wireproxy.service"
  chown "$REAL_UID:$REAL_GID" "$unit_dir/serein-wireproxy.service"
  ok "serein-wireproxy.service instalado (inativo até o serein-route wireproxy)"
}

build_and_install_serein
install_wireproxy_unit
command -v /usr/local/bin/serein >/dev/null && ok "Serein (fork) instalado — reinicie o Serein para usar o novo binário"
warn "Rota de rede: 'serein-route status|set|off|test|wireproxy|vpn'. Proxy/VPN pode violar os Termos do Discord."
