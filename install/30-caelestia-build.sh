#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

resolve_local_repo() {
    local name="$1"
    local remote_url="$2"
    local local_path="$PANDORA_ROOT/../$name"
    if [[ -d "$local_path/.git" ]]; then
        printf '%s' "$local_path"
    else
        local dest="$PANDORA_BUILD/$name"
        clone_or_pull "$remote_url" "$dest"
        printf '%s' "$dest"
    fi
}

CLI_DIR="$(resolve_local_repo cli "$PANDORA_CLI_URL")"
SHELL_DIR="$(resolve_local_repo shell "$PANDORA_SHELL_URL")"

run_step "Build cli ($CLI_DIR)" bash -c "
    cd '$CLI_DIR'
    python -m build --wheel
    sudo python -m installer dist/*.whl --force
    sudo install -Dm644 completions/caelestia.fish /usr/share/fish/vendor_completions.d/caelestia.fish
"

run_step "Build shell ($SHELL_DIR)" bash -c "
    cd '$SHELL_DIR'
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/
    cmake --build build
    sudo cmake --install build
"

require_cmd caelestia qs
log "caelestia CLI e shell instalados do source."
