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

skip_if_ready() {
    local name="$1"
    shift
    if "$@"; then
        log "==> $name (já pronto — pulando)"
        return 0
    fi
    return 1
}

pandora_cli_ready() {
    command -v caelestia &>/dev/null \
        && python -c "import materialyoucolor, PIL" &>/dev/null 2>&1
}

ensure_caelestia_cli_deps() {
    pacman_install python-pillow
    if python -c "import materialyoucolor" &>/dev/null 2>&1; then
        return 0
    fi
    log "Instalando materialyoucolor (dependência do caelestia CLI)..."
    sudo python -m pip install --break-system-packages materialyoucolor
}

pandora_shell_qsconf() {
    local conf
    for conf in \
        /etc/xdg/quickshell/caelestia/shell.qml \
        "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia/shell.qml"
    do
        [[ -f "$conf" ]] && { printf '%s' "$conf"; return 0; }
    done
    return 1
}

pandora_shell_ready() {
    # qs (quickshell-git ou quickshell do repo) sozinho não basta — precisa do shell.qml
    command -v qs &>/dev/null && pandora_shell_qsconf &>/dev/null
}

# Garante Quickshell do Caelestia — nunca noctalia-qs (CachyOS Provides: quickshell-git).
ensure_pandora_quickshell() {
    ensure_paru

    if pacman -Q noctalia-qs &>/dev/null; then
        warn "noctalia-qs detectado — incompatível com Caelestia; removendo..."
        sudo pacman -R --noconfirm noctalia-qs || die "Remova noctalia-qs manualmente e reinstale quickshell"
    fi

    if pacman -Q quickshell-git &>/dev/null || pacman -Q quickshell &>/dev/null; then
        log "Quickshell OK: $(pacman -Q quickshell-git 2>/dev/null || pacman -Q quickshell)"
        command -v qs &>/dev/null || die "qs ausente após quickshell instalado"
        return 0
    fi

    # Preferir pacote oficial do repo (não o Provides do noctalia-qs).
    if pkg_in_repos quickshell; then
        log "Instalando quickshell (repos) — evitando noctalia-qs"
        sudo pacman -S --needed --noconfirm quickshell || die "Falha ao instalar quickshell"
    elif pkg_in_aur quickshell-git; then
        log "Instalando quickshell-git (AUR)"
        aur_install_one quickshell-git || die "Falha ao instalar quickshell-git"
    else
        die "Nem quickshell (repos) nem quickshell-git (AUR) disponíveis"
    fi

    command -v qs &>/dev/null || die "qs não encontrado após instalar Quickshell"
}

# Stamp de ABI/runtime: Hyprland/Aquamarine/libcava/qs + revs dos forks.
# Se mudar (ex.: 0.55→0.56), o shell precisa ser recompilado mesmo com shell.qml presente.
pandora_runtime_stamp_path() {
    printf '%s' "${PANDORA_STATE}/runtime.stamp"
}

pandora_pkg_qv() {
    local pkg="$1"
    pacman -Q "$pkg" 2>/dev/null || printf '%s missing\n' "$pkg"
}

pandora_repo_rev() {
    local name="$1"
    local dir=""
    if [[ -d "$PANDORA_ROOT/../$name/.git" ]]; then
        dir="$PANDORA_ROOT/../$name"
    elif [[ -d "$PANDORA_BUILD/$name/.git" ]]; then
        dir="$PANDORA_BUILD/$name"
    else
        printf '%s unavailable\n' "$name"
        return 0
    fi
    printf '%s %s\n' "$name" "$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo unknown)"
}

pandora_runtime_stamp() {
    pandora_pkg_qv hyprland
    pandora_pkg_qv aquamarine
    pandora_pkg_qv hyprutils
    pandora_pkg_qv xdg-desktop-portal-hyprland
    pandora_pkg_qv libcava
    pandora_pkg_qv cava
    pandora_pkg_qv quickshell-git
    pandora_pkg_qv quickshell
    pandora_pkg_qv foot
    pandora_repo_rev cli
    pandora_repo_rev shell
    pandora_repo_rev caelestia
}

pandora_runtime_changed() {
    local stamp path
    path="$(pandora_runtime_stamp_path)"
    stamp="$(pandora_runtime_stamp)"
    [[ ! -f "$path" ]] && return 0
    [[ "$(<"$path")" != "$stamp" ]]
}

save_pandora_runtime_stamp() {
    mkdir -p "$PANDORA_STATE"
    pandora_runtime_stamp >"$(pandora_runtime_stamp_path)"
    log "Runtime stamp salvo: $(pandora_runtime_stamp_path)"
}

# Hyprland mínimo para hl.dsp (dashboard, binds Pandora).
# 0.56.2+ corrige cursor em captura de janela; Pandora testa ≥0.56.0.
pandora_hyprland_min_version() {
    printf '%s' "0.56.0"
}

pandora_hyprland_version_ok() {
    local ver min
    ver="$(pacman -Q hyprland 2>/dev/null | awk '{print $2}' | sed 's/-.*//;s/\.arch.*//;s/\.cachyos.*//')"
    min="$(pandora_hyprland_min_version)"
    [[ -n "$ver" ]] || return 1
    printf '%s\n%s\n' "$min" "$ver" | sort -V | head -1 | grep -qx "$min"
}

caelestia_dots_ready() {
    local hypr="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
    [[ -f "$hypr/hyprland.lua" || -f "$hypr/hyprland.conf" ]]
}

