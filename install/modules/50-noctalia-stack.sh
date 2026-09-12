#!/usr/bin/env bash
# 50 — Noctalia Shell + Umbriel + Greeter (greetd)
# Docs:
#   https://docs.noctalia.dev/noctalia/getting-started/installation/
#   https://docs.noctalia.dev/noctalia/getting-started/running-the-shell/
#   https://docs.noctalia.dev/noctalia/compositor-settings/umbriel/
#   https://docs.noctalia.dev/umbriel/installation/
#   https://docs.noctalia.dev/greeter/installation/
#   https://docs.noctalia.dev/greeter/configuration/
#   https://docs.noctalia.dev/greeter/sync/
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

disable_other_display_managers() {
  # Docs: identify display-manager.service alias, disable that unit, then greetd.
  local unit dm
  if unit="$(systemctl show -p Id --value display-manager.service 2>/dev/null || true)"; then
    if [[ -n "$unit" && "$unit" != "display-manager.service" && "$unit" != "greetd.service" ]]; then
      log "Desabilitando display manager atual: $unit"
      systemctl disable "$unit" 2>/dev/null || systemctl disable "$unit" 2>/dev/null || true
    fi
  fi
  for dm in sddm gdm gdm3 lightdm lxdm ly; do
    if [[ "$dm.service" == "${unit:-}" ]]; then
      continue
    fi
    if ! systemctl is-enabled --quiet "$dm.service" 2>/dev/null && ! systemctl is-active --quiet "$dm.service" 2>/dev/null; then
      already_ok
      continue
    fi
    systemctl disable "$dm.service" 2>/dev/null || systemctl disable "$dm.service" 2>/dev/null || true
  done
}

resolve_umbriel_session_name() {
  local name="" desktop=""
  if command -v noctalia-greeter >/dev/null && noctalia-greeter sessions &>/dev/null; then
    name="$(noctalia-greeter sessions 2>/dev/null | grep -iE '^Umbriel$' | head -1 || true)"
    if [[ -z "$name" ]]; then
      name="$(noctalia-greeter sessions 2>/dev/null | grep -iE 'umbriel' | head -1 || true)"
    fi
  fi
  if [[ -z "$name" ]]; then
    desktop="$(find /usr/share/wayland-sessions /usr/local/share/wayland-sessions \
      -name '*umbriel*.desktop' 2>/dev/null | head -1 || true)"
    if [[ -n "$desktop" ]]; then
      name="$(grep -E '^Name=' "$desktop" | head -1 | cut -d= -f2-)"
    fi
  fi
  printf '%s' "${name:-Umbriel}"
}

ensure_umbriel_autostart() {
  local conf="$1"
  # Docs: [general] autostart = ["noctalia"]
  if grep -qE 'autostart\s*=\s*\[[^]]*"noctalia"' "$conf"; then
    already_ok
    return 0
  fi
  if grep -qE '^[[:space:]]*autostart[[:space:]]*=[[:space:]]*\[\s*\]' "$conf"; then
    sed -i -E 's/^([[:space:]]*autostart[[:space:]]*=[[:space:]]*)\[\s*\]/\1["noctalia"]/' "$conf"
  elif grep -qE '^[[:space:]]*autostart[[:space:]]*=' "$conf"; then
    sed -i -E 's/^([[:space:]]*autostart[[:space:]]*=[[:space:]]*\[)/\1"noctalia", /' "$conf"
  elif grep -qE '^\[general\]' "$conf"; then
    sed -i '/^\[general\]/a autostart = ["noctalia"]' "$conf"
  else
    printf '\n[general]\nautostart = ["noctalia"]\n' >>"$conf"
  fi
  ok "Umbriel autostart → noctalia"
}

