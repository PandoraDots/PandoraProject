#!/usr/bin/env bash
# Shared helpers for PandoraProject install scripts.

set -euo pipefail

: "${PANDORA_ROOT:?PANDORA_ROOT must be set}"

PANDORA_MODEL="${PANDORA_MODEL:-phn16-72}"
PANDORA_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/pandora"
PANDORA_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/caelestia"
PANDORA_BUILD="${PANDORA_STATE}/build"
PANDORA_DOTS_URL="${PANDORA_DOTS_URL:-https://github.com/PandoraDots/caelestia.git}"
PANDORA_CLI_URL="${PANDORA_CLI_URL:-https://github.com/PandoraDots/cli.git}"
PANDORA_SHELL_URL="${PANDORA_SHELL_URL:-https://github.com/PandoraDots/shell.git}"
PANDORA_NEKRO_URL="${PANDORA_NEKRO_URL:-https://github.com/PandoraDots/nekro-sense.git}"
PANDORA_AUR_HELPER="${PANDORA_AUR_HELPER:-paru}"

# shellcheck source=install/cachyos.sh
source "$PANDORA_ROOT/install/cachyos.sh"

log()  { printf '\033[1;34m[Pandora]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[Pandora]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[Pandora]\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "Comando obrigatório ausente: $cmd"
    done
}

run_step() {
    local name="$1"
    shift
    log "==> $name"
    "$@"
}

model_config() {
    local model="$1"
    local file="$PANDORA_ROOT/models/${model}.json"
    [[ -f "$file" ]] || die "Modelo desconhecido: $model (esperado $file)"
    printf '%s' "$file"
}

deploy_overlays() {
    local src="$PANDORA_ROOT/overlays"
    local dest="$PANDORA_CONFIG"
    mkdir -p "$dest"
    for f in cli.json shell.json hypr-vars.lua hypr-user.lua; do
        if [[ -f "$src/$f" ]]; then
            cp "$src/$f" "$dest/$f"
            if [[ "$f" == "hypr-user.lua" ]]; then
                sed -i "s|__PANDORA_ROOT__|$PANDORA_ROOT|g" "$dest/$f"
            fi
            if [[ "$f" == "cli.json" ]]; then
                patch_cli_json
                log "Overlay: $f -> $dest/$f"
                continue
            fi
            log "Overlay: $f -> $dest/$f"
        fi
    done
    if [[ -f "$src/fastfetch/config.jsonc" ]]; then
        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch"
        sed "s|__PANDORA_ROOT__|$PANDORA_ROOT|g" "$src/fastfetch/config.jsonc" \
            >"${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/config.jsonc"
        log "Overlay: fastfetch/config.jsonc"
    fi
    if [[ -f "$src/cava/config" ]]; then
        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/cava"
        cp "$src/cava/config" "${XDG_CONFIG_HOME:-$HOME/.config}/cava/config"
        log "Overlay: cava/config"
    fi
    if [[ -f "$src/fish/functions/fish_greeting.fish" ]]; then
        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/fish/functions"
        cp "$src/fish/functions/fish_greeting.fish" \
            "${XDG_CONFIG_HOME:-$HOME/.config}/fish/functions/fish_greeting.fish"
        log "Overlay: fish/functions/fish_greeting.fish"
    fi
    deploy_systemd_units
    deploy_user_icon
}

deploy_user_icon() {
    local src="$PANDORA_ROOT/assets/icon.png"
    local dest="$HOME/.face"

    [[ -f "$src" ]] || {
        warn "Ícone de usuário não encontrado: $src"
        return 0
    }

    if [[ -f "$dest" && ! -L "$dest" ]]; then
        warn "Ícone de usuário personalizado preservado: $dest"
        return 0
    fi

    ln -sfn "$src" "$dest"
    log "Ícone de usuário Caelestia: $dest -> $src"
}

