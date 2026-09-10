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
      systemctl disable --now "$unit" 2>/dev/null || systemctl disable "$unit" 2>/dev/null || true
    fi
  fi
  for dm in sddm gdm gdm3 lightdm lxdm ly; do
    if [[ "$dm.service" == "${unit:-}" ]]; then
      continue
    fi
    systemctl disable --now "$dm.service" 2>/dev/null || systemctl disable "$dm.service" 2>/dev/null || true
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
    ok "Umbriel já autostarta noctalia"
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
  nvidia_pci="$(lspci -Dn 2>/dev/null | awk '/ 10de:.*( 0300| 0302| 0380)/ {print $1; exit}')"
  intel_pci="$(lspci -Dn 2>/dev/null | awk '/ 8086:.*( 0300| 0302| 0380)/ {print $1; exit}')"
  if [[ -z "$nvidia_pci" || -z "$intel_pci" ]]; then
    warn "DRM ignore NVIDIA omitido (iGPU Intel não detectada ainda — ligue Hybrid no BIOS)"
    return 0
  fi
  if grep -qE 'ignored_pci_addresses' "$conf"; then
    ok "Umbriel [drm] já configurado"
    return 0
  fi
  cat >>"$conf" <<EOF

# Pandora: compositor na iGPU; dGPU sob demanda (prime-run / obs-nvidia)
# Docs: https://docs.noctalia.dev/umbriel/configuration/#drm-devices
[drm]
ignored_pci_addresses = ["${nvidia_pci}"]
EOF
  ok "Umbriel ignora NVIDIA PCI ${nvidia_pci} (compositor na Intel ${intel_pci})"
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
    ok "Mantendo Umbriel config existente"
  fi

  ensure_umbriel_autostart "$conf"
  ensure_umbriel_hybrid_drm "$conf"

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
      || warn "umbriel validate reportou problemas — revise $conf"
  fi
}

write_greetd_config() {
  local greeter_bin="$1"
  mkdir -p /etc/greetd
  backup_file /etc/greetd/config.toml
  # Docs: greetd must launch noctalia-greeter-session (full path), user=greeter.
  # Defaults de sessão/usuário ficam em greeter.toml (evita quebrar Name= com espaços).
  cat >/etc/greetd/config.toml <<EOF
# Pandora Noctalia — https://docs.noctalia.dev/greeter/installation/
[terminal]
vt = 1

[default_session]
command = "${greeter_bin}"
user = "greeter"
EOF
  ok "greetd → ${greeter_bin}"
}

write_greeter_defaults() {
  local session_name="$1"
  local f=/var/lib/noctalia-greeter/greeter.toml
  mkdir -p /var/lib/noctalia-greeter

  if [[ ! -f "$f" ]]; then
    cat >"$f" <<EOF
# Pandora defaults — https://docs.noctalia.dev/greeter/configuration/
# Name= exato do .desktop (não o basename do arquivo)
[user]
default = "${REAL_USER}"

[session]
default = "${session_name}"
EOF
  else
    # Atualiza só [user].default e [session].default sem apagar o resto (setup/sync)
    REAL_USER="$REAL_USER" SESSION_NAME="$session_name" GREETER_TOML="$f" python3 - <<'PY'
import os, re
path = os.environ["GREETER_TOML"]
user = os.environ["REAL_USER"]
session = os.environ["SESSION_NAME"]
text = open(path, encoding="utf-8").read()

def set_section_key(text: str, section: str, key: str, value: str) -> str:
    line = f'{key} = "{value}"'
    m = re.search(rf'(\[{re.escape(section)}\][^\[]*)', text, re.S)
    if not m:
        return text.rstrip() + f"\n\n[{section}]\n{line}\n"
    body = m.group(1)
    if re.search(rf'^{re.escape(key)}\s*=', body, re.M):
        body = re.sub(rf'^{re.escape(key)}\s*=.*$', line, body, count=1, flags=re.M)
    else:
        body = body.rstrip() + f"\n{line}\n"
    return text[: m.start(1)] + body + text[m.end(1) :]

text = set_section_key(text, "user", "default", user)
text = set_section_key(text, "session", "default", session)
open(path, "w", encoding="utf-8").write(text)
PY
  fi
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

# Setup oficial do pacote (PAM + /var/lib/noctalia-greeter + greeter.toml)
# Path documentado em PACKAGING.md / AUR .install
setup_ran=0
for s in \
  /usr/share/noctalia-greeter/setup_greeter_system.sh \
  /usr/local/share/noctalia-greeter/setup_greeter_system.sh
do
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

# Habilita greetd; --now só se não houver sessão gráfica ativa (evita matar o DE atual)
systemctl enable greetd.service
if [[ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
  systemctl enable --now greetd.service || warn "não foi possível startar greetd agora"
else
  warn "Sessão gráfica ativa — greetd enabled; fará cutover no próximo boot"
fi
systemctl set-default graphical.target || true

ok "Noctalia + Umbriel + Greeter configurados (reboot para login)"