ensure_umbriel_hybrid_drm() {
  # iGPU para o compositor; dGPU só via prime-run (modelo híbrido do Helios).
  # Só aplica se Intel + NVIDIA estiverem presentes — senão Umbriel fica sem GPU.
  local conf="$1"
  local nvidia_pci intel_pci
  nvidia_pci="$(lspci -Dn 2>/dev/null | awk '$2 ~ /^(0300|0302|0380):$/ && $3 ~ /^10de:/ {print $1; exit}')"
  intel_pci="$(lspci -Dn 2>/dev/null | awk '$2 ~ /^(0300|0302|0380):$/ && $3 ~ /^8086:/ {print $1; exit}')"
  if [[ -z "$nvidia_pci" || -z "$intel_pci" ]]; then
    warn "DRM ignore NVIDIA omitido (iGPU Intel não detectada ainda — ligue Hybrid no BIOS)"
    return 0
  fi
  python3 "$INSTALL_ROOT/lib/repair-config.py" drm "$conf" "$nvidia_pci" \
    || die "Falha ao corrigir/validar DRM do Umbriel"
  ok "Umbriel ignora NVIDIA PCI ${nvidia_pci} (compositor na Intel ${intel_pci})"
}

ensure_umbriel_keyboard_abnt2() {
  local conf="$1"
  python3 "$INSTALL_ROOT/lib/repair-config.py" keyboard "$conf" br abnt2 \
    || die "Falha ao definir teclado br/abnt2 no Umbriel"
  ok "Umbriel teclado → br / abnt2"
}

ensure_umbriel_brightness_binds() {
  local conf="$1"
  if grep -qE '^[[:space:]]*"XF86MonBrightness(Up|Down)"' "$conf"; then
    already_ok
    return 0
  fi
  python3 "$INSTALL_ROOT/lib/repair-config.py" brightness-binds "$conf" \
    || die "Falha ao habilitar keybinds de brilho no Umbriel"
  if grep -qE '^[[:space:]]*"XF86MonBrightness(Up|Down)"' "$conf"; then
    ok "Umbriel keybinds → brilho (Fn)"
  else
    warn "Keybinds de brilho não encontrados no example — adicione manualmente se necessário"
  fi
}

ensure_umbriel_caelestia_visual() {
  # Chrome do Caelestia (blur/opacity/sombra/rounding/gaps/anim) — sem scheme vermelho.
  local conf="$1"
  python3 "$INSTALL_ROOT/lib/repair-config.py" visual "$conf" \
    || die "Falha ao aplicar visual Caelestia no Umbriel"
  ok "Umbriel visual → Caelestia (blur 8×2, opacity 0.95, anim speed×100 ms)"
}

ensure_umbriel_pandora_keybinds() {
  local conf="$1"
  python3 "$INSTALL_ROOT/lib/repair-config.py" keybinds "$conf" \
    || die "Falha ao aplicar keybinds Pandora no Umbriel"
  ok "Umbriel keybinds → apps, scratchpads, focus-follows-mouse, scroll→WS"
}

install_pandora_helpers() {
  install_if_changed 755 "$INSTALL_ROOT/assets/pandora-scratch-toggle" /usr/local/bin/pandora-scratch-toggle
  install_if_changed 755 "$INSTALL_ROOT/assets/pandora-kitty-shell" /usr/local/bin/pandora-kitty-shell
  install_if_changed 755 "$INSTALL_ROOT/assets/pandora-terminal" /usr/local/bin/pandora-terminal
  ok "Helpers → /usr/local/bin/pandora-{scratch-toggle,kitty-shell,terminal}"
}

ensure_noctalia_pandora_config() {
  # Declarative Noctalia overrides from the GUI (bar/CC/theme/widgets).
  # Docs: ~/.config/noctalia/*.toml merge; settings.toml wins — prune managed keys.
  local conf_dir="$REAL_HOME/.config/noctalia"
  local wall_dir="$REAL_HOME/Pictures/Wallpapers"
  local wall_src="$INSTALL_ROOT/assets/wallpapers/glassesredjapan.jpg"
  local template="$INSTALL_ROOT/assets/noctalia/pandora.toml"
  local dest="$conf_dir/pandora.toml"
  local settings="$REAL_HOME/.local/state/noctalia/settings.toml"

  as_user mkdir -p "$conf_dir" "$wall_dir" "$REAL_HOME/.local/state/noctalia"
  if [[ -f "$wall_src" ]]; then
    install_if_changed 644 "$wall_src" "$wall_dir/glassesredjapan.jpg"
    chown "$REAL_UID:$REAL_GID" "$wall_dir/glassesredjapan.jpg"
  else
    warn "Wallpaper Pandora ausente em assets/wallpapers"
  fi

  python3 "$INSTALL_ROOT/lib/repair-config.py" noctalia-render "$dest" "$REAL_HOME" "$template" \
    || die "Falha ao instalar ~/.config/noctalia/pandora.toml"
  chown "$REAL_UID:$REAL_GID" "$dest"
  ok "Noctalia → ~/.config/noctalia/pandora.toml (bar, control center, theme, widgets)"

  if [[ -f "$settings" ]]; then
    python3 "$INSTALL_ROOT/lib/repair-config.py" noctalia-prune-settings "$settings" "$dest" \
      || die "Falha ao limpar overrides conflitantes em settings.toml"
    chown "$REAL_UID:$REAL_GID" "$settings"
    ok "Noctalia settings.toml → removidas tabelas cobertas por pandora.toml"
  fi
}

