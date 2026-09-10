#!/usr/bin/env bash
# 50 — Noctalia Shell + Umbriel + Greeter (greetd) — única sessão desktop
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user

log "Stack Noctalia + Umbriel + Greeter"

pac_install greetd dbus polkit noctalia
# Portal + compositor (AUR no Arch puro)
install_prefer umbriel-git || die "falha umbriel-git"
install_prefer xdg-desktop-portal-umbriel-git || pac_install xdg-desktop-portal || true
install_prefer noctalia-greeter || die "falha noctalia-greeter"

# Extras úteis ao shell
pac_install \
  xdg-desktop-portal xdg-desktop-portal-gtk \
  brightnessctl playerctl \
  grim slurp wl-clipboard \
  ffmpeg thumbnailer

# Setup greeter system state se o pacote trouxer o script
for s in \
  /usr/share/noctalia-greeter/setup_greeter_system.sh \
  /usr/lib/noctalia-greeter/setup_greeter_system.sh \
  /usr/share/noctalia-greeter/scripts/setup_greeter_system.sh
do
  if [[ -x "$s" ]]; then
    log "Rodando $s"
    bash "$s" || warn "setup_greeter_system.sh retornou erro"
    break
  fi
done

# Garante usuário greeter
if ! id greeter &>/dev/null; then
  useradd -r -m -d /var/lib/greetd -s /usr/bin/nologin greeter 2>/dev/null \
    || useradd -r -d /var/lib/noctalia-greeter -s /usr/bin/nologin greeter || true
fi
mkdir -p /var/lib/noctalia-greeter
chown -R greeter:greeter /var/lib/noctalia-greeter 2>/dev/null || true

greeter_bin="$(command -v noctalia-greeter-session || true)"
[[ -n "$greeter_bin" ]] || die "noctalia-greeter-session não encontrado no PATH"

# Descobre Name= da sessão Umbriel
session_name="Umbriel"
desktop_file="$(find /usr/share/wayland-sessions /usr/local/share/wayland-sessions \
  -name '*umbriel*.desktop' 2>/dev/null | head -1 || true)"
if [[ -n "$desktop_file" ]]; then
  session_name="$(grep -E '^Name=' "$desktop_file" | head -1 | cut -d= -f2-)"
  ok "Sessão Wayland: $desktop_file (Name=$session_name)"
else
  warn "Desktop file umbriel não encontrado ainda — usando Name=Umbriel"
fi

log "Configurando /etc/greetd/config.toml → noctalia-greeter + sessão Umbriel"
mkdir -p /etc/greetd
backup_file /etc/greetd/config.toml
cat >/etc/greetd/config.toml <<EOF
# Pandora Noctalia — gerado por install/modules/50-noctalia-stack.sh
[terminal]
vt = 1

[default_session]
command = "${greeter_bin} -- --session ${session_name} --user ${REAL_USER}"
user = "greeter"
EOF

# greeter.toml default user/session (se suportado)
if [[ -d /var/lib/noctalia-greeter ]]; then
  if [[ ! -f /var/lib/noctalia-greeter/greeter.toml ]]; then
    cat >/var/lib/noctalia-greeter/greeter.toml <<EOF
# Pandora defaults
[user]
default = "${REAL_USER}"

[session]
default = "${session_name}"
EOF
    chown greeter:greeter /var/lib/noctalia-greeter/greeter.toml 2>/dev/null || true
  fi
fi

# Umbriel: copiar config empacotada + autostart Noctalia
as_user mkdir -p "$REAL_HOME/.config/umbriel"
umbriel_conf="$REAL_HOME/.config/umbriel/config.toml"
if [[ ! -f "$umbriel_conf" ]]; then
  for src in /usr/share/umbriel/config.toml /usr/local/share/umbriel/config.toml; do
    if [[ -f "$src" ]]; then
      cp "$src" "$umbriel_conf"
      break
    fi
  done
fi
if [[ ! -f "$umbriel_conf" ]]; then
  cat >"$umbriel_conf" <<'EOF'
# Pandora Noctalia — minimal Umbriel config
# Docs: https://docs.noctalia.dev/umbriel/configuration/

[general]
autostart = ["noctalia"]
mod_key = "Super"
xwayland = true

[environment]
ELECTRON_OZONE_PLATFORM_HINT = "auto"
SDL_VIDEODRIVER = "wayland"
EOF
else
  # Garante noctalia no general.autostart se ainda não estiver
  if ! grep -qE 'noctalia' "$umbriel_conf"; then
    if grep -qE '^\[general\]' "$umbriel_conf"; then
      if grep -qE '^\s*autostart\s*=' "$umbriel_conf"; then
        sed -i 's/^\(\s*autostart\s*=\s*\[\)/\1"noctalia", /' "$umbriel_conf"
      else
        sed -i '/^\[general\]/a autostart = ["noctalia"]' "$umbriel_conf"
      fi
    else
      printf '\n[general]\nautostart = ["noctalia"]\n' >>"$umbriel_conf"
    fi
  fi
fi
chown "$REAL_UID:$REAL_GID" "$umbriel_conf"

# Desliga outros DMs se existirem
for dm in sddm gdm lightdm lxdm; do
  systemctl disable "$dm.service" 2>/dev/null || true
done

systemd_enable greetd.service
# Não iniciar greetd agora se estivermos em sessão gráfica ativa — enable only is safer mid-install
systemctl set-default graphical.target || true

ok "Noctalia + Umbriel + Greeter configurados (reboot para login)"
