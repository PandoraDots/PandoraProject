#!/usr/bin/env bash
# Verifica pacotes, configs e serviços após instalação PandoraProject.
# Gera relatório em texto para análise (incl. IA).
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PANDORA_ROOT

PANDORA_MODEL="${PANDORA_MODEL:-phn16-72}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pandora"
MANIFEST="$PANDORA_ROOT/install/verify-manifest.json"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model) PANDORA_MODEL="$2"; shift 2 ;;
        --model=*) PANDORA_MODEL="${1#*=}"; shift ;;
        --log-dir) LOG_DIR="$2"; shift 2 ;;
        --manifest) MANIFEST="$2"; shift 2 ;;
        -h|--help)
            echo "Uso: $0 [--model phn16-72] [--log-dir DIR] [--manifest FILE]"
            exit 0
            ;;
        *) echo "Argumento desconhecido: $1" >&2; exit 1 ;;
    esac
done
export PANDORA_MODEL

source "$PANDORA_ROOT/install/lib.sh"

MODEL_FILE="$(model_config "$PANDORA_MODEL")"
mkdir -p "$LOG_DIR"

TS="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/verify-install-${TS}.log"
LOG_LATEST="$LOG_DIR/verify-install-latest.log"

declare -i COUNT_OK=0 COUNT_WARN=0 COUNT_FAIL=0 COUNT_INFO=0

report() {
    local level="$1"
    local msg="$2"
    printf '[%s] %s\n' "$level" "$msg" >>"$LOG_FILE"
    case "$level" in
        OK)   COUNT_OK+=1 ;;
        WARN) COUNT_WARN+=1; printf '\033[1;33m[WARN]\033[0m %s\n' "$msg" >&2 ;;
        FAIL) COUNT_FAIL+=1; printf '\033[1;31m[FAIL]\033[0m %s\n' "$msg" >&2 ;;
        INFO) COUNT_INFO+=1; printf '\033[1;34m[INFO]\033[0m %s\n' "$msg" ;;
    esac
}

expand_path() {
    local p="$1"
    p="${p//\~/$HOME}"
    p="${p//\$HOME/$HOME}"
    p="${p//\$PANDORA_ROOT/$PANDORA_ROOT}"
    printf '%s' "$p"
}

check_pkg() {
    local pkg="$1" level="${2:-required}"
    local alias resolved
    alias="$(pandora_pkg_alias "$pkg")"
    [[ -n "$alias" ]] && pkg="$alias"
    if pacman -Qi "$pkg" &>/dev/null; then
        report OK "pacote: $pkg"
        return 0
    fi
    if [[ "$level" == "optional" ]]; then
        report WARN "pacote (opcional): $pkg"
    else
        report FAIL "pacote: $pkg"
    fi
    return 1
}

check_cmd() {
    local cmd="$1" level="${2:-required}"
    if command -v "$cmd" &>/dev/null; then
        report OK "comando: $cmd"
        return 0
    fi
    if [[ "${INSTALL_INCOMPLETE:-0}" -eq 1 && "$cmd" == "caelestia" ]]; then
        report FAIL "comando: $cmd (bloqueia passos 40-90 — rode resume-install.sh)"
        return 1
    fi
    if [[ "$level" == "optional" ]]; then
        report WARN "comando (opcional): $cmd"
    else
        report FAIL "comando: $cmd"
    fi
    return 1
}

check_file() {
    local path="$1"
    local level="${2:-required}"
    path="$(expand_path "$path")"
    if [[ -e "$path" || -L "$path" ]]; then
        report OK "arquivo: $path"
        return 0
    fi
    if [[ "${INSTALL_INCOMPLETE:-0}" -eq 1 && "$level" == "required" ]]; then
        report WARN "arquivo (pendente pós-resume): $path"
        return 1
    fi
    if [[ "$level" == "optional" ]]; then
        report WARN "arquivo (opcional): $path"
    else
        report FAIL "arquivo: $path"
    fi
    return 1
}

check_file_contains() {
    local path pattern label
    path="$(expand_path "$1")"
    pattern="$2"
    label="${3:-$pattern}"
    if [[ ! -f "$path" ]]; then
        report FAIL "conteúdo ($label): $path ausente"
        return 1
    fi
    if grep -qF "$pattern" "$path" 2>/dev/null; then
        report OK "conteúdo ($label): $path"
        return 0
    fi
    report FAIL "conteúdo ($label): padrão '$pattern' não encontrado em $path"
    return 1
}