install_umbriel_user_config() {
  local conf="$REAL_HOME/.config/umbriel/config.toml"
  as_user mkdir -p "$REAL_HOME/.config/umbriel"

  if [[ ! -f "$conf" ]]; then
    # CRÍTICO: o example empacotado traz keybinds/window_rules/layer_rules do Noctalia.
    # Uma config mínima SUBSTITUI o conjunto built-in de keybinds (docs Umbriel).
    local src=""
    for cand in /usr/share/umbriel/config.toml /usr/local/share/umbriel/config.toml; do
      if [[ -f "$cand" ]]; then
        src="$cand"
        break
      fi
    done
    if [[ -n "$src" ]]; then
      cp "$src" "$conf"
      ok "Copiado $src → ~/.config/umbriel/config.toml"
    else
      log "Baixando examples/config.toml upstream (pacote sem example)"
      as_user curl -fsSL \
        https://raw.githubusercontent.com/noctalia-dev/umbriel/main/examples/config.toml \
        -o "$conf" \
        || die "Não foi possível obter config.toml do Umbriel"
    fi
  else
    already_ok
  fi

  ensure_umbriel_autostart "$conf"
  ensure_umbriel_hybrid_drm "$conf"
  ensure_umbriel_keyboard_abnt2 "$conf"
  ensure_umbriel_brightness_binds "$conf"
  ensure_umbriel_caelestia_visual "$conf"
  ensure_umbriel_pandora_keybinds "$conf"

  # Environment Wayland-friendly (docs Umbriel)
  if ! grep -qE '^[[:space:]]*ELECTRON_OZONE_PLATFORM_HINT' "$conf"; then
    if grep -qE '^\[environment\]' "$conf"; then
      sed -i '/^\[environment\]/a ELECTRON_OZONE_PLATFORM_HINT = "auto"\nSDL_VIDEODRIVER = "wayland"' "$conf"
    else
      printf '\n[environment]\nELECTRON_OZONE_PLATFORM_HINT = "auto"\nSDL_VIDEODRIVER = "wayland"\n' >>"$conf"
    fi
  fi

  chown "$REAL_UID:$REAL_GID" "$conf"
  if command -v umbriel >/dev/null; then
    as_user umbriel validate -c "$conf" \
      && ok "umbriel validate OK" \
      || die "umbriel validate reportou problemas — revise $conf"
  fi
}

write_greetd_config() {
  local greeter_bin="$1"
  mkdir -p /etc/greetd
  # Docs: greetd must launch noctalia-greeter-session (full path), user=greeter.
  # Defaults de sessão/usuário ficam em greeter.toml (evita quebrar Name= com espaços).
  install_if_changed 644 /dev/stdin /etc/greetd/config.toml <<EOF
# Pandora Noctalia — https://docs.noctalia.dev/greeter/installation/
[terminal]
vt = 1

[default_session]
command = "env XKB_DEFAULT_LAYOUT=br XKB_DEFAULT_VARIANT=abnt2 ${greeter_bin}"
user = "greeter"
EOF
  ok "greetd → ${greeter_bin}"
}

