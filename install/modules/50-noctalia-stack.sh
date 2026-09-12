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
  install_if_changed 755 "$INSTALL_ROOT/assets/pandora-terminal" /usr/local/bin/pandora-terminal
  ok "Helpers → /usr/local/bin/pandora-{scratch-toggle,terminal}"
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

  python3 "$INSTALL_ROOT/lib/repair-config.py" greeter "$f" "$REAL_USER" "$session_name" \
    || die "Configuração do greeter inválida; original preservado"
  chown -R greeter:greeter /var/lib/noctalia-greeter 2>/dev/null || true
  ok "greeter.toml user=${REAL_USER} session=${session_name}"
}

# ---------------------------------------------------------------------------
# Install packages
# ---------------------------------------------------------------------------

log "Stack Noctalia + Umbriel + Greeter"

pac_install greetd dbus polkit accountsservice noctalia
# Terminal usado pelos keybinds padrão do example Umbriel (Mod+Return → kitty)
pac_install kitty foot || pac_install foot || true
pac_install fastfetch || warn "fastfetch falhou (terminal ainda abre sem banner)"

install_prefer umbriel-git || die "falha umbriel-git"
# Dependência do umbriel-git; garantir portal
install_prefer xdg-desktop-portal-umbriel-git || true
install_prefer noctalia-greeter || die "falha noctalia-greeter"

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

# Sync passwordless opcional (greeter ≥ 1.5.0) — docs Sync with Noctalia
if command -v noctalia-greeter >/dev/null; then
  if noctalia-greeter passwordless-sync enable "$REAL_USER" 2>/dev/null; then
    ok "passwordless-sync habilitado para $REAL_USER"
  else
    warn "passwordless-sync não aplicado (ok — Sync pedirá senha admin)"
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
