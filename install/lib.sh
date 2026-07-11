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
            log "Overlay: $f -> $dest/$f"
        fi
    done
    if [[ -f "$src/fastfetch/config.jsonc" ]]; then
        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch"
        cp "$src/fastfetch/config.jsonc" "${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/config.jsonc"
        log "Overlay: fastfetch/config.jsonc"
    fi
    deploy_systemd_units
    patch_cli_json
}

patch_cli_json() {
    local cli_json="$PANDORA_CONFIG/cli.json"
    [[ -f "$cli_json" ]] || return 0
    python3 - <<PY
import json, os
path = os.path.expandvars("$cli_json")
with open(path) as f:
    data = json.load(f)
data.setdefault("dots", {})["url"] = os.environ.get("PANDORA_DOTS_URL", "https://github.com/PandoraDots/caelestia.git")
data.setdefault("dots", {})["branch"] = "main"
data.setdefault("wallpaper", {})["postHook"] = f'bash "{os.environ["PANDORA_ROOT"]}/scripts/waywallen-bridge.sh"'
with open(path, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
PY
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
    log "Instalando paru..."
    local tmp
    tmp="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp/paru"
    (cd "$tmp/paru" && makepkg -si --noconfirm)
    rm -rf "$tmp"
}

pacman_install() {
    sudo pacman -S --needed --noconfirm "$@"
}

aur_install() {
    ensure_paru
    paru -S --needed --noconfirm "$@"
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