write_greeter_defaults() {
  local session_name="$1"
  local f=/var/lib/noctalia-greeter/greeter.toml
  mkdir -p /var/lib/noctalia-greeter
  # Only user/session — do NOT write [appearance.palette] here; that would block
  # Sync wallpaper/palette from Noctalia (greeter.toml wins over sync.toml).
  python3 "$INSTALL_ROOT/lib/repair-config.py" greeter "$f" "$REAL_USER" "$session_name" \
    || die "Configuração do greeter inválida; original preservado"
  chown -R greeter:greeter /var/lib/noctalia-greeter 2>/dev/null || true
  ok "greeter.toml user=${REAL_USER} session=${session_name}"
}

pkg_version() {
  local name="$1"
  pacman -Q "$name" 2>/dev/null | awk '{print $2}' || true
}

# Compare Arch/Pacman versions (epoch:pkgver-pkgrel). Returns 0 if $1 >= $2.
version_ge() {
  [[ "$(vercmp "$1" "$2")" -ge 0 ]]
}

report_noctalia_stack_versions() {
  local n g u
  n="$(pkg_version noctalia)"
  g="$(pkg_version noctalia-greeter)"
  u="$(pkg_version umbriel-git)"
  log "Versões: noctalia=${n:-?}  noctalia-greeter=${g:-?}  umbriel-git=${u:-?}"
  if command -v noctalia >/dev/null; then
    log "noctalia CLI: $(noctalia --version 2>/dev/null | head -1)"
  fi
  if command -v umbriel >/dev/null; then
    log "umbriel CLI: $(umbriel --version 2>/dev/null | head -1)"
  fi
  if command -v noctalia-greeter >/dev/null; then
    log "greeter CLI: $(noctalia-greeter --version 2>/dev/null | head -1)"
  fi
}

assert_noctalia_stack_compat() {
  # Passwordless constrained sync needs greeter ≥1.5 and Noctalia after 5.0.1 (≥5.1.0).
  local n g
  n="$(pkg_version noctalia)"
  g="$(pkg_version noctalia-greeter)"
  if [[ -n "$n" ]] && ! version_ge "$n" "5.1.0-1"; then
    warn "noctalia $n < 5.1.0 — atualize (pacman -Syu noctalia) para editor de print + sync constrained"
  fi
  if [[ -n "$g" ]] && ! version_ge "$g" "1.5.0-1"; then
    warn "noctalia-greeter $g < 1.5.0 — passwordless-sync / --sync Polkit exigem 1.5+"
  fi
}

refresh_noctalia_stack_packages() {
  # Optional full refresh of rolling -git packages. Default off (slow rebuild).
  # Prefer CLI flag (sudo strips user env):
  #   sudo ./install/install.sh --refresh-stack 50-noctalia-stack
  # Or: sudo env PANDORA_REFRESH_STACK=1 ./install/install.sh 50
  [[ "${PANDORA_REFRESH_STACK:-0}" == "1" ]] || return 0
  log "PANDORA_REFRESH_STACK=1 → reinstalando noctalia / greeter / umbriel-git"
  pacman -Sy --noconfirm || warn "pacman -Sy falhou"
  pacman -S --noconfirm --needed noctalia || warn "noctalia refresh falhou"
  ensure_paru || { warn "paru indisponível para refresh AUR"; return 0; }
  # Force AUR rebuild even if pacman thinks the package is installed.
  as_user paru -S --noconfirm --skipreview --rebuild noctalia-greeter \
    umbriel-git xdg-desktop-portal-umbriel-git \
    || as_user paru -S --noconfirm --skipreview noctalia-greeter \
      umbriel-git xdg-desktop-portal-umbriel-git \
    || warn "refresh AUR da stack falhou (configs serão reaplicadas mesmo assim)"
}

# ---------------------------------------------------------------------------
# Install packages
# ---------------------------------------------------------------------------

log "Stack Noctalia + Umbriel + Greeter"

# Target matrix (verified 2026-09-12 against docs/releases):
#   noctalia          ≥ 5.1.0  (extra) — screenshot editor, constrained greeter sync
#   noctalia-greeter  ≥ 1.5.0  (AUR)   — passwordless --sync Polkit action
#   umbriel-git       rolling  (AUR)   — re-validate config after rebuild
refresh_noctalia_stack_packages
report_noctalia_stack_versions
assert_noctalia_stack_compat

