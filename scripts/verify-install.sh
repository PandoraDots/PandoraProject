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
        report FAIL "comando: $cmd (bloqueador — rode: bash $PANDORA_ROOT/scripts/resume-install.sh)"
        return 1
    fi
    if [[ "${INSTALL_INCOMPLETE:-0}" -eq 1 && "$level" == "required" && "$cmd" != "caelestia" ]]; then
        report WARN "comando (pendente pós-resume): $cmd"
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
        if [[ "${INSTALL_INCOMPLETE:-0}" -eq 1 ]]; then
            report WARN "conteúdo (pendente pós-resume, $label): $path ausente"
        else
            report FAIL "conteúdo ($label): $path ausente"
        fi
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
    if [[ "${INSTALL_INCOMPLETE:-0}" -eq 1 && "$scope" == "user" && "$level" == "required" ]]; then
        report WARN "systemd ($scope, pendente pós-resume): $unit não habilitado"
        return 1
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
    local theme keyboard dest_bg src_wall session_desktop session_uwsm
    theme="$(jq -r '.sddm.theme // empty' "$MANIFEST")"
    keyboard="$(jq -r '.sddm.keyboard // empty' "$MANIFEST")"
    dest_bg="/usr/share/sddm/themes/caelestia/assets/background"
    src_wall="${PANDORA_ROOT}/Wallpapers/whitekat.jpg"
    session_desktop="/usr/local/share/wayland-sessions/hyprland.desktop"
    session_uwsm="/usr/local/share/wayland-sessions/hyprland-uwsm.desktop"

    if [[ -n "$theme" && -d "/usr/share/sddm/themes/$theme" ]]; then
        report OK "sddm: tema $theme instalado"
    else
        report FAIL "sddm: tema ${theme:-caelestia} ausente"
    fi

    if pacman -Qi caelestia-sddm-locklike-git &>/dev/null; then
        local pkg_url
        pkg_url="$(pacman -Qi caelestia-sddm-locklike-git 2>/dev/null | awk -F': ' '/^URL/{print $2; exit}')"
        if [[ "$pkg_url" == *PandoraDots/caelestia-sddm* ]]; then
            report OK "sddm: pacote locklike URL PandoraDots"
        else
            report FAIL "sddm: pacote locklike URL=$pkg_url (esperado PandoraDots)"
        fi
    else
        report FAIL "sddm: caelestia-sddm-locklike-git não instalado"
    fi

    if [[ -f /etc/sddm.conf.d/pandora.conf ]] && grep -q "Current=$theme" /etc/sddm.conf.d/pandora.conf 2>/dev/null; then
        report OK "sddm: pandora.conf com tema $theme"
    else
        report WARN "sddm: /etc/sddm.conf.d/pandora.conf ausente ou tema diferente"
    fi

    if [[ -f /etc/sddm.conf.d/pandora.conf ]] && grep -qE '^DisplayServer=x11-user$' /etc/sddm.conf.d/pandora.conf; then
        report OK "sddm: DisplayServer=x11-user"
    else
        report FAIL "sddm: DisplayServer deveria ser x11-user (evita falha weston)"
    fi

    if [[ -f "$session_desktop" ]] && grep -qE '^Exec=/usr/bin/start-hyprland$' "$session_desktop"; then
        report OK "sddm: /usr/local/.../hyprland.desktop = start-hyprland"
    else
        report FAIL "sddm: falta /usr/local/.../hyprland.desktop com Exec=start-hyprland"
    fi

    if [[ -f "$session_uwsm" ]] && grep -qE '^Hidden=true$' "$session_uwsm"; then
        report OK "sddm: hyprland-uwsm.desktop Hidden=true"
    else
        report WARN "sddm: hyprland-uwsm.desktop não oculto em /usr/local"
    fi

    if [[ -x /usr/local/lib/pandora/wayland-session ]]; then
        report OK "sddm: SessionCommand wrapper /usr/local/lib/pandora/wayland-session"
    else
        report FAIL "sddm: wrapper /usr/local/lib/pandora/wayland-session ausente"
    fi

    if [[ -f /etc/sddm.conf.d/pandora.conf ]] \
        && grep -qE '^SessionCommand=/usr/local/lib/pandora/wayland-session$' /etc/sddm.conf.d/pandora.conf; then
        report OK "sddm: pandora.conf SessionCommand=pandora wrapper"
    else
        report FAIL "sddm: pandora.conf sem SessionCommand pandora (ainda usa fish --login)"
    fi

    if [[ -f /etc/sddm.conf.d/pandora.conf ]] \
        && grep -qE '^DefaultSession=hyprland.desktop$' /etc/sddm.conf.d/pandora.conf; then
        report OK "sddm: DefaultSession=hyprland.desktop"
    else
        report FAIL "sddm: DefaultSession deveria ser hyprland.desktop"
    fi

    if [[ -f "$src_wall" && -f "$dest_bg" ]] && command -v md5sum &>/dev/null; then
        if [[ "$(md5sum "$src_wall" | awk '{print $1}')" == "$(md5sum "$dest_bg" | awk '{print $1}')" ]]; then
            report OK "sddm: login wallpaper = whitekat"
        else
            report FAIL "sddm: background != whitekat — rode sync_sddm_theme"
        fi
    elif [[ ! -f "$src_wall" ]]; then
        report WARN "sddm: whitekat.jpg ausente em Wallpapers/"
    else
        report FAIL "sddm: assets/background ausente"
    fi

    if systemctl --user is-enabled pandora-gpu-profile.path &>/dev/null; then
        report FAIL "gpu: pandora-gpu-profile.path habilitado (loop) — disable --now"
    else
        report OK "gpu: pandora-gpu-profile.path desabilitado"
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
        if [[ "${INSTALL_INCOMPLETE:-0}" -eq 1 ]]; then
            report WARN "scheme (pendente pós-resume): $scheme_file ausente"
        else
            report FAIL "scheme: $scheme_file ausente"
        fi
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

