#!/usr/bin/env bash
# 10 — System tuning: pacman, makepkg, zram, timers, bash, fonts, IPv4
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user

if grep -qx 'Color' /etc/pacman.conf && grep -qx 'ILoveCandy' /etc/pacman.conf; then
  already_ok
else
  log "Ajustando /etc/pacman.conf (Color + ILoveCandy)"
  configure_pacman_ui
fi

# MAKEFLAGS / ParallelDownloads: full machine during install (00-preflight),
# steady -j6 / Downloads=8 applied in 80-finalize after all builds.

log "zram via systemd-zram-generator"
pac_install zram-generator
if cmp -s "$INSTALL_ROOT/config/zram-generator.conf" /etc/systemd/zram-generator.conf; then
  already_ok
else
  install_if_changed 644 "$INSTALL_ROOT/config/zram-generator.conf" /etc/systemd/zram-generator.conf
  systemctl daemon-reload
fi
systemd_enable systemd-zram-setup@zram0.service || true
# generator creates the unit at boot; force it now if possible
if ! systemctl is-active --quiet systemd-zram-setup@zram0.service; then
  systemctl start /dev/zram0 2>/dev/null || true
fi

log "Memória: sysctl p/ zram + earlyoom (protege a sessão contra thrashing)"
install_if_changed 644 "$INSTALL_ROOT/assets/sysctl/99-pandora-memory.conf" /etc/sysctl.d/99-pandora-memory.conf
sysctl --system >/dev/null 2>&1 || warn "sysctl --system falhou"
pac_install earlyoom
install_if_changed 644 "$INSTALL_ROOT/assets/earlyoom/earlyoom.default" /etc/default/earlyoom
systemd_enable earlyoom.service
systemctl restart earlyoom.service 2>/dev/null || true
# earlyoom substitui o systemd-oomd (ambos ativos disputariam vítimas)
systemctl disable --now systemd-oomd.service 2>/dev/null || true

log "Builds: 16 threads + prioridade máxima (pandora-fast, limits, cargo, environment.d)"
# pandora-fast: 16 jobs, CPUWeight máximo (scope próprio), I/O classe 0, nice -10, perfil "performance"
install_if_changed 755 "$INSTALL_ROOT/assets/build/pandora-fast" /usr/local/bin/pandora-fast
install_if_changed 644 "$INSTALL_ROOT/assets/build/fast-aliases.sh" /usr/local/share/pandora/fast-aliases.sh
# wheel pode subir a própria prioridade (nice -15); vale a partir do próximo login
install_if_changed 644 "$INSTALL_ROOT/assets/build/limits-pandora-build.conf" /etc/security/limits.d/60-pandora-build.conf
# variáveis de build para tudo que nasce na sessão do usuário (e para serviços systemd --user)
as_user mkdir -p "$REAL_HOME/.config/environment.d" "$REAL_HOME/.cargo"
install_if_changed 644 "$INSTALL_ROOT/assets/build/80-pandora-build.conf" "$REAL_HOME/.config/environment.d/80-pandora-build.conf"
chown "$REAL_UID:$REAL_GID" "$REAL_HOME/.config/environment.d/80-pandora-build.conf"
# cargo: jobs globais, sem sobrescrever um [build] jobs que o usuário já tenha
if [[ ! -f "$REAL_HOME/.cargo/config.toml" ]]; then
  install_if_changed 644 "$INSTALL_ROOT/assets/build/cargo-config.toml" "$REAL_HOME/.cargo/config.toml"
  chown "$REAL_UID:$REAL_GID" "$REAL_HOME/.cargo/config.toml"
elif ! grep -qE '^[[:space:]]*jobs[[:space:]]*=' "$REAL_HOME/.cargo/config.toml"; then
  if grep -qE '^\[build\]' "$REAL_HOME/.cargo/config.toml"; then
    sed -i '/^\[build\]/a jobs = 16' "$REAL_HOME/.cargo/config.toml"
  else
    printf '\n[build]\njobs = 16\n' >>"$REAL_HOME/.cargo/config.toml"
  fi
  chown "$REAL_UID:$REAL_GID" "$REAL_HOME/.cargo/config.toml"
fi
# shell interativo: cargo/make/ninja/meson/cmake/makepkg/paru/yay passam por pandora-fast
if ! grep -q 'fast-aliases.sh' "$REAL_HOME/.bashrc" 2>/dev/null; then
  printf '\n# Pandora: builds com 16 jobs e prioridade máxima\n[ -r /usr/local/share/pandora/fast-aliases.sh ] && . /usr/local/share/pandora/fast-aliases.sh\n' >>"$REAL_HOME/.bashrc"
  chown "$REAL_UID:$REAL_GID" "$REAL_HOME/.bashrc"
fi

log "Timers: fstrim + paccache"
pac_install pacman-contrib
systemd_enable fstrim.timer paccache.timer

if grep -qE '^precedence ::ffff:0:0/96[[:space:]]+100' /etc/gai.conf; then
  already_ok
else
log "Preferência IPv4 em /etc/gai.conf"
backup_file /etc/gai.conf
if [[ -f /etc/gai.conf ]]; then
  sed -i 's/^#precedence ::ffff:0:0\/96  100$/precedence ::ffff:0:0\/96  100/' /etc/gai.conf
  grep -qE '^precedence ::ffff:0:0/96' /etc/gai.conf \
    || printf '\nprecedence ::ffff:0:0/96  100\n' >>/etc/gai.conf
fi

fi

log "Bash: history-search com setas ↑/↓"
# Global inputrc + user
write_if_changed /etc/inputrc.d/pandora-history.inputrc \
$'# Pandora Noctalia\n"\\e[A": history-search-backward\n"\\e[B": history-search-forward\n'
# Arch inputrc is single file — append if needed
if [[ -f /etc/inputrc ]]; then
  if ! grep -q 'history-search-backward' /etc/inputrc; then
    backup_file /etc/inputrc
    cat >>/etc/inputrc <<'EOF'

# Pandora Noctalia — history search
"\e[A": history-search-backward
"\e[B": history-search-forward
EOF
  fi
fi
as_user mkdir -p "$REAL_HOME"
if [[ ! -f "$REAL_HOME/.inputrc" ]] || ! as_user grep -q 'history-search-backward' "$REAL_HOME/.inputrc" 2>/dev/null; then
  cat >>"$REAL_HOME/.inputrc" <<'EOF'
# Pandora Noctalia — history search
"\e[A": history-search-backward
"\e[B": history-search-forward
EOF
  chown "$REAL_UID:$REAL_GID" "$REAL_HOME/.inputrc"
fi

log "Fontes + emoji + MS fonts"
pac_install \
  ttf-dejavu ttf-liberation ttf-jetbrains-mono-nerd \
  noto-fonts noto-fonts-cjk noto-fonts-emoji \
  otf-font-awesome \
  cantarell-fonts
install_prefer ttf-ms-fonts || warn "ttf-ms-fonts falhou (AUR)"

# Rebuild font cache
as_user fc-cache >/dev/null 2>&1 || fc-cache >/dev/null 2>&1 || true

log "Teclado BR ABNT2 (console + X11 + XKB_DEFAULT)"
ensure_br_abnt2_keymap

ok "System tuning ok"