check_systemd_unit() {
    local unit="$1" scope="${2:-system}" level="${3:-required}"
    local enabled=0
    if [[ "$scope" == "user" ]]; then
        systemctl --user is-enabled "$unit" &>/dev/null && enabled=1
    else
        systemctl is-enabled "$unit" &>/dev/null && enabled=1
    fi
    if [[ $enabled -eq 1 ]]; then
        report OK "systemd ($scope): $unit habilitado"
        return 0
    fi
    if [[ "$level" == "optional" ]]; then
        report WARN "systemd ($scope, opcional): $unit não habilitado"
    else
        report FAIL "systemd ($scope): $unit não habilitado"
    fi
    return 1
}

check_cachyos_drivers() {
    is_cachyos || return 0
    local -a raw=() pkgs=()
    export PANDORA_MODEL_FILE="$MODEL_FILE"
    mapfile -t raw < <(jq -r '
        (.packages.nvidia[]?),
        (.packages.intel[]?),
        (.packages.power[]?),
        (.packages.kernel_headers? // empty)
    ' "$MODEL_FILE")
    mapfile -t pkgs < <(cachyos_resolve_packages "${raw[@]}")
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        report FAIL "drivers CachyOS: nenhum pacote resolvido"
        return 1
    fi
    local pkg
    for pkg in "${pkgs[@]}"; do
        check_pkg "$pkg" required || true
    done
}

check_sddm() {
    local theme keyboard
    theme="$(jq -r '.sddm.theme // empty' "$MANIFEST")"
    keyboard="$(jq -r '.sddm.keyboard // empty' "$MANIFEST")"

    if [[ -n "$theme" && -d "/usr/share/sddm/themes/$theme" ]]; then
        report OK "sddm: tema $theme instalado"
    else
        report FAIL "sddm: tema ${theme:-caelestia} ausente"
    fi

    if [[ -f /etc/sddm.conf.d/pandora.conf ]] && grep -q "Current=$theme" /etc/sddm.conf.d/pandora.conf 2>/dev/null; then
        report OK "sddm: pandora.conf com tema $theme"
    else
        report WARN "sddm: /etc/sddm.conf.d/pandora.conf ausente ou tema diferente"
    fi

    if [[ -n "$keyboard" ]]; then
        local kmap
        kmap="$(localectl status 2>/dev/null | awk '/VC Keymap:|X11 Layout:/ {print $3; exit}' || true)"
        if [[ "$kmap" == *"br"* ]]; then
            report OK "teclado: $keyboard (localectl)"
        else
            report WARN "teclado: esperado $keyboard, localectl=$kmap"
        fi
    fi
}

check_scheme() {
    local expected scheme_file
    expected="$(jq -r '.scheme.name // "inferno"' "$MANIFEST")"
    scheme_file="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/scheme.json"
    if [[ ! -f "$scheme_file" ]]; then
        report FAIL "scheme: $scheme_file ausente"
        return 1
    fi
    if jq -e --arg n "$expected" '.name == $n' "$scheme_file" &>/dev/null; then
        report OK "scheme: $expected em $scheme_file"
        return 0
    fi
    local actual
    actual="$(jq -r '.name // "?"' "$scheme_file" 2>/dev/null)"
    report FAIL "scheme: esperado $expected, encontrado $actual"
    return 1
}

check_model_apps() {
    local pkg
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        check_pkg "$pkg" optional || true
    done < <(jq -r '.packages.apps[]?' "$MODEL_FILE" 2>/dev/null)
}

check_runtime() {
    if command -v hyprctl &>/dev/null && hyprctl monitors &>/dev/null 2>&1; then
        report OK "runtime: sessão Hyprland ativa"
        if hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.class | startswith("pandora-"))' &>/dev/null; then
            report OK "runtime: janelas pandora-* detectadas"
        else
            report INFO "runtime: dashboard pandora-* não detectado (normal pós-install em TTY)"
        fi
    else
        report INFO "runtime: Hyprland inativo — dashboard só verificável após login"
    fi

    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        report INFO "runtime: $line"
    done < <(jq -r '.runtime_info[]?' "$MANIFEST" 2>/dev/null)
}

# --- Cabeçalho do relatório ---
{
    printf 'PandoraProject — verificação pós-instalação\n'
    printf 'Data: %s\n' "$(date -Iseconds)"
    printf 'Modelo: %s\n' "$PANDORA_MODEL"
    printf 'Manifest: %s\n' "$MANIFEST"
    printf 'Host: %s\n' "$(uname -n)"
    printf 'CachyOS: %s\n' "$(is_cachyos && echo sim || echo não)"
    printf '%s\n' '---'
} >"$LOG_FILE"

INSTALL_INCOMPLETE=0
if ! command -v caelestia &>/dev/null; then
    INSTALL_INCOMPLETE=1
    report INFO "instalação incompleta: comando caelestia ausente — configs/serviços user provavelmente pendentes"
    report INFO "ação sugerida: bash $PANDORA_ROOT/scripts/resume-install.sh"
fi

# --- Pacotes do manifest ---
while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    check_pkg "$pkg" required || true
done < <(jq -r '.packages.required[]?' "$MANIFEST")

while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    check_pkg "$pkg" optional || true
done < <(jq -r '.packages.optional[]?' "$MANIFEST")

if jq -e '.packages.cachyos_drivers == true' "$MANIFEST" &>/dev/null; then
    check_cachyos_drivers || true
fi

check_model_apps || true

# --- Comandos ---
while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    check_cmd "$cmd" required || true
done < <(jq -r '.commands.required[]?' "$MANIFEST")

while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    check_cmd "$cmd" optional || true
done < <(jq -r '.commands.optional[]?' "$MANIFEST")

# --- Arquivos ---
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    check_file "$f" required || true
done < <(jq -r '.files.required[]?' "$MANIFEST")

while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    f="$(expand_path "$f")"
    f="${f//\$PANDORA_ROOT/$PANDORA_ROOT}"
    check_file "$f" optional || true
done < <(jq -r '.files.optional[]?' "$MANIFEST")

# --- Conteúdo de arquivos ---
while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == "null" ]] && continue
    path="$(jq -r '.path' <<<"$entry")"
    pattern="$(jq -r '.pattern' <<<"$entry")"
    label="$(jq -r '.label // .pattern' <<<"$entry")"
    check_file_contains "$path" "$pattern" "$label" || true