check_hypr_user_monitor() {
    local path="${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/hypr-user.lua"
    if [[ ! -f "$path" ]]; then
        if [[ "${INSTALL_INCOMPLETE:-0}" -eq 1 ]]; then
            report WARN "hypr monitor (pendente pós-resume): $path ausente"
        else
            report FAIL "hypr monitor: $path ausente"
        fi
        return 1
    fi

    local pos
    pos="$(grep -E '^\s*position\s*=' "$path" | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/' || true)"
    if [[ -z "$pos" ]]; then
        report WARN "hypr monitor: nenhum position= em $path"
        return 0
    fi

    # Hyprland exige auto* ou COORDSxCOORDS (ex.: 0x0) — "0,0" quebra a sessão/shell
    if [[ "$pos" =~ ^auto(-center)?(-(up|down|left|right))?$ || "$pos" =~ ^-?[0-9]+x-?[0-9]+$ ]]; then
        report OK "hypr monitor: position='$pos' válido"
        return 0
    fi
    report FAIL "hypr monitor: position='$pos' inválido em $path (use '0x0' ou 'auto', não '0,0')"
    return 1
}

check_hypr_config_errors() {
    local errors
    if ! errors="$(hyprctl configerrors 2>/dev/null)"; then
        report WARN "runtime: hyprctl configerrors indisponível"
        return 1
    fi
    errors="$(printf '%s' "$errors" | sed '/^[[:space:]]*$/d')"
    if [[ -z "$errors" ]]; then
        report OK "runtime: hyprctl configerrors limpo"
        return 0
    fi
    report FAIL "runtime: erros na config Hyprland (shell/taskbar podem falhar)"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        report FAIL "runtime: configerror: $line"
    done <<<"$errors"
    return 1
}

check_caelestia_shell_config() {
    local conf
    if conf="$(pandora_shell_qsconf 2>/dev/null)"; then
        report OK "arquivo: shell caelestia ($conf)"
        return 0
    fi
    if [[ "${INSTALL_INCOMPLETE:-0}" -eq 1 ]]; then
        report WARN "arquivo (pendente pós-resume): /etc/xdg/quickshell/caelestia/shell.qml"
    else
        report FAIL "arquivo: shell caelestia ausente (/etc/xdg/quickshell/caelestia/shell.qml) — rode install/30-caelestia-build.sh"
    fi
    return 1
}

check_caelestia_shell() {
    # Evitar falso positivo em pgrep: padrão não pode aparecer na linha de comando deste script
    if pgrep -u "$USER" -f '(^|/)qs -c caelestia|(^|/)quickshell .*-c caelestia' &>/dev/null; then
        report OK "runtime: caelestia shell (qs -c caelestia) em execução"
        return 0
    fi

    if command -v qs &>/dev/null && qs -c caelestia ipc show &>/dev/null 2>&1; then
        report OK "runtime: caelestia shell responde via IPC"
        return 0
    fi

    report FAIL "runtime: caelestia shell/taskbar não está rodando"
    return 1
}

check_spicetify_theme() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/config-xpui.ini"
    if [[ ! -f "$cfg" ]]; then
        report WARN "spicetify: config-xpui.ini ausente"
        return 1
    fi
    if ! grep -qE '^current_theme[[:space:]=]+caelestia' "$cfg"; then
        report FAIL "spicetify: current_theme não é caelestia"
        return 1
    fi
    if ! grep -qE '^version[[:space:]=]+.+' "$cfg"; then
        report FAIL "spicetify: Backup vazio — rode spicetify backup apply"
        return 1
    fi
    report OK "spicetify: tema caelestia aplicado (backup ok)"
    return 0
}

