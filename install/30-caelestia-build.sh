#!/usr/bin/env bash
set -euo pipefail

PANDORA_ROOT="${PANDORA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export PANDORA_ROOT
PANDORA_MODEL="${PANDORA_MODEL:-phn16-72}"
export PANDORA_MODEL

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

resolve_local_repo() {
    local name="$1"
    local remote_url="$2"
    local with_tags="${3:-0}"
    local local_path="$PANDORA_ROOT/../$name"
    local dest=""

    if [[ -d "$local_path/.git" ]]; then
        dest="$local_path"
    else
        dest="$PANDORA_BUILD/$name"
        clone_or_pull "$remote_url" "$dest" main "$with_tags"
    fi

    [[ -d "$dest" ]] || die "Repositório $name inválido: $dest"
    printf '%s' "$dest"
}

CLI_DIR="$(resolve_local_repo cli "$PANDORA_CLI_URL" 1)"
SHELL_DIR="$(resolve_local_repo shell "$PANDORA_SHELL_URL" 1)"

build_cli() {
    ensure_caelestia_cli_deps

    if pandora_cli_ready; then
        log "caelestia CLI já funcional: $(command -v caelestia)"
        return 0
    fi

    if command -v caelestia &>/dev/null; then
        log "caelestia instalado — corrigindo dependências Python"
        ensure_caelestia_cli_deps
        pandora_cli_ready || die "caelestia CLI não funcional (materialyoucolor/pillow)"
        return 0
    fi

    cd "$CLI_DIR"
    python -m build --wheel
    sudo python -m installer --overwrite-existing dist/*.whl
    sudo install -Dm644 completions/caelestia.fish /usr/share/fish/vendor_completions.d/caelestia.fish
    ensure_caelestia_cli_deps
    pandora_cli_ready || die "caelestia CLI não funcional após instalação"
}

build_shell() {
    require_cmd qs
    if pandora_shell_ready; then
        log "caelestia shell já instalado: $(pandora_shell_qsconf)"
        return 0
    fi

    local git_rev version
    git_rev="$(git -C "$SHELL_DIR" rev-parse HEAD)"
    version="$(git -C "$SHELL_DIR" describe --tags --abbrev=0 2>/dev/null || true)"
    if [[ -z "$version" ]]; then
        version="0.0.1"
        warn "Repo shell sem tags — usando VERSION=$version GIT_REVISION=$git_rev"
    else
        version="${version#v}"
    fi

    log "Compilando caelestia-shell em $SHELL_DIR (qs sozinho não basta)"
    cd "$SHELL_DIR"
    cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/ \
        -DVERSION="$version" \
        -DGIT_REVISION="$git_rev" \
        -DDISTRIBUTOR=PandoraProject
    cmake --build build

    if sudo -n cmake --install build; then
        log "caelestia-shell instalado em /etc/xdg/quickshell/caelestia (system)"
        rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/shell-qml.env"
    else
        warn "sudo sem senha indisponível — instalando shell em ~/.config/quickshell/caelestia"
        install_shell_userlocal "$SHELL_DIR"
    fi

    pandora_shell_ready || die "shell.qml não encontrado após install"
}

install_shell_userlocal() {
    local shell_dir="${1:?}"
    local build="$shell_dir/build"
    local qsconf="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
    local qmldir="${HOME}/.local/lib/qt6/qml"
    local libdir="${HOME}/.local/lib/caelestia"
    local envfile="${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/shell-qml.env"
    local dir

    mkdir -p "$qsconf" "$qmldir" "$libdir" "$(dirname "$envfile")"

    for dir in assets components modules services utils; do
        rm -rf "$qsconf/$dir"
        cp -a "$shell_dir/$dir" "$qsconf/$dir"
    done
    if [[ -f "$build/qml/shell.qml" ]]; then
        cp -a "$build/qml/shell.qml" "$qsconf/shell.qml"
    else
        cp -a "$shell_dir/shell.qml" "$qsconf/shell.qml"
    fi
    chmod +x "$qsconf/assets/wrap_term_launch.sh" 2>/dev/null || true

    if [[ -d "$build/qml/Caelestia" ]]; then
        rm -rf "$qmldir/Caelestia"
        cp -a "$build/qml/Caelestia" "$qmldir/Caelestia"
    fi
    if [[ -d "$build/qml/M3Shapes" ]]; then
        rm -rf "$qmldir/M3Shapes"
        cp -a "$build/qml/M3Shapes" "$qmldir/M3Shapes"
    fi
    find "$build/plugin" -name 'libcaelestia-*.so' -exec cp -a {} "$libdir/" \; 2>/dev/null || true
    find "$build" -name 'libm3shapes*.so*' -exec cp -a {} "$libdir/" \; 2>/dev/null || true

    cat >"$envfile" <<EOF
export QML2_IMPORT_PATH="$qmldir"
export QML_IMPORT_PATH="$qmldir"
export LD_LIBRARY_PATH="$libdir"
EOF
    log "shell user-local: $qsconf (+ plugins em $qmldir)"
}

if ! skip_if_ready "Build cli ($CLI_DIR)" pandora_cli_ready; then
    run_step "Build cli ($CLI_DIR)" build_cli
fi

if ! skip_if_ready "Build shell ($SHELL_DIR)" pandora_shell_ready; then
    run_step "Build shell ($SHELL_DIR)" build_shell
fi

require_cmd caelestia qs
log "caelestia CLI e shell instalados do source."