done < <(jq -c '.file_contains[]?' "$MANIFEST" 2>/dev/null)

# --- systemd ---
while IFS= read -r unit; do
    [[ -z "$unit" ]] && continue
    check_systemd_unit "$unit" system required || true
done < <(jq -r '.systemd_system.required[]?' "$MANIFEST")

while IFS= read -r unit; do
    [[ -z "$unit" ]] && continue
    check_systemd_unit "$unit" system optional || true
done < <(jq -r '.systemd_system.optional[]?' "$MANIFEST")

while IFS= read -r unit; do
    [[ -z "$unit" ]] && continue
    check_systemd_unit "$unit" user required || true
done < <(jq -r '.systemd_user.required[]?' "$MANIFEST")

while IFS= read -r unit; do
    [[ -z "$unit" ]] && continue
    check_systemd_unit "$unit" user optional || true
done < <(jq -r '.systemd_user.optional[]?' "$MANIFEST")

# --- SDDM, scheme, runtime ---
check_sddm || true
check_scheme || true
check_runtime || true

# --- Resumo ---
{
    printf '%s\n' '---'
    printf 'RESUMO: OK=%s WARN=%s FAIL=%s INFO=%s\n' "$COUNT_OK" "$COUNT_WARN" "$COUNT_FAIL" "$COUNT_INFO"
} >>"$LOG_FILE"

ln -sfn "$LOG_FILE" "$LOG_LATEST"

printf '\033[1;34m[Pandora]\033[0m Verificação concluída: OK=%s WARN=%s FAIL=%s INFO=%s\n' \
    "$COUNT_OK" "$COUNT_WARN" "$COUNT_FAIL" "$COUNT_INFO"
log "Relatório: $LOG_FILE"
log "Último relatório: $LOG_LATEST"

[[ $COUNT_FAIL -eq 0 ]]