patch_cli_json() {
    local cli_json="$PANDORA_CONFIG/cli.json"
    [[ -f "$cli_json" ]] || return 0
    python3 - <<PY
import json, os
path = os.path.expandvars("$cli_json")
root = os.environ["PANDORA_ROOT"]
with open(path) as f:
    data = json.load(f)
data.setdefault("dots", {})["url"] = os.environ.get("PANDORA_DOTS_URL", "https://github.com/PandoraDots/caelestia.git")
data.setdefault("dots", {})["branch"] = "main"
data.setdefault("wallpaper", {})["postHook"] = f'bash "{root}/scripts/wallpaper-posthook.sh"'
data.setdefault("theme", {})["postHook"] = "sudo /usr/share/sddm/themes/caelestia/scripts/sync.sh --posthook"
with open(path, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
PY
}

configure_keyboard_layout() {
    sudo localectl set-keymap br-abnt2 2>/dev/null || warn "localectl set-keymap falhou"
    sudo localectl set-x11-keymap br abnt2 2>/dev/null || warn "localectl set-x11-keymap falhou"
    log "Teclado: br-abnt2 (sistema + Hyprland via overlay)"
}

deploy_sddm_sudoers() {
    local sync_script="/usr/share/sddm/themes/caelestia/scripts/sync.sh"
    [[ -x "$sync_script" ]] || return 0

    local dropin="/etc/sudoers.d/caelestia-sddm-sync"
    local line="$USER ALL=(root) NOPASSWD: $sync_script"
    if [[ -f "$dropin" ]] && grep -qF "$sync_script" "$dropin" 2>/dev/null; then
        return 0
    fi
    echo "$line" | sudo tee "$dropin" >/dev/null
    sudo chmod 440 "$dropin"
    log "Sudoers: sync SDDM sem senha ($sync_script)"
}

sync_sddm_theme() {
    deploy_sddm_sudoers
    local sync_script="/usr/share/sddm/themes/caelestia/scripts/sync.sh"
    if [[ -x "$sync_script" ]]; then
        sudo "$sync_script" 2>/dev/null || warn "Sync do tema SDDM falhou"
        log "Tema SDDM sincronizado (wallpaper, avatar, cores inferno)"
    fi
}

deploy_systemd_units() {
    local unit_dir="$HOME/.config/systemd/user"
    local src="$PANDORA_ROOT/overlays/systemd"
    mkdir -p "$unit_dir"
    if [[ -f "$src/pandora-gpu-profile.service" ]]; then
        sed "s|%h/PandoraProject|$PANDORA_ROOT|g" "$src/pandora-gpu-profile.service" \
            >"$unit_dir/pandora-gpu-profile.service"
    fi
    if [[ -f "$src/pandora-gpu-profile.path" ]]; then
        cp "$src/pandora-gpu-profile.path" "$unit_dir/pandora-gpu-profile.path"
    fi
    if [[ -f "$src/pandora-gpu-profile.timer" ]]; then
        cp "$src/pandora-gpu-profile.timer" "$unit_dir/pandora-gpu-profile.timer"
    fi
    systemctl --user daemon-reload 2>/dev/null || true
}

link_wallpapers() {
    local pictures="${XDG_PICTURES_DIR:-$HOME/Pictures}"
    local target="$pictures/Wallpapers"
    mkdir -p "$pictures"
    if [[ -L "$target" ]]; then
        rm "$target"
    elif [[ -d "$target" ]]; then
        warn "$target já existe como diretório; mantendo conteúdo existente"
        return 0
    fi
    ln -sfn "$PANDORA_ROOT/Wallpapers" "$target"
    log "Wallpapers: $target -> $PANDORA_ROOT/Wallpapers"
}

ensure_paru() {
    if command -v paru >/dev/null 2>&1; then
        return 0
    fi
    if is_cachyos; then
        log "Instalando paru (repositório CachyOS)..."
        sudo pacman -S --needed --noconfirm paru
        return 0
    fi
    log "Instalando paru (AUR)..."
    local tmp
    tmp="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp/paru"
    (cd "$tmp/paru" && makepkg -si --noconfirm)
    rm -rf "$tmp"
}

# Nomes legados / incorretos -> pacotes reais no Arch/CachyOS.
pandora_pkg_alias() {
    case "$1" in
        material-symbols)              printf '%s' ttf-material-symbols-variable ;;
        caskaydia-cove-nerd-fonts)       printf '%s' ttf-cascadia-code-nerd ;;
        ttf-caskaydia-cove-nerd-fonts)   printf '%s' ttf-cascadia-code-nerd ;;
        lm-sensors)                      printf '%s' lm_sensors ;;
        python-hatch-vsc)                printf '%s' "" ;;
        *)                               printf '%s' "$1" ;;
    esac
}

pkg_in_repos() {
    pacman -Si "$1" &>/dev/null
}

pkg_in_aur() {
    ensure_paru
    paru -Si --aur "$1" &>/dev/null
}

pkg_available() {
    pkg_in_repos "$1" || pkg_in_aur "$1"
}

# Evita prompts de "provider" (ex.: qtengine-git, libcava-git) em instalação não interativa.
aur_install_one() {
    local pkg="$1"
    ensure_paru
    if paru -S --aur --needed --noconfirm "$pkg"; then
        return 0
    fi
    warn "Falha ao instalar $pkg (AUR)"
    return 1
}