pandora_overlays_ready() {
    [[ -f "$PANDORA_CONFIG/hypr-user.lua" ]] \
        && grep -qF "$PANDORA_ROOT" "$PANDORA_CONFIG/hypr-user.lua" 2>/dev/null \
        && [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/config.jsonc" ]]
}

scheme_inferno_ready() {
    local scheme_file="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/scheme.json"
    [[ -f "$scheme_file" ]] && jq -e '.name == "inferno"' "$scheme_file" &>/dev/null
}

# Localiza AppImage/binário do Hydra (Shelly, Pandora ou PATH).
find_hydra_binary() {
    local bin dir f
    dir="${HOME}/.local/bin"
    for f in \
        "$dir/hydralauncher" \
        "$dir"/hydralauncher*.AppImage \
        "$dir"/Hydra*.AppImage; do
        [[ -x "$f" ]] || continue
        # Preferir AppImage do Shelly (nome versionado) sobre cópia sem extensão
        if [[ "$f" == *.AppImage ]]; then
            printf '%s' "$f"
            return 0
        fi
        bin="$f"
    done
    [[ -n "${bin:-}" ]] && { printf '%s' "$bin"; return 0; }
    if command -v hydralauncher &>/dev/null; then
        command -v hydralauncher
        return 0
    fi
    return 1
}

# .desktop já criado pelo Shelly / AppImageKit / Pandora.
find_hydra_desktop() {
    local apps d
    apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    for d in \
        "$apps"/hydralauncher*.desktop \
        "$apps"/io.hydralauncher.Hydra.desktop \
        "$apps"/*[Hh]ydra*.desktop; do
        [[ -f "$d" ]] || continue
        printf '%s' "$d"
        return 0
    done
    return 1
}

hydra_desktop_path() {
    # Preferir entrada existente (Shelly); senão o template Pandora.
    local found
    if found="$(find_hydra_desktop 2>/dev/null)"; then
        printf '%s' "$found"
        return 0
    fi
    printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/applications/io.hydralauncher.Hydra.desktop"
}

hydra_icon_path() {
    printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps/io.hydralauncher.Hydra.png"
}

hydra_ready() {
    find_hydra_binary &>/dev/null || return 1
    find_hydra_desktop &>/dev/null || return 1
}

wallpaper_ready() {
    local path_state wall shell_json
    path_state="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/wallpaper/path.txt"
    shell_json="${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/shell.json"
    [[ -f "$path_state" ]] || return 1
    wall="$(cat "$path_state" 2>/dev/null || true)"
    [[ -n "$wall" && -f "$wall" ]] || return 1
    if [[ -f "$shell_json" ]] && command -v jq &>/dev/null; then
        jq -e '.background.wallpaperEnabled == true' "$shell_json" &>/dev/null || return 1
        jq -e '.background.enabled != false' "$shell_json" &>/dev/null || return 1
    fi
    return 0
}

hydra_extract_icon() {
    local bin icon_dst tmp found
    bin="$(find_hydra_binary 2>/dev/null)" || return 1
    icon_dst="$(hydra_icon_path)"
    mkdir -p "$(dirname "$icon_dst")"
    [[ -x "$bin" ]] || return 1

    # Ícone já gerado pelo Shelly
    found="$(find "${HOME}/.local/share/shelly-icons" -type f \( -iname '*hydra*' -o -iname 'hydralauncher*' \) 2>/dev/null | head -1 || true)"
    if [[ -n "$found" && -f "$found" ]]; then
        cp -f "$found" "$icon_dst"
        log "Hydra ícone (Shelly): $icon_dst"
        return 0
    fi

    tmp="$(mktemp -d)"
    if (cd "$tmp" && "$bin" --appimage-extract 'hydralauncher.png' >/dev/null 2>&1) \
        || (cd "$tmp" && "$bin" --appimage-extract '*.png' >/dev/null 2>&1); then
        found="$(find "$tmp/squashfs-root" -type f \( -iname 'hydralauncher.png' -o -iname '*hydra*.png' \) 2>/dev/null | head -1)"
        [[ -z "$found" ]] && found="$(find "$tmp/squashfs-root" -type f -name '*.png' 2>/dev/null | head -1)"
        if [[ -n "$found" && -f "$found" ]]; then
            cp -f "$found" "$icon_dst"
            rm -rf "$tmp"
            log "Hydra ícone: $icon_dst"
            return 0
        fi
    fi
    rm -rf "$tmp"
    return 1
}

# Garante .desktop no XDG (Caelestia lê applications/). Se Shelly já criou, só confirma.
install_hydra_launcher() {
    local bin desktop_src desktop_dst apps_dir existing

    if existing="$(find_hydra_desktop 2>/dev/null)"; then
        log "Hydra já no launcher (Shelly/XDG): $existing"
        return 0
    fi

    bin="$(find_hydra_binary 2>/dev/null)" || {
        warn "Hydra binário ausente — instale via Shelly ou rode com rede para baixar"
        return 1
    }

    apps_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    desktop_dst="${apps_dir}/io.hydralauncher.Hydra.desktop"
    desktop_src="$PANDORA_ROOT/assets/hydra/io.hydralauncher.Hydra.desktop"
    mkdir -p "$apps_dir"

    hydra_extract_icon || warn "Ícone Hydra não extraído (OK — .desktop ainda funciona)"

    if [[ -f "$desktop_src" ]]; then
        sed -e "s|^Exec=.*|Exec=${bin}|" \
            -e "s|^Icon=.*|Icon=io.hydralauncher.Hydra|" \
            "$desktop_src" >"$desktop_dst"
    else
        cat >"$desktop_dst" <<EOF
[Desktop Entry]
Type=Application
Name=Hydra Launcher
Comment=Gerenciador de biblioteca de jogos
Exec=${bin}
Icon=io.hydralauncher.Hydra
Terminal=false
Categories=Game;
StartupNotify=true
EOF
    fi
    chmod 644 "$desktop_dst"

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$apps_dir" 2>/dev/null || true
    fi
    log "Hydra launcher: $desktop_dst"
}

# --- Orion Launcher (OrionBE / Minecraft Bedrock) ---

orion_state_tag_file() {
    printf '%s' "${PANDORA_STATE}/orion-release.tag"
}

orion_bin_link() {
    printf '%s' "${HOME}/.local/bin/orion-launcher"
}

orion_desktop_path() {
    printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/applications/org.orionbedrock.OrionLauncher.desktop"
}

orion_icon_path() {
    printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps/org.orionbedrock.OrionLauncher.png"
}

find_orion_binary() {
    local dir f link
    link="$(orion_bin_link)"
    dir="${HOME}/.local/bin"
    [[ -x "$link" ]] && { printf '%s' "$(readlink -f "$link" 2>/dev/null || printf '%s' "$link")"; return 0; }
    for f in "$dir"/OrionBE-Launcher*.AppImage "$dir"/OrionBE*.AppImage "$dir"/orion-launcher*.AppImage; do
        [[ -x "$f" ]] || continue
        printf '%s' "$f"
        return 0
    done
    if command -v orion-launcher &>/dev/null; then
        command -v orion-launcher
        return 0
    fi
    return 1
}

orion_ready() {
    find_orion_binary &>/dev/null || return 1
    [[ -f "$(orion_desktop_path)" ]] || return 1
}

orion_host_arch_token() {
    case "$(uname -m)" in
        x86_64|amd64) printf 'linux-x64' ;;
        aarch64|arm64) printf 'linux-arm64' ;;
        *) printf 'linux-x64' ;;
    esac
}

# Imprime: TAG<TAB>URL  da release mais recente (AppImage preferindo arch do host).
orion_latest_release_info() {
    local repo arch json tag url
    repo="${ORION_REPO:-OrionBedrock/OrionLauncher}"
    arch="$(orion_host_arch_token)"
    require_cmd curl jq
    json="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest")"
    tag="$(jq -r '.tag_name // empty' <<<"$json")"
    url="$(jq -r --arg arch "$arch" '
        [.assets[] | select(.name | test("\\.AppImage$"))
         | select(.name | test($arch; "i"))]
        | (.[0].browser_download_url // empty)
    ' <<<"$json")"
    if [[ -z "$url" ]]; then
        url="$(jq -r '[.assets[] | select(.name | test("\\.AppImage$"))] | (.[0].browser_download_url // empty)' <<<"$json")"
    fi
    [[ -n "$tag" && -n "$url" && "$url" != "null" ]] || return 1
    printf '%s\t%s' "$tag" "$url"
}

ensure_fuse_for_appimage() {
    if command -v fusermount &>/dev/null || command -v fusermount3 &>/dev/null; then
        return 0
    fi
    warn "fusermount ausente — instalando fuse2 (AppImage)"
    pacman_install fuse2 || true
}

install_orion_binary() {
    local info tag url dest link current_tag stamp name
    ensure_fuse_for_appimage
    require_cmd curl jq

    info="$(orion_latest_release_info)" || die "Não foi possível obter release latest do Orion (${ORION_REPO:-OrionBedrock/OrionLauncher})"
    tag="${info%%$'\t'*}"
    url="${info#*$'\t'}"
    stamp="$(orion_state_tag_file)"
    link="$(orion_bin_link)"
    mkdir -p "$(dirname "$link")" "$(dirname "$stamp")"

    current_tag=""
    [[ -f "$stamp" ]] && current_tag="$(<"$stamp")"

    if [[ "${ORION_FORCE_UPDATE:-0}" != "1" && -x "$link" && "$current_tag" == "$tag" ]]; then
        log "Orion já na release mais recente: $tag ($link)"
        return 0
    fi

    name="$(basename "$url")"
    dest="${HOME}/.local/bin/${name}"
    log "Baixando Orion $tag: $url"
    curl -fL --progress-bar "$url" -o "$dest"
    chmod +x "$dest"
    ln -sfn "$dest" "$link"
    printf '%s\n' "$tag" >"$stamp"

    # Remove AppImages Orion antigos (exceto o atual)
    local old
    for old in "${HOME}/.local/bin"/OrionBE-Launcher*.AppImage "${HOME}/.local/bin"/OrionBE*.AppImage; do
        [[ -f "$old" ]] || continue
        [[ "$(readlink -f "$old" 2>/dev/null || true)" == "$(readlink -f "$dest")" ]] && continue
        [[ "$old" == "$dest" ]] && continue
        rm -f "$old" && log "Removido AppImage Orion antigo: $old"
    done

    log "Orion instalado: $link -> $dest ($tag)"
}

orion_extract_icon() {
    local bin icon_dst tmp found
    bin="$(find_orion_binary 2>/dev/null)" || return 1
    icon_dst="$(orion_icon_path)"
    mkdir -p "$(dirname "$icon_dst")"
    [[ -x "$bin" ]] || return 1

    tmp="$(mktemp -d)"
    if (cd "$tmp" && "$bin" --appimage-extract '*.png' >/dev/null 2>&1) \
        || (cd "$tmp" && "$bin" --appimage-extract >/dev/null 2>&1); then
        found="$(find "$tmp/squashfs-root" -type f \( -iname '*orion*.png' -o -iname '*OrionBE*.png' \) 2>/dev/null | head -1)"
        [[ -z "$found" ]] && found="$(find "$tmp/squashfs-root" -type f -name '*.png' 2>/dev/null | head -1)"
        if [[ -n "$found" && -f "$found" ]]; then
            cp -f "$found" "$icon_dst"
            rm -rf "$tmp"
            log "Orion ícone: $icon_dst"
            return 0
        fi
    fi
    rm -rf "$tmp"
    return 1
}

install_orion_launcher() {
    local bin desktop_src desktop_dst apps_dir exec_path

    bin="$(find_orion_binary 2>/dev/null)" || {
        warn "Orion binário ausente"
        return 1
    }
    exec_path="$(orion_bin_link)"
    [[ -x "$exec_path" ]] || exec_path="$bin"

    apps_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    desktop_dst="$(orion_desktop_path)"
    desktop_src="$PANDORA_ROOT/assets/orion/org.orionbedrock.OrionLauncher.desktop"
    mkdir -p "$apps_dir"

    orion_extract_icon || warn "Ícone Orion não extraído (OK — .desktop ainda funciona)"

    if [[ -f "$desktop_src" ]]; then
        sed -e "s|^Exec=.*|Exec=${exec_path}|" \
            -e "s|^Icon=.*|Icon=org.orionbedrock.OrionLauncher|" \
            "$desktop_src" >"$desktop_dst"
    else
        cat >"$desktop_dst" <<EOF
[Desktop Entry]
Type=Application
Name=Orion Launcher
Comment=Minecraft Bedrock Launcher (OrionBE)
Exec=${exec_path}
Icon=org.orionbedrock.OrionLauncher
Terminal=false
Categories=Game;
StartupNotify=true
EOF
    fi
    chmod 644 "$desktop_dst"

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$apps_dir" 2>/dev/null || true
    fi
    log "Orion launcher: $desktop_dst"
}

user_unit_enabled() {
    local unit="$1"
    systemctl --user is-enabled "$unit" &>/dev/null
}

model_config() {
    local model="$1"
    local file="$PANDORA_ROOT/models/${model}.json"
    [[ -f "$file" ]] || die "Modelo desconhecido: $model (esperado $file)"
    printf '%s' "$file"
}

validate_hypr_user_monitor() {
    local path="${1:-$PANDORA_CONFIG/hypr-user.lua}"
    local pos
    [[ -f "$path" ]] || return 0
    pos="$(grep -E '^\s*position\s*=' "$path" | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/' || true)"
    [[ -z "$pos" ]] && return 0
    if [[ "$pos" =~ ^auto(-center)?(-(up|down|left|right))?$ || "$pos" =~ ^-?[0-9]+x-?[0-9]+$ ]]; then
        return 0
    fi
    die "hypr-user.lua: position='$pos' inválido (Hyprland exige '0x0' ou 'auto', não '0,0') — $path"
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
                validate_hypr_user_monitor "$dest/$f"
            fi
            if [[ "$f" == "cli.json" ]]; then
                patch_cli_json
                log "Overlay: $f -> $dest/$f"
                continue
            fi
            log "Overlay: $f -> $dest/$f"
        fi
    done
    # XDPH: cursor embutido no screen share (Equibop/Discord)
    if [[ -f "$src/hypr/xdph.conf" ]]; then
        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
        cp "$src/hypr/xdph.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/xdph.conf"
        log "Overlay: hypr/xdph.conf (cursor_mode=embedded)"
    fi
    if [[ -f "$src/cava/config" ]]; then
        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/cava"
        cp "$src/cava/config" "${XDG_CONFIG_HOME:-$HOME/.config}/cava/config"
        log "Overlay: cava/config (fallback vermelho, bars=32)"
    fi
    if [[ -f "$src/templates/cava.conf" ]]; then
        mkdir -p "$PANDORA_CONFIG/templates"
        cp "$src/templates/cava.conf" "$PANDORA_CONFIG/templates/cava.conf"
        log "Overlay: templates/cava.conf (schema Caelestia → cava)"
    fi
    sync_cava_from_scheme || true
    if [[ -f "$src/fastfetch/config.jsonc" ]]; then
        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch"
        sed "s|__PANDORA_ROOT__|$PANDORA_ROOT|g" "$src/fastfetch/config.jsonc" \
            >"${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/config.jsonc"
        log "Overlay: fastfetch/config.jsonc"
    fi
    if [[ -f "$src/fish/functions/fish_greeting.fish" ]]; then
        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/fish/functions"
        cp "$src/fish/functions/fish_greeting.fish" \
            "${XDG_CONFIG_HOME:-$HOME/.config}/fish/functions/fish_greeting.fish"
        log "Overlay: fish/functions/fish_greeting.fish"
    fi
    deploy_thunar_overlays
    deploy_systemd_units
    deploy_user_icon
    deploy_wallpaper_qml
    deploy_zapzap_theme
    deploy_spicetify_inferno
}

# Spicetify Inferno: preto / vermelho / branco (mata verde Spotify residual).
deploy_spicetify_inferno() {
    local src="$PANDORA_ROOT/overlays/spicetify/Themes/caelestia"
    local dest="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/Themes/caelestia"
    local css_src="$src/user.css"
    local color_src="$src/color.ini"

    [[ -f "$css_src" ]] || {
        warn "deploy_spicetify: user.css ausente ($css_src)"
        return 1
    }

    mkdir -p "$dest"
    cp -f "$css_src" "$dest/user.css"
    [[ -f "$color_src" ]] && cp -f "$color_src" "$dest/color.ini"

    # Mantém fonte caelestia alinhada (install dots não reverte ao verde)
    if [[ -d "$HOME/caelestia/spicetify/Themes/caelestia" ]]; then
        cp -f "$css_src" "$HOME/caelestia/spicetify/Themes/caelestia/user.css"
        [[ -f "$color_src" ]] && cp -f "$color_src" "$HOME/caelestia/spicetify/Themes/caelestia/color.ini"
    fi

    if ! command -v spicetify &>/dev/null; then
        warn "deploy_spicetify: spicetify-cli ausente — só arquivos copiados"
        return 0
    fi
    if [[ ! -d /opt/spotify ]]; then
        warn "deploy_spicetify: /opt/spotify ausente — só arquivos copiados"
        return 0
    fi

    # Spicetify precisa escrever em /opt/spotify
    if [[ ! -w /opt/spotify/Apps ]]; then
        sudo chmod a+wr /opt/spotify 2>/dev/null || true
        sudo chmod a+wr -R /opt/spotify/Apps 2>/dev/null || true
    fi

    spicetify config current_theme caelestia color_scheme caelestia 2>/dev/null || true
    # Após update do Spotify, "apply" falha com mismatch — usa backup apply
    if spicetify backup apply 2>/dev/null || spicetify apply 2>/dev/null; then
        log "Overlay: Spicetify Inferno (preto/vermelho/branco) aplicado"
    else
        warn "spicetify apply falhou — rode: sudo chmod a+wr -R /opt/spotify && spicetify backup apply"
        return 1
    fi
}

# Tema Inferno no ZapZap (CSS/JS WA Web + conf + launcher Qt vermelho).
deploy_zapzap_theme() {
    local src="$PANDORA_ROOT/overlays/zapzap"
    local css_src="$src/customizations/global/css/pandora-inferno.css"
    local js_src="$src/customizations/global/js/pandora-inferno.js"
    # Fallback from installed zapzap-pandora package
    [[ -f "$css_src" ]] || css_src="/usr/share/zapzap-pandora/pandora-inferno.css"
    [[ -f "$js_src" ]] || js_src="/usr/share/zapzap-pandora/pandora-inferno.js"
    local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/ZapZap"
    local css_dir="$data_dir/customizations/global/css"
    local js_dir="$data_dir/customizations/global/js"
    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/ZapZap/ZapZap.conf"
    local desktop_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    local desktop_src="$src/com.rtosta.zapzap.desktop"
    local launcher="$PANDORA_ROOT/scripts/zapzap-pandora"

    [[ -f "$css_src" ]] || {
        warn "deploy_zapzap: CSS ausente ($css_src)"
        return 1
    }

    mkdir -p "$css_dir" "$js_dir" "$(dirname "$conf")" "$desktop_dir"
    cp "$css_src" "$css_dir/pandora-inferno.css"
    [[ -f "$js_src" ]] && cp "$js_src" "$js_dir/pandora-inferno.js"
    # Evita custom.css vazio/conflitante sobrescrever prioridade visual
    if [[ -f "$css_dir/custom.css" ]] && [[ ! -s "$css_dir/custom.css" ]]; then
        rm -f "$css_dir/custom.css"
    fi
    chmod +x "$launcher" 2>/dev/null || true

    if [[ -f "$desktop_src" ]]; then
        sed "s|__PANDORA_ROOT__|$PANDORA_ROOT|g" "$desktop_src" \
            >"$desktop_dir/com.rtosta.zapzap.desktop"
        update-desktop-database "$desktop_dir" 2>/dev/null || true
    fi

    # QSettings (org=ZapZap, app=ZapZap): habilita CSS + JS + dark
    if python3 - <<'PY'
from PyQt6.QtCore import QSettings

s = QSettings("ZapZap", "ZapZap")
s.setValue("custom/global/css/enabled", True)
s.setValue("custom/global/js/enabled", True)
s.setValue("system/theme", "dark")

def clean_disabled(key: str, keep_name: str) -> None:
    disabled = s.value(key, [])
    if disabled is None:
        disabled = []
    if isinstance(disabled, str):
        disabled = [disabled] if disabled else []
    disabled = [x for x in disabled if x and x != keep_name]
    s.setValue(key, disabled)

clean_disabled("custom/global/css/disabled_files", "pandora-inferno.css")
clean_disabled("custom/global/js/disabled_files", "pandora-inferno.js")
s.sync()
print("ok")
PY
    then
        log "Overlay: ZapZap Inferno (CSS+JS) + theme=dark"
    else
        mkdir -p "$(dirname "$conf")"
        touch "$conf"
        if grep -q '^\[custom\]' "$conf" 2>/dev/null; then
            grep -q 'global\\css\\enabled=' "$conf" \
                && sed -i 's|global\\css\\enabled=.*|global\\css\\enabled=true|' "$conf" \
                || sed -i '/^\[custom\]/a global\\css\\enabled=true' "$conf"
            grep -q 'global\\js\\enabled=' "$conf" \
                && sed -i 's|global\\js\\enabled=.*|global\\js\\enabled=true|' "$conf" \
                || sed -i '/^\[custom\]/a global\\js\\enabled=true' "$conf"
        else
            printf '\n[custom]\nglobal\\css\\enabled=true\nglobal\\js\\enabled=true\n' >>"$conf"
        fi
        if grep -q '^\[system\]' "$conf" 2>/dev/null; then
            grep -q '^theme=' "$conf" \
                && sed -i 's|^theme=.*|theme=dark|' "$conf" \
                || sed -i '/^\[system\]/a theme=dark' "$conf"
        else
            printf '\n[system]\ntheme=dark\n' >>"$conf"
        fi
        warn "deploy_zapzap: PyQt6 indisponível — conf editado via sed"
        log "Overlay: ZapZap Inferno (fallback conf)"
    fi
}

# Build/install ZapZap from Pandora packages/zapzap-pandora (Inferno Qt palette).
install_zapzap_pandora() {
    local pkgdir="$PANDORA_ROOT/packages/zapzap-pandora"
    local build="$pkgdir/build.sh"
    [[ -x "$build" ]] || chmod +x "$build"

    if pacman -Q zapzap-pandora &>/dev/null; then
        local ver
        ver="$(pacman -Q zapzap-pandora | awk '{print $2}')"
        log "zapzap-pandora já instalado ($ver) — só redeploy do tema"
        deploy_zapzap_theme || warn "deploy_zapzap_theme falhou"
        return 0
    fi

    log "Compilando zapzap-pandora (fonte upstream + patches Inferno)..."
    bash "$build" || {
        warn "build zapzap-pandora falhou — tentando zapzap AUR + tema"
        pacman_install zapzap || true
        deploy_zapzap_theme || true
        return 1
    }
}

# Aplica cores do scheme.json no cava (enableCava). Fallback: overlay vermelho já copiado.
sync_cava_from_scheme() {
    local scheme_file="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/scheme.json"
    local cava_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/cava/config"

    if [[ ! -f "$scheme_file" ]]; then
        warn "sync_cava: scheme.json ausente — mantendo fallback vermelho (bars=32)"
        return 1
    fi

    if ! python -c "
from caelestia.utils.scheme import get_scheme
from caelestia.utils.theme import apply_cava
apply_cava(get_scheme().colours)
" 2>/dev/null; then
        # Fallback: reaplicar scheme completo (também atualiza cava se enableCava)
        if command -v caelestia >/dev/null 2>&1; then
            local name flavour mode
            name="$(jq -r '.name // empty' "$scheme_file")"
            flavour="$(jq -r '.flavour // "default"' "$scheme_file")"
            mode="$(jq -r '.mode // "dark"' "$scheme_file")"
            [[ -n "$name" ]] || return 1
            caelestia scheme set -n "$name" -f "$flavour" -m "$mode" >/dev/null 2>&1 || {
                warn "sync_cava: falha ao aplicar cores do schema"
                return 1
            }
        else
            warn "sync_cava: caelestia/python ausente — mantendo fallback vermelho (bars=32)"
            return 1
        fi
    fi

    if [[ -f "$cava_cfg" ]] && grep -qE '^bars\s*=\s*32' "$cava_cfg"; then
        log "cava: cores do schema Caelestia + bars=32"
        return 0
    fi
    if [[ -f "$cava_cfg" ]]; then
        warn "sync_cava: config escrita, mas bars≠32 — confira template"
    fi
    return 0
}

deploy_wallpaper_qml() {
    local src="$PANDORA_ROOT/overlays/quickshell/modules/background/Wallpaper.qml"
    local sibling="$PANDORA_ROOT/../shell/modules/background/Wallpaper.qml"
    local dest_dirs=(
        "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia/modules/background"
        "${XDG_STATE_HOME:-$HOME/.local/state}/pandora/build/shell/modules/background"
    )
    local d

    # Prefer fork irmão atualizado, senão overlay embutido
    [[ -f "$sibling" ]] && src="$sibling"
    [[ -f "$src" ]] || return 0

    for d in "${dest_dirs[@]}"; do
        mkdir -p "$d"
        cp -f "$src" "$d/Wallpaper.qml"
    done
    log "Wallpaper.qml: file:// Image (NVIDIA-safe)"
}

deploy_thunar_overlays() {
    local src="$PANDORA_ROOT/overlays"
    local xfce_dest="${XDG_CONFIG_HOME:-$HOME/.config}/xfce4/xfconf/xfce-perchannel-xml"
    local thunar_dest="${XDG_CONFIG_HOME:-$HOME/.config}/Thunar"

    if [[ -f "$src/xfce4/xfconf/xfce-perchannel-xml/thunar.xml" ]]; then
        mkdir -p "$xfce_dest"
        if [[ -f "$xfce_dest/thunar.xml" ]]; then
            if grep -q 'misc-exec-shell-scripts-by-default' "$xfce_dest/thunar.xml" 2>/dev/null; then
                sed -i 's|value="THUNAR_EXECUTE_SHELL_SCRIPT_[A-Z_]*"|value="THUNAR_EXECUTE_SHELL_SCRIPT_ASK"|' \
                    "$xfce_dest/thunar.xml"
            else
                sed -i 's|</channel>|  <property name="misc-exec-shell-scripts-by-default" type="string" value="THUNAR_EXECUTE_SHELL_SCRIPT_ASK"/>\n</channel>|' \
                    "$xfce_dest/thunar.xml"
            fi
        else
            cp "$src/xfce4/xfconf/xfce-perchannel-xml/thunar.xml" "$xfce_dest/thunar.xml"
        fi
        if command -v xfconf-query &>/dev/null; then
            xfconf-query -c thunar -p /misc-exec-shell-scripts-by-default \
                -n -t string -s THUNAR_EXECUTE_SHELL_SCRIPT_ASK 2>/dev/null \
                || xfconf-query -c thunar -p /misc-exec-shell-scripts-by-default \
                    -s THUNAR_EXECUTE_SHELL_SCRIPT_ASK 2>/dev/null || true
        fi
        log "Overlay: thunar shell-scripts ASK"
    fi

    if [[ -f "$src/Thunar/thunar-volman.xml" ]]; then
        mkdir -p "$thunar_dest"
        cp "$src/Thunar/thunar-volman.xml" "$thunar_dest/thunar-volman.xml"
        log "Overlay: Thunar/thunar-volman.xml"
    fi
}

# XDG user dirs em inglês (Documents/Pictures/…) — evita desalinhamento com Wallpapers.
setup_english_user_dirs() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    local dirs_file="$cfg/user-dirs.dirs"
    local locale_file="$cfg/user-dirs.locale"
    local -A map=(
        ["Área de trabalho"]="Desktop"
        ["Documentos"]="Documents"
        ["Downloads"]="Downloads"
        ["Músicas"]="Music"
        ["Imagens"]="Pictures"
        ["Vídeos"]="Videos"
        ["Modelos"]="Templates"
        ["Público"]="Public"
        ["Projetos"]="Projects"
    )
    local old new item
    mkdir -p "$cfg"
    for old in "${!map[@]}"; do
        new="${map[$old]}"
        if [[ -d "$HOME/$old" && ! -e "$HOME/$new" ]]; then
            mv "$HOME/$old" "$HOME/$new"
            log "user-dirs: $old -> $new"
        elif [[ -d "$HOME/$old" && -d "$HOME/$new" ]]; then
            shopt -s dotglob nullglob
            for item in "$HOME/$old"/*; do
                [[ -e "$item" ]] || continue
                mv -n "$item" "$HOME/$new/" 2>/dev/null || true
            done
            shopt -u dotglob nullglob
            rmdir "$HOME/$old" 2>/dev/null || true
        fi
        mkdir -p "$HOME/$new"
    done

    cat >"$dirs_file" <<'EOF'
# PandoraProject — XDG user dirs (English)
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
XDG_PROJECTS_DIR="$HOME/Projects"
EOF
    printf 'en_US\n' >"$locale_file"
    export XDG_DESKTOP_DIR="$HOME/Desktop"
    export XDG_DOWNLOAD_DIR="$HOME/Downloads"
    export XDG_TEMPLATES_DIR="$HOME/Templates"
    export XDG_PUBLICSHARE_DIR="$HOME/Public"
    export XDG_DOCUMENTS_DIR="$HOME/Documents"
    export XDG_MUSIC_DIR="$HOME/Music"
    export XDG_PICTURES_DIR="$HOME/Pictures"
    export XDG_VIDEOS_DIR="$HOME/Videos"
    log "user-dirs: English (Documents/Pictures/…)"
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
# Wallpaper só pelo Caelestia (remove postHook legado se existir)
data.get("wallpaper", {}).pop("postHook", None)
if "wallpaper" in data and not data["wallpaper"]:
    del data["wallpaper"]
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
    local login_wall="$PANDORA_ROOT/scripts/sddm-set-login-wall.sh"
    local dropin="/etc/sudoers.d/caelestia-sddm-sync"
    local lines=()

    [[ -x "$sync_script" || -f "$sync_script" ]] || return 0
    chmod +x "$login_wall" 2>/dev/null || true

    lines+=("$USER ALL=(root) NOPASSWD: $sync_script")
    lines+=("$USER ALL=(root) NOPASSWD: $login_wall")
    lines+=("$USER ALL=(root) NOPASSWD: /usr/bin/bash $login_wall")
    lines+=("$USER ALL=(root) NOPASSWD: /bin/bash $login_wall")

    printf '%s\n' "${lines[@]}" | sudo tee "$dropin" >/dev/null
    sudo chmod 440 "$dropin"
    log "Sudoers: sync SDDM + whitekat login wall sem senha"
}

sync_sddm_theme() {
    deploy_sddm_sudoers
    local sync_script="/usr/share/sddm/themes/caelestia/scripts/sync.sh"
    local login_wall="$PANDORA_ROOT/scripts/sddm-set-login-wall.sh"
    if [[ -x "$sync_script" ]]; then
        sudo "$sync_script" 2>/dev/null || warn "Sync do tema SDDM falhou"
        sudo "$login_wall" 2>/dev/null || bash "$login_wall" 2>/dev/null \
            || warn "Falha ao forçar whitekat no SDDM"
        log "Tema SDDM sincronizado (avatar/cores + login whitekat)"
    fi
}

install_hyprland_session() {
    local system_dir="/usr/local/share/wayland-sessions"
    local user_dir="${XDG_DATA_HOME:-$HOME/.local/share}/wayland-sessions"
    local wrapper_src="$PANDORA_ROOT/scripts/pandora-wayland-session.sh"
    local wrapper_dest="/usr/local/lib/pandora/wayland-session"
    local hypr_src="$PANDORA_ROOT/overlays/wayland-sessions/hyprland.desktop"
    local uwsm_src="$PANDORA_ROOT/overlays/wayland-sessions/hyprland-uwsm.desktop"

    sudo mkdir -p "$system_dir" "$(dirname "$wrapper_dest")"
    mkdir -p "$user_dir"

    # Sessão padrão: start-hyprland (sem UWSM — evita Session started false no SDDM)
    if [[ -f "$hypr_src" ]]; then
        sudo cp -f "$hypr_src" "$system_dir/hyprland.desktop"
        cp -f "$hypr_src" "$user_dir/hyprland.desktop"
    else
        warn "Overlay hyprland.desktop ausente"
    fi
    sudo chmod 644 "$system_dir/hyprland.desktop" 2>/dev/null || true

    # UWSM oculto no seletor (não usar no login greetd)
    if [[ -f "$uwsm_src" ]]; then
        sudo cp -f "$uwsm_src" "$system_dir/hyprland-uwsm.desktop"
        cp -f "$uwsm_src" "$user_dir/hyprland-uwsm.desktop"
        sudo chmod 644 "$system_dir/hyprland-uwsm.desktop" 2>/dev/null || true
    fi

    if [[ -f "$wrapper_src" ]]; then
        sudo cp -f "$wrapper_src" "$wrapper_dest"
        sudo chmod 755 "$wrapper_dest"
    else
        warn "Wrapper wayland-session ausente: $wrapper_src"
    fi

    log "Sessão Wayland: $system_dir/hyprland.desktop (start-hyprland) + SessionCommand=$wrapper_dest"
}

# Compat: callers antigos
install_hyprland_uwsm_session() {
    install_hyprland_session
}

install_caelestia_sddm_fork() {
    local fork_root
    fork_root="$(cd "${PANDORA_CAELESTIA_SDDM:-$PANDORA_ROOT/../caelestia-sddm}" && pwd)"
    local aur_dir="$fork_root/aur"
    local build_dir pkg

    if [[ ! -f "$aur_dir/PKGBUILD" ]]; then
        die "Fork caelestia-sddm ausente: $aur_dir/PKGBUILD (clone https://github.com/PandoraDots/caelestia-sddm.git)"
    fi
    if [[ ! -d "$fork_root/.git" ]]; then
        die "Fork caelestia-sddm sem .git: $fork_root"
    fi
    if ! grep -q 'PandoraDots/caelestia-sddm' "$aur_dir/PKGBUILD"; then
        die "PKGBUILD sem URL PandoraDots: $aur_dir/PKGBUILD"
    fi

    log "Instalando caelestia-sddm-locklike-git do fork local: $fork_root"
    build_dir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$build_dir'" RETURN
    cp -a "$aur_dir/." "$build_dir/"
    # Empacota a partir do clone local (não baixa do AUR/upstream)
    sed -i "s|^source=.*|source=(\"\${pkgbase}::git+file://${fork_root}\")|" "$build_dir/PKGBUILD"

    (
        cd "$build_dir"
        makepkg -f --noconfirm --noprogressbar
        pkg="$(ls -1 caelestia-sddm-locklike-git-*.pkg.tar.* 2>/dev/null | head -1)"
        [[ -n "$pkg" ]] || die "Pacote locklike não gerado em $build_dir"
        sudo pacman -U --noconfirm "$pkg"
    )
    # git+file:// empacota o commit; reaplicar working tree (fixes ainda não commitados)
    if [[ -d "$fork_root/themes/locklike" ]]; then
        sudo cp -a "$fork_root/themes/locklike/." /usr/share/sddm/themes/caelestia/
        [[ -f "$fork_root/scripts/sync.sh" ]] \
            && sudo install -Dm755 "$fork_root/scripts/sync.sh" \
                /usr/share/sddm/themes/caelestia/scripts/sync.sh
        log "Overlay locklike do working tree aplicado em /usr/share/sddm/themes/caelestia"
    fi
    # Pacote grava caelestia.conf — reforça drop-in sem xcb e pandora.conf por cima
    sanitize_caelestia_sddm_conf
    deploy_pandora_sddm_conf
    log "Tema SDDM Caelestia (fork PandoraDots) instalado"
}

# Neutraliza drop-in do pacote: sem xcb e sem Current= (greeter = maldives via 99-pandora).
sanitize_caelestia_sddm_conf() {
    local dest="/etc/sddm.conf.d/caelestia.conf"
    sudo mkdir -p /etc/sddm.conf.d
    sudo tee "$dest" >/dev/null <<'EOF'
[General]
GreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1
EOF
    sudo chmod 644 "$dest"
    # Remover confs de teste que competem com 99-pandora
    sudo rm -f /etc/sddm.conf.d/99-vanilla-test.conf \
        /etc/sddm.conf.d/pandora.conf 2>/dev/null || true
    if grep -q 'QT_QPA_PLATFORM=xcb' "$dest" 2>/dev/null; then
        die "sanitize_caelestia_sddm_conf: ainda há QT_QPA_PLATFORM=xcb em $dest"
    fi
    if grep -qE '^Current=' "$dest" 2>/dev/null; then
        die "sanitize_caelestia_sddm_conf: caelestia.conf não deve forçar Current="
    fi
    log "SDDM: caelestia.conf sem xcb e sem Current= (greeter maldives)"
}

deploy_pandora_sddm_conf() {
    local src="$PANDORA_ROOT/overlays/sddm/pandora.conf"
    local dest="/etc/sddm.conf.d/99-pandora.conf"
    sudo mkdir -p /etc/sddm.conf.d
    sanitize_caelestia_sddm_conf
    if [[ -f "$src" ]]; then
        sudo cp -f "$src" "$dest"
    else
        sudo tee "$dest" >/dev/null <<'EOF'
[Theme]
Current=maldives

[General]
Numlock=on
DisplayServer=x11-user
DefaultSession=hyprland.desktop

[Wayland]
SessionCommand=/usr/local/lib/pandora/wayland-session
EOF
    fi
    sudo chmod 644 "$dest"
    # Garantir que nenhum Current=caelestia reste ativo
    if grep -rhE '^Current=caelestia$' /etc/sddm.conf.d/ 2>/dev/null | grep -q .; then
        warn "Ainda há Current=caelestia em conf.d — removendo de drop-ins do pacote"
        sanitize_caelestia_sddm_conf
    fi
    log "SDDM: greeter=maldives DisplayServer=x11-user DefaultSession=hyprland.desktop ($dest)"
}

deploy_greetd_pam() {
    local src="$PANDORA_ROOT/overlays/greetd/pam.d-greetd"
    local dest="/etc/pam.d/greetd"
    if [[ -f "$src" ]]; then
        sudo cp -f "$src" "$dest"
    else
        sudo tee "$dest" >/dev/null <<'EOF'
#%PAM-1.0
auth       required     pam_securetty.so
auth       requisite    pam_nologin.so
auth       include      system-local-login
auth       optional     pam_gnome_keyring.so
account    include      system-local-login
password   include      system-local-login
-password  optional     pam_gnome_keyring.so use_authtok
session    include      system-local-login
session    optional     pam_gnome_keyring.so auto_start
EOF
    fi
    sudo chmod 644 "$dest"
    if ! grep -q 'pam_gnome_keyring.so' "$dest"; then
        die "deploy_greetd_pam: falta pam_gnome_keyring em $dest"
    fi
    log "greetd PAM: gnome-keyring auto_start ($dest)"
}

prompt_pandora_login() {
    local user_default pass1 pass2
    user_default="${PANDORA_LOGIN_USER:-${USER:-}}"
    [[ -n "$user_default" ]] || die "prompt_pandora_login: USER vazio"

    if [[ "${PANDORA_SKIP_PASS:-0}" == "1" ]]; then
        PANDORA_LOGIN_USER="${PANDORA_LOGIN_USER:-$user_default}"
        log "Login: usuário=$PANDORA_LOGIN_USER (senha não alterada — PANDORA_SKIP_PASS=1)"
    elif [[ -t 0 ]]; then
        read -r -p "Usuário de login [$user_default]: " PANDORA_LOGIN_USER
        PANDORA_LOGIN_USER="${PANDORA_LOGIN_USER:-$user_default}"
        while true; do
            read -r -s -p "Senha para $PANDORA_LOGIN_USER: " pass1
            printf '\n'
            read -r -s -p "Confirme a senha: " pass2
            printf '\n'
            if [[ -z "$pass1" ]]; then
                warn "Senha vazia — tente de novo"
                continue
            fi
            if [[ "$pass1" != "$pass2" ]]; then
                warn "Senhas não coincidem — tente de novo"
                continue
            fi
            break
        done
        PANDORA_LOGIN_PASS="$pass1"
    else
        PANDORA_LOGIN_USER="${PANDORA_LOGIN_USER:-$user_default}"
        if [[ -z "${PANDORA_LOGIN_PASS:-}" ]]; then
            die "prompt_pandora_login: stdin não é TTY — defina PANDORA_LOGIN_USER e PANDORA_LOGIN_PASS (ou PANDORA_SKIP_PASS=1)"
        fi
        log "Login não-interativo: usuário=$PANDORA_LOGIN_USER"
    fi

    if [[ ! "$PANDORA_LOGIN_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        die "Usuário inválido: $PANDORA_LOGIN_USER (use minúsculas, números, _ ou -)"
    fi
    export PANDORA_LOGIN_USER
}

ensure_pandora_login_user() {
    local user groups
    prompt_pandora_login
    user="$PANDORA_LOGIN_USER"
    groups="wheel,video,audio,input,storage"

    if id "$user" &>/dev/null; then
        if [[ "${PANDORA_SKIP_PASS:-0}" == "1" ]]; then
            log "Usuário $user já existe — mantendo senha atual"
        else
            log "Usuário $user já existe — atualizando senha"
        fi
    else
        [[ "${PANDORA_SKIP_PASS:-0}" != "1" ]] || die "Usuário $user não existe e PANDORA_SKIP_PASS=1"
        log "Criando usuário $user..."
        sudo useradd -m -G "$groups" -s /bin/bash "$user" \
            || die "Falha ao criar usuário $user"
    fi

    if [[ "${PANDORA_SKIP_PASS:-0}" != "1" ]]; then
        # Não pipear direto em `sudo chpasswd` — o sudo pode consumir o stdin da senha.
        sudo bash -c 'printf "%s:%s\n" "$1" "$2" | chpasswd' _ "$user" "$PANDORA_LOGIN_PASS" \
            || die "Falha ao definir senha de $user"
        unset PANDORA_LOGIN_PASS
    fi

    if [[ "$user" != "${USER:-}" ]]; then
        warn "Usuário de login ($user) ≠ usuário atual (${USER:-}). Overlays vão para \$HOME de ${USER:-}."
        warn "Rode o restante da install como $user (su - $user) se HOME/config precisar bater."
    fi

    export PANDORA_LOGIN_USER
    log "Login: usuário=$user (greetd initial_session)"
}

deploy_greetd_conf() {
    local src="$PANDORA_ROOT/overlays/greetd/config.toml"
    local dest="/etc/greetd/config.toml"
    local login_user="${PANDORA_LOGIN_USER:-${USER:-}}"
    [[ -n "$login_user" ]] || die "deploy_greetd_conf: PANDORA_LOGIN_USER/USER vazio"

    sudo mkdir -p /etc/greetd
    if [[ -f "$src" ]]; then
        sed "s|__PANDORA_USER__|$login_user|g" "$src" | sudo tee "$dest" >/dev/null
    else
        sudo tee "$dest" >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-session --sessions /usr/local/share/wayland-sessions:/usr/share/wayland-sessions --cmd /usr/bin/start-hyprland"
user = "greeter"

[initial_session]
command = "/usr/bin/start-hyprland"
user = "$login_user"
EOF
    fi
    sudo chmod 644 "$dest"
    if ! grep -qE '^\[initial_session\]' "$dest" \
        || ! grep -qE "^user = \"$login_user\"$" "$dest"; then
        die "deploy_greetd_conf: initial_session/user=$login_user ausente em $dest"
    fi
    deploy_greetd_pam
    log "greetd: autologin $login_user → start-hyprland; tuigreet após logout ($dest)"
}

enable_greetd_disable_sddm() {
    deploy_greetd_conf
    install_hyprland_session
    sudo systemctl disable --now sddm.service 2>/dev/null || true
    sudo systemctl enable greetd.service
    log "DM: greetd enabled, sddm disabled (evita greeter X11/NVIDIA)"
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
    if [[ -f "$src/pandora-equibop-ss-audio-guard.service" ]]; then
        sed "s|%h/PandoraProject|$PANDORA_ROOT|g" "$src/pandora-equibop-ss-audio-guard.service" \
            >"$unit_dir/pandora-equibop-ss-audio-guard.service"
        chmod +x "$PANDORA_ROOT/scripts/equibop-ss-audio-guard.sh" 2>/dev/null || true
    fi
    if [[ -f "$src/pandora-fan-curve.service" ]]; then
        sed "s|%h/PandoraProject|$PANDORA_ROOT|g" "$src/pandora-fan-curve.service" \
            >"$unit_dir/pandora-fan-curve.service"
        chmod +x "$PANDORA_ROOT/scripts/perfectsense-fan-curve.sh" 2>/dev/null || true
    fi
    systemctl --user daemon-reload 2>/dev/null || true
    # Path observa o mesmo sysfs que o script escreve → loop; preferir timer
    systemctl --user disable --now pandora-gpu-profile.path 2>/dev/null || true
    systemctl --user enable --now pandora-gpu-profile.timer 2>/dev/null || true
    systemctl --user enable --now pandora-equibop-ss-audio-guard.service 2>/dev/null || true
    systemctl --user enable --now pandora-fan-curve.service 2>/dev/null || true
}

link_wallpapers() {
    local dirs_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    # shellcheck disable=SC1090
    [[ -f "$dirs_file" ]] && source "$dirs_file"
    local pictures="${XDG_PICTURES_DIR:-$HOME/Pictures}"
    pictures="${pictures/#\$HOME/$HOME}"
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
# Caelestia dots ≥ ago/2026 usa pwvucontrol como app de áudio padrão.
install_audio_stack() {
    local -a pkgs=(
        pipewire pipewire-pulse pipewire-audio pipewire-alsa
        wireplumber pwvucontrol
    )

    pacman_install "${pkgs[@]}"

    if ! pacman -Q pwvucontrol &>/dev/null; then
        pacman_install pavucontrol || warn "Nem pwvucontrol nem pavucontrol instalados"
    fi

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
    local with_tags="${4:-0}"

    if [[ -d "$dest/.git" ]]; then
        git -C "$dest" fetch origin "$branch" >&2
        if [[ "$with_tags" == "1" ]]; then
            git -C "$dest" fetch --tags origin >&2 2>/dev/null || true
        fi
        git -C "$dest" checkout "$branch" >&2
        git -C "$dest" pull --ff-only origin "$branch" >&2 \
            || warn "Pull falhou em $dest; usando checkout local"
    else
        mkdir -p "$(dirname "$dest")"
        if [[ "$with_tags" == "1" ]]; then
            git clone --branch "$branch" "$url" "$dest" >&2
            git -C "$dest" fetch --tags origin >&2 2>/dev/null || true
        else
            git clone --depth 1 --branch "$branch" "$url" "$dest" >&2
        fi
    fi
}

# Exporta helpers para subshells (bash -c). Sem isso, pacman_install/aur_install etc.
# falham com "comando não encontrado" em instalação limpa.
pandora_export_helpers() {
    export PANDORA_ROOT PANDORA_MODEL PANDORA_AUR_HELPER
    export PANDORA_STATE PANDORA_CONFIG PANDORA_BUILD
    export PANDORA_DOTS_URL PANDORA_CLI_URL PANDORA_SHELL_URL PANDORA_NEKRO_URL
    export PANDORA_LOGIN_USER

    local fn
    local -a fns=(
        log warn die require_cmd run_step model_config
        deploy_overlays deploy_user_icon patch_cli_json configure_keyboard_layout
        deploy_sddm_sudoers sync_sddm_theme deploy_systemd_units link_wallpapers
        deploy_wallpaper_qml deploy_pandora_sddm_conf deploy_greetd_conf deploy_greetd_pam
        deploy_zapzap_theme install_zapzap_pandora deploy_spicetify_inferno
        enable_greetd_disable_sddm prompt_pandora_login ensure_pandora_login_user
        sync_cava_from_scheme
        install_hyprland_session install_hyprland_uwsm_session install_caelestia_sddm_fork
        sanitize_caelestia_sddm_conf
        ensure_paru pacman_install aur_install aur_install_one clone_or_pull install_audio_stack
        pandora_pkg_alias pkg_in_repos pkg_in_aur pkg_available
        skip_if_ready pandora_cli_ready pandora_shell_ready caelestia_dots_ready
        pandora_overlays_ready scheme_inferno_ready hydra_ready orion_ready user_unit_enabled
        pandora_runtime_stamp pandora_runtime_changed save_pandora_runtime_stamp
        pandora_hyprland_version_ok pandora_hyprland_min_version
        pandora_pkg_qv pandora_repo_rev pandora_runtime_stamp_path
        ensure_pandora_quickshell
        install_hydra_launcher find_hydra_binary find_hydra_desktop
        hydra_desktop_path hydra_icon_path hydra_extract_icon
        install_orion_binary install_orion_launcher find_orion_binary
        orion_desktop_path orion_icon_path orion_extract_icon orion_latest_release_info
        ensure_fuse_for_appimage orion_host_arch_token orion_state_tag_file orion_bin_link
        ensure_caelestia_cli_deps
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
