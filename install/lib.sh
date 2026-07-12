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
    # qs (quickshell-git) sozinho não basta — precisa do shell.qml do caelestia-shell
    command -v qs &>/dev/null && pandora_shell_qsconf &>/dev/null
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

waywallen_desktop_path() {
    printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/applications/org.waywallen.waywallen.desktop"
}

waywallen_icon_path() {
    printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/org.waywallen.waywallen.svg"
}

waywallen_ready() {
    [[ -x "${HOME}/.local/bin/waywallen" ]] || return 1
    [[ -f "$(waywallen_desktop_path)" ]] || return 1
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
        # enabled=false ou ausente tratado: precisa estar habilitado (default true)
        jq -e '.background.enabled != false' "$shell_json" &>/dev/null || return 1
    fi
    # Daemon Waywallen ativo cobre o Caelestia com layer preto no NVIDIA
    if systemctl --user is-active waywallen.service &>/dev/null; then
        return 1
    fi
    return 0
}

install_waywallen_launcher() {
    local bin="${HOME}/.local/bin/waywallen"
    local ui_wrapper="$PANDORA_ROOT/scripts/waywallen-ui.sh"
    local ui_link="${HOME}/.local/bin/waywallen-ui"
    local desktop_src="$PANDORA_ROOT/assets/waywallen/org.waywallen.waywallen.desktop"
    local icon_src="$PANDORA_ROOT/assets/waywallen/org.waywallen.waywallen.svg"
    local desktop_dst icon_dst apps_dir icons_dir

    [[ -x "$bin" ]] || {
        warn "Waywallen binário ausente: $bin"
        return 1
    }
    [[ -f "$ui_wrapper" ]] || {
        warn "Wrapper Waywallen ausente: $ui_wrapper"
        return 1
    }
    chmod +x "$ui_wrapper" "$PANDORA_ROOT/scripts/waywallen-bridge.sh" 2>/dev/null || true
    ln -sfn "$ui_wrapper" "$ui_link"

    apps_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    icons_dir="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
    desktop_dst="$(waywallen_desktop_path)"
    icon_dst="$(waywallen_icon_path)"
    mkdir -p "$apps_dir" "$icons_dir"

    if [[ -f "$icon_src" ]]; then
        cp -f "$icon_src" "$icon_dst"
    else
        warn "Ícone Waywallen ausente em $icon_src"
    fi

    if [[ -f "$desktop_src" ]]; then
        # --no-display via wrapper: evita layer preto no NVIDIA
        sed -e "s|^Exec=.*|Exec=${ui_link}|" \
            -e "s|^Icon=.*|Icon=org.waywallen.waywallen|" \
            "$desktop_src" >"$desktop_dst"
    else
        cat >"$desktop_dst" <<EOF
[Desktop Entry]
Type=Application
Name=Waywallen
GenericName=Wallpaper Manager for Linux
Comment=Seletor de wallpaper (renderizado pelo Caelestia no Hyprland)
Exec=${ui_link}
Icon=org.waywallen.waywallen
Terminal=false
Categories=Graphics;Qt;
Keywords=wallpaper;pipewire;vulkan;
StartupNotify=true
EOF
    fi
    chmod 644 "$desktop_dst"

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$apps_dir" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" 2>/dev/null || true
    fi
    log "Waywallen launcher: $desktop_dst"
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
    deploy_thunar_overlays
    deploy_systemd_units
    deploy_user_icon
    deploy_wallpaper_qml
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

install_hyprland_uwsm_session() {
    local src="$PANDORA_ROOT/overlays/wayland-sessions/hyprland-uwsm.desktop"
    local wrapper_src="$PANDORA_ROOT/scripts/pandora-wayland-session.sh"
    # SDDM greeter (user sddm) não lê ~/.local — prioridade: /usr/local/share
    local system_dir="/usr/local/share/wayland-sessions"
    local system_dest="$system_dir/hyprland-uwsm.desktop"
    local user_dir="${XDG_DATA_HOME:-$HOME/.local/share}/wayland-sessions"
    local user_dest="$user_dir/hyprland-uwsm.desktop"
    local wrapper_dest="/usr/local/lib/pandora/wayland-session"
    local content

    if [[ -f "$src" ]]; then
        content="$(cat "$src")"
    else
        content='[Desktop Entry]
Name=Hyprland (uwsm-managed)
Comment=An intelligent dynamic tiling Wayland compositor
Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop
TryExec=uwsm
DesktopNames=Hyprland
Type=Application'
    fi

    sudo mkdir -p "$system_dir" "$(dirname "$wrapper_dest")"
    printf '%s\n' "$content" | sudo tee "$system_dest" >/dev/null
    sudo chmod 644 "$system_dest"

    if [[ -f "$wrapper_src" ]]; then
        sudo cp -f "$wrapper_src" "$wrapper_dest"
        sudo chmod 755 "$wrapper_dest"
    else
        warn "Wrapper wayland-session ausente: $wrapper_src"
    fi

    # Espelho opcional (não é o que o greeter usa)
    mkdir -p "$user_dir"
    printf '%s\n' "$content" >"$user_dest"
    chmod 644 "$user_dest"

    log "Sessão Wayland: $system_dest (uwsm -g -1) + SessionCommand=$wrapper_dest"
}

deploy_pandora_sddm_conf() {
    local src="$PANDORA_ROOT/overlays/sddm/pandora.conf"
    sudo mkdir -p /etc/sddm.conf.d
    if [[ -f "$src" ]]; then
        sudo cp -f "$src" /etc/sddm.conf.d/pandora.conf
    else
        sudo tee /etc/sddm.conf.d/pandora.conf >/dev/null <<'EOF'
[Theme]
Current=caelestia

[General]
Numlock=on
DisplayServer=x11-user
EOF
    fi
    sudo chmod 644 /etc/sddm.conf.d/pandora.conf
    log "SDDM: DisplayServer=x11-user (greeter X11 estável)"
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
    # Path observa o mesmo sysfs que o script escreve → loop; preferir timer
    systemctl --user disable --now pandora-gpu-profile.path 2>/dev/null || true
    systemctl --user enable --now pandora-gpu-profile.timer 2>/dev/null || true
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

    local fn
    local -a fns=(
        log warn die require_cmd run_step model_config
        deploy_overlays deploy_user_icon patch_cli_json configure_keyboard_layout
        deploy_sddm_sudoers sync_sddm_theme deploy_systemd_units link_wallpapers
        deploy_wallpaper_qml
        ensure_paru pacman_install aur_install aur_install_one clone_or_pull install_audio_stack
        pandora_pkg_alias pkg_in_repos pkg_in_aur pkg_available
        skip_if_ready pandora_cli_ready pandora_shell_ready caelestia_dots_ready
        pandora_overlays_ready scheme_inferno_ready waywallen_ready user_unit_enabled
        install_waywallen_launcher
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
