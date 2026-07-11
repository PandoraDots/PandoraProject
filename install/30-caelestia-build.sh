#!/usr/bin/env bash
set -euo pipefail
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
    if pandora_cli_ready; then
        log "caelestia CLI já instalado: $(command -v caelestia)"
        return 0
    fi

    cd "$CLI_DIR"
    python -m build --wheel
    sudo python -m installer --overwrite-existing dist/*.whl
    sudo install -Dm644 completions/caelestia.fish /usr/share/fish/vendor_completions.d/caelestia.fish
}

build_shell() {
    if pandora_shell_ready; then
        log "caelestia shell (qs) já instalado: $(command -v qs)"
        return 0
    fi

    cd "$SHELL_DIR"
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/
    cmake --build build
    sudo cmake --install build
}

if ! skip_if_ready "Build cli ($CLI_DIR)" pandora_cli_ready; then
    run_step "Build cli ($CLI_DIR)" build_cli
fi

if ! skip_if_ready "Build shell ($SHELL_DIR)" pandora_shell_ready; then
    run_step "Build shell ($SHELL_DIR)" build_shell
fi

require_cmd caelestia qs
log "caelestia CLI e shell instalados do source."
