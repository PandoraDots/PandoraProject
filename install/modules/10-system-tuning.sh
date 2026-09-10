#!/usr/bin/env bash
# 10 — System tuning: pacman, makepkg, zram, timers, bash, fonts, IPv4
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user

log "Ajustando /etc/pacman.conf (Color + ILoveCandy + ParallelDownloads=8)"
backup_file /etc/pacman.conf
# Color
sed -i 's/^#Color$/Color/' /etc/pacman.conf
grep -qE '^Color$' /etc/pacman.conf || sed -i '/^\[options\]/a Color' /etc/pacman.conf
# ILoveCandy
grep -qE '^ILoveCandy$' /etc/pacman.conf || sed -i '/^Color$/a ILoveCandy' /etc/pacman.conf
# ParallelDownloads
if grep -qE '^#?ParallelDownloads' /etc/pacman.conf; then
  sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 8/' /etc/pacman.conf
else
  sed -i '/^\[options\]/a ParallelDownloads = 8' /etc/pacman.conf
fi

log "Ajustando /etc/makepkg.conf (-j6, zstd -T6)"
backup_file /etc/makepkg.conf
if grep -qE '^#?MAKEFLAGS=' /etc/makepkg.conf; then
  sed -i 's/^#\?MAKEFLAGS=.*/MAKEFLAGS="-j6"/' /etc/makepkg.conf
else
  printf '\nMAKEFLAGS="-j6"\n' >>/etc/makepkg.conf
fi
if grep -qE "^COMPRESSZST=" /etc/makepkg.conf; then
  sed -i 's/^COMPRESSZST=.*/COMPRESSZST=(zstd -c -T6 -)/' /etc/makepkg.conf
else
  printf 'COMPRESSZST=(zstd -c -T6 -)\n' >>/etc/makepkg.conf
fi

log "zram via systemd-zram-generator"
pac_install zram-generator
install -Dm644 "$INSTALL_ROOT/config/zram-generator.conf" /etc/systemd/zram-generator.conf
systemctl daemon-reload
systemd_enable systemd-zram-setup@zram0.service || true
# generator cria a unit no boot; força agora se possível
systemctl start /dev/zram0 2>/dev/null || true

log "Timers: fstrim + paccache"
pac_install pacman-contrib
systemd_enable fstrim.timer paccache.timer

log "Preferência IPv4 em /etc/gai.conf"
backup_file /etc/gai.conf
if [[ -f /etc/gai.conf ]]; then
  sed -i 's/^#precedence ::ffff:0:0\/96  100$/precedence ::ffff:0:0\/96  100/' /etc/gai.conf
  grep -qE '^precedence ::ffff:0:0/96' /etc/gai.conf \
    || printf '\nprecedence ::ffff:0:0/96  100\n' >>/etc/gai.conf
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
  ttf-font-awesome otf-font-awesome \
  cantarell-fonts
install_prefer ttf-ms-fonts || warn "ttf-ms-fonts falhou (AUR)"

# Rebuild font cache
as_user fc-cache -fv >/dev/null 2>&1 || fc-cache -fv >/dev/null 2>&1 || true

ok "System tuning ok"
