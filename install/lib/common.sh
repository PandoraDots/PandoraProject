#!/usr/bin/env bash
# Shared helpers for Pandora Noctalia post-install.
set -euo pipefail

INSTALL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export INSTALL_ROOT

# shellcheck disable=SC2034
readonly PS_REPO_URL="${PS_REPO_URL:-https://github.com/yPerfectBR/PerfectSense.git}"
readonly SUNG_REPO_URL="${SUNG_REPO_URL:-https://github.com/yappologistic/Sung.git}"
readonly BUILD_DIR="${BUILD_DIR:-/tmp/pandora-noctalia-build}"
readonly AUR_CACHE="${AUR_CACHE:-$BUILD_DIR/aur}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32mOK:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERR:\033[0m %s\n' "$*" >&2; exit 1; }

need_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Execute como root (sudo ./install.sh)"
}

resolve_user() {
  local u="${SUDO_USER:-${REAL_USER:-}}"
  if [[ -z "$u" || "$u" == root ]]; then
    # Fallback: primeiro usuário humano com home em /home
    u="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $6 ~ /^\/home\// {print $1; exit}')"
  fi
  [[ -n "$u" ]] || die "Não foi possível detectar o usuário alvo (SUDO_USER)"
  REAL_USER="$u"
  REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
  REAL_UID="$(id -u "$REAL_USER")"
  REAL_GID="$(id -g "$REAL_USER")"
  export REAL_USER REAL_HOME REAL_UID REAL_GID
}

as_user() {
  resolve_user
  if [[ ${EUID:-0} -eq 0 ]]; then
    runuser -u "$REAL_USER" -- env HOME="$REAL_HOME" USER="$REAL_USER" LOGNAME="$REAL_USER" "$@"
  else
    env HOME="$REAL_HOME" USER="$REAL_USER" LOGNAME="$REAL_USER" "$@"
  fi
}

pkg_installed() {
  pacman -Q "$1" &>/dev/null
}

pac_available() {
  pacman -Si -- "$1" &>/dev/null
}

aur_available() {
  command -v paru &>/dev/null || return 1
  paru -Si -- "$1" &>/dev/null
}

ensure_paru() {
  if command -v paru &>/dev/null; then
    return 0
  fi
  log "Instalando paru (AUR helper)"
  pacman -S --needed --noconfirm base-devel git || true
  mkdir -p "$AUR_CACHE"
  if [[ ! -d "$AUR_CACHE/paru" ]]; then
    as_user git clone --depth=1 https://aur.archlinux.org/paru.git "$AUR_CACHE/paru"
  fi
  # Build as user, install as root
  (cd "$AUR_CACHE/paru" && as_user makepkg -f --noconfirm)
  pacman -U --noconfirm "$AUR_CACHE/paru"/paru-*.pkg.tar.zst
  configure_paru
}

configure_paru() {
  resolve_user
  local conf="$REAL_HOME/.config/paru/paru.conf"
  as_user mkdir -p "$(dirname "$conf")"
  if [[ ! -f "$conf" ]]; then
    as_user cp /etc/paru.conf "$conf" 2>/dev/null || as_user touch "$conf"
  fi
  # SkipReview / SudoLoop / BottomUp
  if ! as_user grep -qE '^\s*SkipReview' "$conf" 2>/dev/null; then
    printf '\n# Pandora Noctalia\nSkipReview\nSudoLoop\nBottomUp\n' | as_user tee -a "$conf" >/dev/null
  fi
}