check_waywallen_wallpaper() {
    local last wall path_state desktop icon shell_json layers
    last="${XDG_STATE_HOME:-$HOME/.local/state}/pandora/waywallen-last.txt"
    path_state="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/wallpaper/path.txt"
    desktop="$(waywallen_desktop_path)"
    icon="$(waywallen_icon_path)"
    shell_json="${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/shell.json"

    if [[ -x "${HOME}/.local/bin/waywallen" ]]; then
        report OK "waywallen: binário em ~/.local/bin/waywallen"
    else
        report FAIL "waywallen: binário ausente (~/.local/bin/waywallen)"
        return 1
    fi

    if [[ -f "$desktop" ]] && grep -qE '^Exec=.+' "$desktop"; then
        report OK "waywallen: launcher desktop=$desktop"
    else
        report FAIL "waywallen: .desktop ausente no launcher — rode install/50-waywallen.sh"
        return 1
    fi

    if [[ -L "${HOME}/.local/bin/waywallen-ui" || -x "${HOME}/.local/bin/waywallen-ui" ]] \
        && grep -qE 'waywallen-ui' "$desktop"; then
        report OK "waywallen: launcher usa wrapper --no-display (waywallen-ui)"
    else
        report FAIL "waywallen: .desktop não aponta para waywallen-ui — rode install_waywallen_launcher"
        return 1
    fi

    if [[ -f "$icon" ]]; then
        report OK "waywallen: ícone=$icon"
    else
        report WARN "waywallen: ícone ausente ($icon)"
    fi

    # Daemon NÃO deve estar ativo: no NVIDIA o layer fica preto e cobre o Caelestia
    if systemctl --user is-active waywallen.service &>/dev/null; then
        report FAIL "waywallen: serviço ativo (layer preto no NVIDIA) — systemctl --user disable --now waywallen.service"
        return 1
    fi
    if systemctl --user is-enabled waywallen.service &>/dev/null; then
        report FAIL "waywallen: serviço habilitado no boot — systemctl --user disable waywallen.service"
        return 1
    fi
    report OK "waywallen: daemon desabilitado (Caelestia renderiza wallpaper)"

    wall=""
    [[ -f "$path_state" ]] && wall="$(cat "$path_state")"
    [[ -z "$wall" && -f "$last" ]] && wall="$(cat "$last")"
    if [[ -n "$wall" && -f "$wall" ]]; then
        report OK "wallpaper: path=$wall"
    else
        report FAIL "wallpaper: nenhum path válido — rode caelestia wallpaper -f …"
        return 1
    fi

    if [[ -f "$shell_json" ]] && command -v jq &>/dev/null; then
        if ! jq -e '.background.wallpaperEnabled == true' "$shell_json" &>/dev/null; then
            report FAIL "wallpaper: shell.json wallpaperEnabled!=true (necessário no NVIDIA)"
            return 1
        fi
        if jq -e '.background.enabled == false' "$shell_json" &>/dev/null; then
            report FAIL "wallpaper: shell.json background.enabled=false"
            return 1
        fi
        report OK "wallpaper: Caelestia background/wallpaper habilitados"
    fi

    if command -v hyprctl &>/dev/null && hyprctl monitors &>/dev/null 2>&1; then
        layers="$(hyprctl layers 2>/dev/null || true)"
        if grep -q 'namespace: waywallen-wallpaper' <<<"$layers"; then
            report FAIL "wallpaper: layer waywallen-wallpaper presente (preto no NVIDIA) — pare o daemon"
            return 1
        fi
        if grep -q 'namespace: caelestia-background' <<<"$layers"; then
            report OK "wallpaper: layer caelestia-background ativo"
        else
            report FAIL "wallpaper: caelestia-background ausente — reinicie: caelestia shell -d"
            return 1
        fi
    fi

    return 0
}

check_runtime() {
    if ! python -c "import materialyoucolor, PIL" &>/dev/null 2>&1; then
        report FAIL "python: materialyoucolor/pillow ausentes (rode install/30-caelestia-build.sh)"
        return 1
    fi
    report OK "python: materialyoucolor + pillow"

    check_hypr_user_monitor || true
    check_caelestia_shell_config || true
    check_spicetify_theme || true
    check_waywallen_wallpaper || true

    if command -v hyprctl &>/dev/null && hyprctl monitors &>/dev/null 2>&1; then
        report OK "runtime: sessão Hyprland ativa"
        check_hypr_config_errors || true
        if pandora_shell_qsconf &>/dev/null; then
            check_caelestia_shell || true
        else
            report FAIL "runtime: shell/taskbar não pode iniciar sem /etc/xdg/quickshell/caelestia/shell.qml"
        fi
        if hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.class | startswith("pandora-"))' &>/dev/null; then
            report OK "runtime: janelas pandora-* detectadas"
        else
            report WARN "runtime: dashboard pandora-* não detectado com sessão Hyprland ativa"
        fi
    else
        report INFO "runtime: Hyprland inativo — configerrors/shell/dashboard só verificáveis após login"
    fi
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
if ! command -v caelestia &>/dev/null || ! command -v qs &>/dev/null; then
    INSTALL_INCOMPLETE=1
    report INFO "instalação incompleta: caelestia/qs ausente — passos 40-90 não rodaram"
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
