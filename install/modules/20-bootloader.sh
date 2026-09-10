#!/usr/bin/env bash
# 20 — Bootloader: ideal = systemd-boot timeout 0; se GRUB, timeout 0
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root

bl="$(detect_bootloader)"
log "Bootloader detectado: $bl"

case "$bl" in
  systemd-boot)
    conf=""
    for c in /boot/loader/loader.conf /efi/loader/loader.conf /boot/efi/loader/loader.conf; do
      if [[ -f "$c" ]] || [[ -d "$(dirname "$c")" ]]; then
        conf="$c"
        break
      fi
    done
    [[ -n "$conf" ]] || conf=/boot/loader/loader.conf
    mkdir -p "$(dirname "$conf")"
    if [[ -f "$conf" ]]; then
      backup_file "$conf"
      if grep -qE '^timeout' "$conf"; then
        sed -i 's/^timeout.*/timeout 0/' "$conf"
      else
        printf 'timeout 0\n' >>"$conf"
      fi
      grep -qE '^default' "$conf" || printf 'default @saved\n' >>"$conf" || true
    else
      write_if_changed "$conf" $'default @saved\ntimeout 0\nconsole-mode max\neditor no\n'
    fi
    ok "systemd-boot: timeout 0 em $conf"
    ;;
  grub)
    [[ -f /etc/default/grub ]] || die "GRUB detectado sem /etc/default/grub"
    backup_file /etc/default/grub
    if grep -qE '^GRUB_TIMEOUT=' /etc/default/grub; then
      sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    else
      printf '\nGRUB_TIMEOUT=0\n' >>/etc/default/grub
    fi
    # menu oculto ainda mais rápido (ESC mostra)
    if grep -qE '^#?GRUB_TIMEOUT_STYLE=' /etc/default/grub; then
      sed -i 's/^#\?GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
    else
      printf 'GRUB_TIMEOUT_STYLE=hidden\n' >>/etc/default/grub
    fi
    # Também cobre GRUB_TIMEOUT='5' / "5" (alguns defaults)
    sed -i -E "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/" /etc/default/grub
    sed -i -E "s/^#?GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/" /etc/default/grub
    if command -v grub-mkconfig >/dev/null; then
      if [[ -d /boot/grub ]]; then
        grub-mkconfig -o /boot/grub/grub.cfg
      elif [[ -d /boot/grub2 ]]; then
        grub-mkconfig -o /boot/grub2/grub.cfg
      else
        warn "grub.cfg path desconhecido — edite GRUB_TIMEOUT=0 manualmente"
      fi
    fi
    ok "GRUB: timeout 0 (para boot mais rápido no próximo install, prefira systemd-boot no archinstall)"
    ;;
  *)
    warn "Bootloader desconhecido — pulando. No archinstall, escolha systemd-boot (timeout 0)."
    ;;
esac
