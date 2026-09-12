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
already_ok() { printf 'ok\n'; }

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
  pacman -Q "$1" &>/dev/null && pacman -Qk "$1" &>/dev/null
}

pac_available() {
  pacman -Si -- "$1" &>/dev/null
}

aur_available() {
  command -v paru &>/dev/null || return 1
  as_user paru -Si -- "$1" &>/dev/null
}

ensure_paru() {
  if pkg_installed paru && as_user paru --version &>/dev/null; then
    configure_paru || return $?
    already_ok
    return 0
  fi
  if restore_cached_package paru; then
    configure_paru
    return $?
  fi
  log "Instalando paru (AUR helper)"
  local build_deps=(base-devel git)
  if ! as_user cargo --version &>/dev/null || ! as_user rustc --version &>/dev/null; then
    build_deps+=(rust)
  fi
  pac_install "${build_deps[@]}" || return 1
  if ! as_user cargo --version &>/dev/null || ! as_user rustc --version &>/dev/null; then
    warn "Cargo e Rust precisam estar disponíveis para compilar paru"
    return 1
  fi
  mkdir -p "$AUR_CACHE" || return 1
  if [[ ! -d "$AUR_CACHE/paru" ]]; then
    as_user git clone --depth=1 https://aur.archlinux.org/paru.git "$AUR_CACHE/paru" || return 1
  fi
  # Build as user, install as root
  (cd "$AUR_CACHE/paru" && as_user makepkg --noconfirm) || return 1
  install_built_package paru "$AUR_CACHE/paru" || return 1
  configure_paru
}

configure_paru() {
  resolve_user
  local conf="$REAL_HOME/.config/paru/paru.conf"
  as_user mkdir -p "$(dirname "$conf")"
  if [[ ! -f "$conf" ]]; then
    as_user cp /etc/paru.conf "$conf" 2>/dev/null || as_user touch "$conf"
  fi
  # Keep options inside [options], including repair of older sectionless files.
  local tmp
  tmp="$(mktemp)" || return 1
  awk '
    BEGIN { print "[options]"; print "SkipReview"; print "SudoLoop"; print "BottomUp" }
    /^[[:space:]]*\[options\][[:space:]]*$/ { next }
    /^[[:space:]]*(SkipReview|SudoLoop|BottomUp)[[:space:]]*$/ { next }
    { print }
  ' "$conf" >"$tmp" || { rm -f "$tmp"; return 1; }
  install_if_changed 644 "$tmp" "$conf" || { rm -f "$tmp"; return 1; }
  chown "$REAL_UID:$REAL_GID" "$conf"
  rm -f "$tmp"
}

