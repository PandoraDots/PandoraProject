#!/usr/bin/env bash
# Helpers para priorizar pacotes otimizados do CachyOS (drivers, kernel, repos).

: "${PANDORA_ROOT:?}"

CACHYOS_SKIP_PACKAGES=(
    nvidia-open-dkms
    nvidia-dkms
    linux-headers
)

is_cachyos() {
    [[ -f /etc/pacman.conf ]] && grep -qE '^\[cachyos' /etc/pacman.conf \
        || pacman -Qq cachyos-keyring &>/dev/null \
        || pacman -Qq cachyos-settings &>/dev/null
}

ensure_cachyos_repos() {
    is_cachyos || return 0

    if ! grep -qE '^\[cachyos' /etc/pacman.conf 2>/dev/null; then
        warn "Repositórios CachyOS ausentes em /etc/pacman.conf — builds otimizados podem não ser usados"
        return 1
    fi

    sudo pacman -Sy --noconfirm
    log "Repositórios CachyOS sincronizados"
}

cachyos_pkg_available() {
    local pkg="$1"
    pacman -Si "$pkg" &>/dev/null
}

cachyos_preferred_pkg() {
    local pkg="$1"
    local candidate

    if cachyos_pkg_available "$pkg"; then
        printf '%s' "$pkg"
        return 0
    fi

    for candidate in "${pkg}-cachyos" "cachyos-${pkg}"; do
        if cachyos_pkg_available "$candidate"; then
            warn "Pacote $pkg -> $candidate (variante CachyOS)"
            printf '%s' "$candidate"
            return 0
        fi
    done

    printf '%s' "$pkg"
}

cachyos_should_skip_pkg() {
    local pkg="$1"
    local skip
    for skip in "${CACHYOS_SKIP_PACKAGES[@]}"; do
        [[ "$pkg" == "$skip" ]] && return 0
    done
    return 1
}

cachyos_list_kernel_packages() {
    local model_file="${1:-}"
    local kernel

    if [[ -n "$model_file" && -f "$model_file" ]]; then
        jq -r '.cachyos.kernels[]?' "$model_file" 2>/dev/null | while read -r kernel; do
            [[ -n "$kernel" ]] && printf '%s\n' "$kernel"
        done
        return 0
    fi

    pacman -Qqe 2>/dev/null | grep -E '^linux-cachyos' \
        | grep -Ev '(nvidia|headers|meta|settings|dbgsym|docs)' || true
}

cachyos_nvidia_module_packages() {
    local model_file="${1:-}"
    local kernel module

    while IFS= read -r kernel; do
        [[ -z "$kernel" ]] && continue
        module="${kernel}-nvidia-open"
        if cachyos_pkg_available "$module"; then
            printf '%s\n' "$module"
            continue
        fi
        module="${kernel}-nvidia"
        if cachyos_pkg_available "$module"; then
            warn "Módulo open indisponível; usando $module para $kernel"
            printf '%s\n' "$module"
        else
            warn "Módulo NVIDIA não encontrado para $kernel"
        fi
    done < <(cachyos_list_kernel_packages "$model_file")
}

cachyos_kernel_header_packages() {
    local model_file="${1:-}"
    local kernel

    while IFS= read -r kernel; do
        [[ -z "$kernel" ]] && continue
        if cachyos_pkg_available "${kernel}-headers"; then
            printf '%s\n' "${kernel}-headers"
        else
            warn "Headers não encontrados: ${kernel}-headers"
        fi
    done < <(cachyos_list_kernel_packages "$model_file")
}

cachyos_resolve_packages() {
    local pkg resolved
    local -A seen=()
    local model_file="${PANDORA_MODEL_FILE:-}"

    for pkg in "$@"; do
        [[ -z "$pkg" ]] && continue

        if cachyos_should_skip_pkg "$pkg"; then
            if [[ "$pkg" == nvidia-open-dkms || "$pkg" == nvidia-dkms ]]; then
                while IFS= read -r module; do
                    [[ -z "$module" || -n "${seen[$module]:-}" ]] && continue
                    seen[$module]=1
                    printf '%s\n' "$module"
                done < <(cachyos_nvidia_module_packages "$model_file")
            fi
            continue
        fi

        if [[ "$pkg" == linux-cachyos-lts-headers || "$pkg" == linux-cachyos-headers || "$pkg" == linux-headers ]]; then
            while IFS= read -r headers; do
                [[ -z "$headers" || -n "${seen[$headers]:-}" ]] && continue
                seen[$headers]=1
                printf '%s\n' "$headers"
            done < <(cachyos_kernel_header_packages "$model_file")
            continue
        fi

        resolved="$(cachyos_preferred_pkg "$pkg")"
        [[ -z "$resolved" || -n "${seen[$resolved]:-}" ]] && continue
        seen[$resolved]=1
        printf '%s\n' "$resolved"
    done
}

install_cachyos_gpu_drivers() {
    local model_file="$1"
    local -a pkgs=()
    local pkg

    export PANDORA_MODEL_FILE="$model_file"
    ensure_cachyos_repos || true

    mapfile -t pkgs < <(jq -r '
        (.packages.nvidia[]?),
        (.packages.intel[]?),
        (.packages.power[]?),
        (.packages.kernel_headers? // empty)
    ' "$model_file" | cachyos_resolve_packages)

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        warn "Nenhum pacote de driver resolvido para CachyOS"
        return 1
    fi

    log "Drivers CachyOS: ${pkgs[*]}"
    pacman_install "${pkgs[@]}"
}