pacman_install() {
    [[ $# -eq 0 ]] && return 0

    ensure_paru
    if is_cachyos; then
        ensure_cachyos_repos || true
    fi

    local -a repo_pkgs=() aur_pkgs=()
    local pkg alias

    for pkg in "$@"; do
        alias="$(pandora_pkg_alias "$pkg")"
        if [[ -z "$alias" ]]; then
            warn "Pacote ignorado (sem equivalente Arch): $pkg"
            continue
        fi
        if [[ "$alias" != "$pkg" ]]; then
            log "Alias de pacote: $pkg -> $alias"
            pkg="$alias"
        fi

        if pkg_in_repos "$pkg"; then
            repo_pkgs+=("$pkg")
        elif pkg_in_aur "$pkg"; then
            aur_pkgs+=("$pkg")
        else
            warn "Pacote não encontrado (repos/AUR): $pkg"
        fi
    done

    if is_cachyos && [[ ${#repo_pkgs[@]} -gt 0 ]]; then
        mapfile -t repo_pkgs < <(cachyos_resolve_packages "${repo_pkgs[@]}")
    fi

    if [[ ${#repo_pkgs[@]} -gt 0 ]]; then
        log "Pacotes (repos): ${repo_pkgs[*]}"
        sudo pacman -S --needed --noconfirm "${repo_pkgs[@]}"
    fi

    if [[ ${#aur_pkgs[@]} -gt 0 ]]; then
        log "Pacotes (AUR): ${aur_pkgs[*]}"
        local aur_pkg
        for aur_pkg in "${aur_pkgs[@]}"; do
            aur_install_one "$aur_pkg" || true
        done
    fi
}

# pipewire-jack conflita com jack2 (comum em ISOs CachyOS/Arch).
install_audio_stack() {
    local -a pkgs=(
        pipewire pipewire-pulse pipewire-audio pipewire-alsa
        wireplumber pavucontrol
    )

    pacman_install "${pkgs[@]}"

    if pacman -Qi pipewire-jack &>/dev/null; then
        log "pipewire-jack já instalado"
        return 0
    fi

    if pacman -Q jack2 &>/dev/null; then
        log "jack2 detectado — removendo para instalar pipewire-jack (PipeWire)"
        if sudo pacman -R --noconfirm jack2 2>/dev/null; then
            pacman_install pipewire-jack
        else
            warn "jack2 não removível (dependências) — pulando pipewire-jack"
            warn "Áudio Pulse/PipeWire segue funcional; apps JACK usam jack2"
        fi
        return 0
    fi

    pacman_install pipewire-jack
}

aur_install() {
    local pkg
    for pkg in "$@"; do
        aur_install_one "$pkg" || true
    done
}

clone_or_pull() {
    local url="$1"
    local dest="$2"
    local branch="${3:-main}"
    if [[ -d "$dest/.git" ]]; then
        git -C "$dest" fetch origin "$branch"
        git -C "$dest" checkout "$branch"
        git -C "$dest" pull --ff-only origin "$branch" || warn "Pull falhou em $dest; usando checkout local"
    else
        mkdir -p "$(dirname "$dest")"
        git clone --depth 1 --branch "$branch" "$url" "$dest"
    fi
}

# Exporta helpers para subshells (bash -c). Sem isso, pacman_install/aur_install etc.
# falham com "comando não encontrado" em instalação limpa.
pandora_export_helpers() {
    export PANDORA_ROOT PANDORA_MODEL PANDORA_AUR_HELPER
    export PANDORA_STATE PANDORA_CONFIG PANDORA_BUILD
    export PANDORA_DOTS_URL PANDORA_CLI_URL PANDORA_SHELL_URL PANDORA_NEKRO_URL

    local fn
    local -a fns=(
        log warn die require_cmd run_step model_config
        deploy_overlays deploy_user_icon patch_cli_json configure_keyboard_layout
        deploy_sddm_sudoers sync_sddm_theme deploy_systemd_units link_wallpapers
        ensure_paru pacman_install aur_install aur_install_one clone_or_pull install_audio_stack
        pandora_pkg_alias pkg_in_repos pkg_in_aur pkg_available
        is_cachyos ensure_cachyos_repos cachyos_pkg_available cachyos_preferred_pkg
        cachyos_should_skip_pkg cachyos_list_kernel_packages
        cachyos_nvidia_module_packages cachyos_kernel_header_packages
        cachyos_resolve_packages install_cachyos_gpu_drivers
    )
    for fn in "${fns[@]}"; do
        export -f "$fn"
    done
}

pandora_helpers_reachable() {
    [[ "$(bash -c 'type -t pacman_install')" == "function" ]]
}

# Alternativa explícita a bash -c quando o snippet usa helpers do lib.sh.
pandora_bash() {
    local script="$1"
    # shellcheck disable=SC2090
    bash -c "
        set -euo pipefail
        source \"\${PANDORA_ROOT}/install/lib.sh\"
        $script
    "
}

if [[ "${BASH_SOURCE[0]:-}" != "${0}" ]]; then
    pandora_export_helpers
fi