pac_install() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  local missing=()
  local p
  for p in "${pkgs[@]}"; do
    pkg_installed "$p" && continue
    if pac_available "$p"; then
      missing+=("$p")
    else
      warn "Pacote oficial indisponível: $p"
    fi
  done
  if ((${#missing[@]})); then
    log "pacman -S: ${missing[*]}"
    pacman -S --needed --noconfirm "${missing[@]}"
  fi
}

aur_install() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  ensure_paru
  local missing=()
  local p
  for p in "${pkgs[@]}"; do
    pkg_installed "$p" && continue
    missing+=("$p")
  done
  if ((${#missing[@]})); then
    log "paru -S: ${missing[*]}"
    # paru as user; it will sudo for install
    as_user paru -S --needed --noconfirm --skipreview "${missing[@]}"
  fi
}

# Official → AUR → (caller fallback)
install_prefer() {
  local name="$1"
  pkg_installed "$name" && { ok "já instalado: $name"; return 0; }
  if pac_available "$name"; then
    pac_install "$name"
    return 0
  fi
  if aur_available "$name" || ensure_paru; then
    if aur_available "$name"; then
      aur_install "$name"
      return 0
    fi
  fi
  return 1
}

enable_multilib() {
  local conf=/etc/pacman.conf
  if grep -qE '^\[multilib\]' "$conf"; then
    ok "multilib já habilitado"
    return 0
  fi
  log "Habilitando [multilib]"
  # Descomenta bloco [multilib] padrão do Arch
  if grep -qE '^#\[multilib\]' "$conf"; then
    sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/{s/^#//}' "$conf"
  else
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>"$conf"
  fi
  pacman -Sy --noconfirm
}

systemd_enable() {
  local unit
  for unit in "$@"; do
    systemctl enable --now "$unit" 2>/dev/null || systemctl enable "$unit" || warn "falha ao habilitar $unit"
  done
}

user_systemd_enable() {
  resolve_user
  local unit
  for unit in "$@"; do
    as_user systemctl --user enable --now "$unit" 2>/dev/null \
      || as_user systemctl --user enable "$unit" \
      || warn "falha user unit: $unit"
  done
}

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp -a "$f" "${f}.pandora.bak.$(date +%Y%m%d%H%M%S)"
}

write_if_changed() {
  local dest="$1"
  local content="$2"
  if [[ -f "$dest" ]] && [[ "$(cat "$dest")" == "$content" ]]; then
    return 0
  fi
  backup_file "$dest"
  mkdir -p "$(dirname "$dest")"
  printf '%s\n' "$content" >"$dest"
}

detect_bootloader() {
  if [[ -d /boot/loader ]] || [[ -d /efi/loader ]] || bootctl is-installed &>/dev/null; then
    if [[ -f /boot/loader/loader.conf ]] || [[ -f /efi/loader/loader.conf ]] || [[ -d /boot/loader/entries ]]; then
      echo systemd-boot
      return
    fi
  fi
  if command -v grub-mkconfig &>/dev/null && [[ -f /etc/default/grub ]]; then
    echo grub
    return
  fi
  if [[ -d /boot/grub ]] || [[ -d /boot/grub2 ]]; then
    echo grub
    return
  fi
  echo unknown
}

ensure_wheel_sudo() {
  resolve_user
  if ! id -nG "$REAL_USER" | tr ' ' '\n' | grep -qx wheel; then
    log "Adicionando $REAL_USER ao grupo wheel"
    usermod -aG wheel "$REAL_USER"
  fi
  # Garante sudo para wheel (sem mexer em hostname/locale)
  if [[ -f /etc/sudoers ]] && ! grep -qE '^%wheel ALL=\(ALL:ALL\) ALL' /etc/sudoers \
    && ! grep -qE '^%wheel ALL=\(ALL\) ALL' /etc/sudoers; then
    if [[ -d /etc/sudoers.d ]]; then
      write_if_changed /etc/sudoers.d/00-wheel-pandora '%wheel ALL=(ALL:ALL) ALL'
      chmod 440 /etc/sudoers.d/00-wheel-pandora
    else
      warn "Não foi possível garantir sudo para wheel (sem /etc/sudoers.d)"
    fi
  fi
  ok "Usuário $REAL_USER com sudo via wheel"
}

mkdir -p "$BUILD_DIR" "$AUR_CACHE"
# Builds AUR/PerfectSense/Sung rodam como usuário — precisa ser gravável
if [[ ${EUID:-0} -eq 0 ]]; then
  resolve_user 2>/dev/null || true
  if [[ -n "${REAL_USER:-}" ]]; then
    chown -R "$REAL_USER":"$REAL_USER" "$BUILD_DIR" 2>/dev/null || true
  fi
fi
