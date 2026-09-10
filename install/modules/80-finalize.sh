#!/usr/bin/env bash
# 80 — Finalize: sanity checks, reminders (no hostname/locale/tz changes)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user

log "Finalizando"

# PATH tip for user local bins
bashrc="$REAL_HOME/.bashrc"
if [[ -f "$bashrc" ]] || true; then
  if [[ ! -f "$bashrc" ]] || ! grep -q '\.local/bin' "$bashrc" 2>/dev/null; then
    cat >>"$bashrc" <<'EOF'

# Pandora Noctalia
export PATH="$HOME/.local/bin:$PATH"
EOF
    chown "$REAL_UID:$REAL_GID" "$bashrc"
  fi
fi

# Ensure paru configured
ensure_paru || true
configure_paru || true

cat <<EOF

╔══════════════════════════════════════════════════════════════╗
║  Pandora Noctalia — instalação concluída                     ║
╠══════════════════════════════════════════════════════════════╣
║  Usuário:   $REAL_USER                                       ║
║  Sessão:    Umbriel + Noctalia (greetd / noctalia-greeter)   ║
║  GPU:       EnvyControl hybrid + prime-run / obs-nvidia      ║
║  Kernel:    linux-zen + nvidia-open-dkms (assumido)          ║
║                                                              ║
║  Próximos passos:                                            ║
║  1. reboot                                                   ║
║  2. Login no greeter (sessão Umbriel)                        ║
║  3. GameMode: configure depois (pacote já instalado)         ║
║  4. OBS: use "OBS Studio (NVIDIA)" + encoder NVENC           ║
║  5. Sync greeter wallpaper/palette via Noctalia se quiser    ║
║                                                              ║
║  Hostname / timezone / locale: NÃO alterados                 ║
╚══════════════════════════════════════════════════════════════╝
EOF

ok "Finalize ok"