pac_install greetd dbus polkit accountsservice noctalia
# Terminal usado pelos keybinds padrão do example Umbriel (Mod+Return → kitty)
pac_install kitty foot || pac_install foot || true
pac_install fastfetch || warn "fastfetch falhou (terminal ainda abre sem banner)"

install_prefer umbriel-git || die "falha umbriel-git"
# Dependência do umbriel-git; garantir portal
install_prefer xdg-desktop-portal-umbriel-git || true
install_prefer noctalia-greeter || die "falha noctalia-greeter"

# Re-check after install (first-time machines) and keep helpers in sync.
report_noctalia_stack_versions
assert_noctalia_stack_compat

pac_install \
  xdg-desktop-portal xdg-desktop-portal-gtk \
  brightnessctl playerctl \
  grim slurp wl-clipboard \
  ffmpeg ffmpegthumbnailer \
  jemalloc

install_pandora_helpers

# Setup oficial do pacote (PAM + /var/lib/noctalia-greeter + greeter.toml)
# Path documentado em PACKAGING.md / AUR .install
setup_ran=0
if id greeter &>/dev/null && [[ -s /etc/pam.d/greetd && -d /var/lib/noctalia-greeter && -s /var/lib/noctalia-greeter/greeter.toml ]]; then
  already_ok
  setup_ran=1
fi
for s in \
  /usr/share/noctalia-greeter/setup_greeter_system.sh \
  /usr/local/share/noctalia-greeter/setup_greeter_system.sh
do
  ((setup_ran == 0)) || break
  if [[ -x "$s" ]]; then
    log "Rodando setup oficial: $s"
    NOCTALIA_GREETER_SESSION_BIN="$(command -v noctalia-greeter-session || true)" \
      bash "$s" || warn "setup_greeter_system.sh retornou erro"
    setup_ran=1
    break
  fi
done
if ((setup_ran == 0)); then
  warn "setup_greeter_system.sh não encontrado — criando estado mínimo"
fi

if ! id greeter &>/dev/null; then
  useradd -r -d /var/lib/noctalia-greeter -s /usr/bin/nologin greeter || true
fi
mkdir -p /var/lib/noctalia-greeter
chown -R greeter:greeter /var/lib/noctalia-greeter 2>/dev/null || true

greeter_bin="$(command -v noctalia-greeter-session || true)"
[[ -n "$greeter_bin" ]] || die "noctalia-greeter-session não encontrado (pacote noctalia-greeter)"
# Preferir caminho canônico /usr/bin quando existir
[[ -x /usr/bin/noctalia-greeter-session ]] && greeter_bin=/usr/bin/noctalia-greeter-session

session_name="$(resolve_umbriel_session_name)"
ok "Sessão padrão do greeter: Name=${session_name}"

write_greetd_config "$greeter_bin"
write_greeter_defaults "$session_name"
install_umbriel_user_config
ensure_noctalia_pandora_config

# Sync passwordless (greeter ≥ 1.5.0 + Noctalia ≥ 5.1.0) — constrained --sync only.
# Docs: https://docs.noctalia.dev/greeter/sync/
# greeter.toml declarative appearance would win over sync.toml — we only set user/session.
if command -v noctalia-greeter >/dev/null; then
  if noctalia-greeter passwordless-sync enable "$REAL_USER" 2>/dev/null; then
    ok "passwordless-sync habilitado para $REAL_USER (constrained appearance sync)"
  else
    warn "passwordless-sync não aplicado (sync continua com prompt de admin — ok)"
  fi
fi

disable_other_display_managers
systemd_enable accounts-daemon.service || true

# Seat access for brightnessctl / input devices
usermod -aG video,input "$REAL_USER" 2>/dev/null || true
ok "Grupos video+input → $REAL_USER"

# Console / X11 / greeter XKB defaults
ensure_br_abnt2_keymap

# Habilita para o próximo boot; abrir o login é o último passo do install.sh.
if systemctl is-enabled --quiet greetd.service; then
  already_ok
else
  systemctl enable greetd.service
fi
if [[ "$(systemctl get-default)" == graphical.target ]]; then
  already_ok
else
  systemctl set-default graphical.target || true
fi

ok "Noctalia + Umbriel + Greeter configurados (reboot para login)"
