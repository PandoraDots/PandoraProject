#!/usr/bin/env bash
# Pandora Noctalia — post-install (Arch puro + linux-zen + nvidia-open-dkms)
#
# Uso (após archinstall, como root ou via sudo):
#   cd /caminho/PandoraProject
#   sudo ./install/install.sh
#
# Módulos individuais:
#   sudo ./install/install.sh 30-gpu-hybrid
#   sudo ./install/install.sh --refresh-stack 50-noctalia-stack
#
# Dry validation (sem instalar):
#   ./install/validate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Start logging before common.sh initialization and module execution.
# shellcheck source=lib/logging.sh
source "$ROOT/lib/logging.sh"
start_install_log
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

source "$ROOT/lib/login.sh"

OFFER_LOGIN=0
need_root
resolve_user

MODULES=(
  00-preflight
  10-system-tuning
  20-bootloader
  30-gpu-hybrid
  40-perfectsense
  50-noctalia-stack
  60-dev
  70-apps
  80-finalize
)

# Flags (sudo descarta env do usuário — preferir --refresh-stack a PANDORA_*=1 sudo …)
MODULE_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --refresh-stack)
      export PANDORA_REFRESH_STACK=1
      log "Flag --refresh-stack → PANDORA_REFRESH_STACK=1"
      ;;
    -h|--help)
      cat <<'EOF'
Uso: sudo ./install/install.sh [opções] [módulo…]

  (sem módulo)              roda todos os módulos na ordem
  50 | 50-noctalia-stack    só a stack Noctalia/Umbriel/Greeter
  --refresh-stack           recompila noctalia/greeter/umbriel-git (AUR tip)
                            antes de reparar configs (use com o módulo 50)

Nota: `VAR=1 sudo ./install/...` NÃO passa VAR ao root. Prefira a flag
ou `sudo env PANDORA_REFRESH_STACK=1 ./install/install.sh 50`.
EOF
      finish_install_log 0 return
      exit 0
      ;;
    -*)
      die "Opção desconhecida: $arg (tente --help)"
      ;;
    *)
      MODULE_ARGS+=("$arg")
      ;;
  esac
done

run_module() {
  local name="$1"
  local file="$ROOT/modules/${name}.sh"
  CURRENT_MODULE="$name"
  [[ -f "$file" ]] || die "Módulo inexistente: $name ($file)"
  log "── Módulo $name — $(date --iso-8601=seconds) ──"
  # Exporta flags para o bash filho que carrega o módulo.
  # shellcheck disable=SC1090
  bash "$file"
  case "$name" in
    50-noctalia-stack|80-finalize) OFFER_LOGIN=1 ;;
  esac
  CURRENT_MODULE="nenhum"
}

if ((${#MODULE_ARGS[@]} > 0)); then
  for m in "${MODULE_ARGS[@]}"; do
    # aceita 30 ou 30-gpu-hybrid
    if [[ "$m" =~ ^[0-9]+$ ]]; then
      match="$(printf '%s\n' "${MODULES[@]}" | grep -E "^${m}-" | head -1 || true)"
      [[ -n "$match" ]] || die "Módulo numérico não encontrado: $m"
      run_module "$match"
    else
      run_module "$m"
    fi
  done
else
  for m in "${MODULES[@]}"; do
    run_module "$m"
  done
fi

ok "install.sh terminou"

# Fechar e descarregar o log antes da última interação e da troca de sessão.
finish_install_log 0 return
if ((OFFER_LOGIN)); then
  offer_login
fi