pac_install() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  local missing=()
  local unavailable=0
  local p
  for p in "${pkgs[@]}"; do
    pkg_installed "$p" && { already_ok; continue; }
    if pac_available "$p"; then
      missing+=("$p")
    else
      warn "Pacote oficial indisponível: $p"
      unavailable=1
    fi
  done
  # Do not partially install a required batch with unresolved dependencies.
  ((unavailable == 0)) || return 1
  if ((${#missing[@]})); then
    log "pacman -S: ${missing[*]}"
    pacman -S --noconfirm "${missing[@]}" || return $?
  fi
  return 0
}

aur_install() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  local missing=()
  local p
  for p in "${pkgs[@]}"; do
    pkg_installed "$p" && { already_ok; continue; }
    restore_cached_package "$p" && { already_ok; continue; }
    missing+=("$p")
  done
  if ((${#missing[@]})); then
    ensure_paru || return 1
    log "paru -S: ${missing[*]}"
    # paru as user; it will sudo for install
    as_user paru -S --noconfirm --skipreview "${missing[@]}"
  fi
}

# Official → AUR → (caller fallback)
install_prefer() {
  local name="$1"
  pkg_installed "$name" && { already_ok; return 0; }
  restore_cached_package "$name" && { already_ok; return 0; }
  if pac_available "$name"; then
    pac_install "$name"
    return $?
  fi
  if aur_available "$name" || ensure_paru; then
    if aur_available "$name"; then
      aur_install "$name"
      return $?
    fi
  fi
  return 1
}

# Reuse archives only after pacman validates their identity and payload.
restore_cached_package() {
  local name="$1" archive metadata
  resolve_user
  while IFS= read -r -d '' archive; do
    metadata="$(pacman -Qp -- "$archive" 2>/dev/null)" || continue
    [[ "${metadata%% *}" == "$name" ]] || continue
    bsdtar -tf "$archive" >/dev/null 2>&1 || continue
    log "Reutilizando pacote compilado: $archive"
    pacman -U --noconfirm "$archive" || return $?
    pkg_installed "$name" && return 0
  done < <(find /var/cache/pacman/pkg "$AUR_CACHE" "$BUILD_DIR" "$REAL_HOME/.cache/paru/clone" \
    -type f -name "$name-*.pkg.tar.*" ! -name '*.sig' -print0 2>/dev/null)
  return 1
}

# ELF validation without opening a GUI. Scripts/AppImages need their own checks.
native_binary_ready() {
  local binary="$1" dependencies
  [[ -s "$binary" && -x "$binary" ]] || return 1
  readelf -h "$binary" >/dev/null 2>&1 || return 1
  dependencies="$(LC_ALL=C ldd "$binary" 2>&1)" || {
    [[ "$dependencies" == *"not a dynamic executable"* || "$dependencies" == *"statically linked"* ]] || return 1
  }
  [[ "$dependencies" != *"not found"* ]]
}

sung_ready() {
  local prefix="$REAL_HOME/.local" file
  native_binary_ready "$prefix/bin/sung" || return 1
  for file in lib/sung/catalog.py lib/sung/online_artwork.py lib/sung/requirements.txt \
    share/applications/sung.desktop share/icons/hicolor/512x512/apps/sung.png; do
    [[ -s "$prefix/$file" ]] || return 1
  done
  as_user "$prefix/lib/sung/runtime/bin/python" -m pip check >/dev/null 2>&1 || return 1
  as_user "$prefix/lib/sung/runtime/bin/python" -c 'import ytmusicapi, yt_dlp' >/dev/null 2>&1 || return 1
  as_user "$prefix/lib/sung/runtime/bin/python" - "$prefix/lib/sung/requirements.txt" <<'PYREQ'
import sys
from importlib.metadata import version
from pip._vendor.packaging.requirements import Requirement
for line in open(sys.argv[1]):
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    req = Requirement(line.strip())
    if req.marker is None or req.marker.evaluate():
        if version(req.name) not in req.specifier:
            sys.exit(1)
PYREQ
}

# Select the real package, never its debug archive or detached signature.
install_built_package() {
  local name="$1" directory="$2" archive metadata
  for archive in "$directory"/"$name"-*.pkg.tar.*; do
    [[ -f "$archive" && "$archive" != *.sig ]] || continue
    metadata="$(pacman -Qp -- "$archive" 2>/dev/null)" || continue
    [[ "${metadata%% *}" == "$name" ]] || continue
    bsdtar -tf "$archive" >/dev/null 2>&1 || continue
    pacman -U --noconfirm "$archive" || return $?
    return 0
  done
  warn "Pacote $name não encontrado em $directory"
  return 1
}

enable_multilib() {
  local conf=/etc/pacman.conf
  if grep -qE '^\[multilib\]' "$conf"; then
    already_ok
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
    if systemctl is-enabled --quiet "$unit" && systemctl is-active --quiet "$unit"; then
      already_ok
      continue
    fi
    systemctl enable --now "$unit" 2>/dev/null || systemctl enable "$unit" || warn "falha ao habilitar $unit"
  done
}

user_systemd_enable() {
  resolve_user
  local unit
  for unit in "$@"; do
    if as_user systemctl --user is-enabled --quiet "$unit" && as_user systemctl --user is-active --quiet "$unit"; then
      already_ok
      continue
    fi
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
  if [[ -f "$dest" ]] && cmp -s "$dest" <(printf '%s\n' "$content"); then
    already_ok
    return 0
  fi
  backup_file "$dest"
  mkdir -p "$(dirname "$dest")"
  printf '%s\n' "$content" >"$dest"
}

# Compare content and permissions before touching an installed asset.
install_if_changed() {
  local mode="$1" src="$2" dest="$3" tmp
  tmp="$(mktemp)" || return 1
  cat "$src" >"$tmp" || { rm -f "$tmp"; return 1; }
  if cmp -s "$tmp" "$dest" && [[ "$(stat -c %a "$dest")" == "${mode#0}" ]]; then
    rm -f "$tmp"
    already_ok
    return 0
  fi
  backup_file "$dest"
  install -Dm"$mode" "$tmp" "$dest"
  local status=$?
  rm -f "$tmp"
  return "$status"
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

# Ensure a kernel cmdline token exists. Prefer UKI (/etc/kernel/cmdline + mkinitcpio);
# also mirror into GRUB_CMDLINE_LINUX_DEFAULT when GRUB is present.
ensure_kernel_cmdline_param() {
  local param="$1"
  local key="${param%%=*}"
  local changed=0
  local f=/etc/kernel/cmdline
  local line tokens t out=()

  if [[ -f "$f" ]]; then
    line="$(tr -s '[:space:]' ' ' <"$f" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    # shellcheck disable=SC2206
    tokens=($line)
    if printf '%s\n' "${tokens[@]}" | grep -qxF -- "$param"; then
      already_ok
    else
      for t in "${tokens[@]}"; do
        [[ "$t" == "$key" || "$t" == "$key"=* ]] && continue
        out+=("$t")
      done
      out+=("$param")
      backup_file "$f"
      printf '%s\n' "${out[*]}" >"$f"
      changed=1
      ok "cmdline UKI → $param"
    fi
  fi

  if [[ -f /etc/default/grub ]]; then
    local grub_line
    grub_line="$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | head -1 || true)"
    if [[ -n "$grub_line" ]]; then
      if [[ "$grub_line" != *" $param"* && "$grub_line" != *"\"$param"* && "$grub_line" != *"=$param\""* ]]; then
        # Insert before the closing quote of the default string.
        if [[ "$grub_line" != *"$key"* ]]; then
          backup_file /etc/default/grub
          sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"/\1 ${param}\"/" /etc/default/grub
          changed=1
          ok "cmdline GRUB → $param"
        fi
      else
        already_ok
      fi
    fi
  fi

  ((changed == 0)) && return 0

  if [[ -f /etc/mkinitcpio.d/linux-zen.preset ]] && pkg_installed linux-zen; then
    mkinitcpio -p linux-zen || warn "mkinitcpio linux-zen falhou ao aplicar $param"
  elif command -v mkinitcpio >/dev/null; then
    mkinitcpio -P || warn "mkinitcpio -P falhou ao aplicar $param"
  fi
  if [[ "$(detect_bootloader)" == grub ]] && command -v grub-mkconfig >/dev/null; then
    if [[ -d /boot/grub ]]; then
      grub-mkconfig -o /boot/grub/grub.cfg >/dev/null || warn "grub-mkconfig falhou"
    elif [[ -d /boot/grub2 ]]; then
      grub-mkconfig -o /boot/grub2/grub.cfg >/dev/null || warn "grub-mkconfig falhou"
    fi
  fi
}

# Console + X11 + libxkbcommon defaults: Brazilian ABNT2.
ensure_br_abnt2_keymap() {
  local vconsole=/etc/vconsole.conf
  local x11=/etc/X11/xorg.conf.d/00-keyboard.conf
  local envf=/etc/environment
  local changed=0

  if [[ -f "$vconsole" ]] \
    && grep -qx 'KEYMAP=br-abnt2' "$vconsole" \
    && grep -qx 'XKBLAYOUT=br' "$vconsole" \
    && grep -qx 'XKBVARIANT=abnt2' "$vconsole"; then
    already_ok
  else
    backup_file "$vconsole"
    {
      grep -vE '^(KEYMAP|XKBLAYOUT|XKBMODEL|XKBVARIANT|XKBOPTIONS)=' "$vconsole" 2>/dev/null || true
      printf 'KEYMAP=br-abnt2\nXKBLAYOUT=br\nXKBMODEL=pc105\nXKBVARIANT=abnt2\nXKBOPTIONS=\n'
    } >"${vconsole}.tmp"
    mv "${vconsole}.tmp" "$vconsole"
    changed=1
    ok "vconsole → br-abnt2"
  fi

  mkdir -p "$(dirname "$x11")"
  local x11_content
  x11_content=$(cat <<'EOF'
# Written by Pandora Noctalia install — Brazilian ABNT2
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "br"
        Option "XkbModel" "pc105"
        Option "XkbVariant" "abnt2"
EndSection
EOF
)
  if [[ -f "$x11" ]] && cmp -s "$x11" <(printf '%s\n' "$x11_content"); then
    already_ok
  else
    backup_file "$x11"
    printf '%s\n' "$x11_content" >"$x11"
    changed=1
    ok "X11 keymap → br abnt2"
  fi

  touch "$envf"
  local need_layout=1 need_variant=1
  grep -qx 'XKB_DEFAULT_LAYOUT=br' "$envf" && need_layout=0
  grep -qx 'XKB_DEFAULT_VARIANT=abnt2' "$envf" && need_variant=0
  if ((need_layout == 0 && need_variant == 0)); then
    already_ok
  else
    backup_file "$envf"
    grep -vE '^XKB_DEFAULT_(LAYOUT|VARIANT|MODEL|OPTIONS)=' "$envf" >"${envf}.tmp" || true
    printf 'XKB_DEFAULT_LAYOUT=br\nXKB_DEFAULT_VARIANT=abnt2\n' >>"${envf}.tmp"
    mv "${envf}.tmp" "$envf"
    changed=1
    ok "XKB_DEFAULT_* → br/abnt2 (greeter + apps)"
  fi

  if command -v localectl >/dev/null; then
    localectl set-keymap --no-convert br-abnt2 >/dev/null 2>&1 || true
    localectl set-x11-keymap br pc105 abnt2 >/dev/null 2>&1 || true
  fi

  ((changed == 1)) || true
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
