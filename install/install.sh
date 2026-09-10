#!/usr/bin/env bash
# Pandora Noctalia — post-install (Arch puro + linux-zen + nvidia-open-dkms)
#
# Uso (após archinstall, como root ou via sudo):
#   cd /caminho/PandoraProject
#   sudo ./install/install.sh
#
# Módulos individuais:
#   sudo ./install/install.sh 30-gpu-hybrid
#
# Dry validation (sem instalar):
#   ./install/validate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

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

run_module() {
  local name="$1"
  local file="$ROOT/modules/${name}.sh"
  [[ -f "$file" ]] || die "Módulo inexistente: $name ($file)"
  log "── Módulo $name ──"
  # shellcheck disable=SC1090
  bash "$file"
}

if [[ $# -gt 0 ]]; then
  for m in "$@"; do
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
