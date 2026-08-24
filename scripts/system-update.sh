#!/usr/bin/env bash
# Atualização segura do sistema + Pandora (Hyprland, Caelestia, AUR críticos).
#
# Ordem:
#   1) keyring
#   2) paru -Syu (repos + AUR)
#   3) rebuild AUR ligados a Hyprland/libcava (quickshell-git, libcava)
#   4) scripts/update.sh com rebuild forçado do cli/shell
#   5) verify-install.sh
#
# Uso:
#   ~/PandoraProject/scripts/system-update.sh
#   ~/PandoraProject/scripts/system-update.sh --noconfirm
#   ~/PandoraProject/scripts/system-update.sh --skip-verify
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PANDORA_ROOT
source "$PANDORA_ROOT/install/lib.sh"

NOCONFIRM=0
SKIP_VERIFY=0
SKIP_SYSTEM=0

for arg in "$@"; do
    case "$arg" in
        --noconfirm) NOCONFIRM=1 ;;
        --skip-verify) SKIP_VERIFY=1 ;;
        --skip-system) SKIP_SYSTEM=1 ;;
        -h|--help)
            cat <<'EOF'
Uso: system-update.sh [--noconfirm] [--skip-verify] [--skip-system]

  --noconfirm    Passa --noconfirm ao paru
  --skip-verify  Não roda verify-install.sh no final
  --skip-system  Só Pandora (update.sh + rebuild), sem paru -Syu
EOF
            exit 0
            ;;
        *)
            die "Argumento desconhecido: $arg (use --help)"
            ;;
    esac
done

paru_flags=(-Syu)
if [[ "$NOCONFIRM" -eq 1 ]]; then
    paru_flags+=(--noconfirm)
fi

preflight() {
    log "Pré-voo: versões atuais"
    pacman -Q hyprland aquamarine hyprutils libcava cava quickshell-git foot xdg-desktop-portal-hyprland 2>/dev/null || true

    if ! pandora_hyprland_version_ok; then
        warn "Hyprland atual < $(pandora_hyprland_min_version). O update deve trazer ≥0.56 (hl.dsp + cursor capture)."
    fi

    if command -v checkupdates &>/dev/null; then
        local crit
        crit="$(checkupdates 2>/dev/null | rg -i '^(hyprland|aquamarine|hyprutils|xdg-desktop-portal-hyprland|libcava|quickshell|linux-cachyos|nvidia|mesa)\b' || true)"
        if [[ -n "$crit" ]]; then
            log "Updates críticos pendentes:"
            printf '%s\n' "$crit"
            if printf '%s\n' "$crit" | rg -q '^hyprland .* -> 0\.5[6-9]|^hyprland .* -> [1-9]'; then
                log "Hyprland 0.56+: upstream declara sem breaking changes; Pandora já usa hl.dsp."
            fi
            if printf '%s\n' "$crit" | rg -q '^libcava '; then
                log "libcava muda → shell Caelestia será recompilado (liga cavacore)."
            fi
        else
            log "Nenhum update crítico hypr/cava/qs listado por checkupdates (ou base já sincronizada)."
        fi
    fi

    log "Forks locais atrás do upstream caelestia-dots:"
    local name dir behind
    for name in cli shell caelestia; do
        dir=""
        [[ -d "$PANDORA_ROOT/../$name/.git" ]] && dir="$PANDORA_ROOT/../$name"
        [[ -z "$dir" && -d "$PANDORA_BUILD/$name/.git" ]] && dir="$PANDORA_BUILD/$name"
        if [[ -z "$dir" ]]; then
            warn "  $name: fork não encontrado"
            continue
        fi
        git -C "$dir" fetch upstream main --quiet 2>/dev/null \
            || git -C "$dir" remote add upstream "https://github.com/caelestia-dots/$name.git" 2>/dev/null \
            || true
        git -C "$dir" fetch upstream main --quiet 2>/dev/null || true
        behind="$(git -C "$dir" rev-list --count HEAD..upstream/main 2>/dev/null || echo "?")"
        log "  $name: $behind commit(s) atrás (merge em update.sh)"
    done
}

rebuild_aur_critical() {
    # Religar qs/libcava após -Syu (Qt/hypr ABI). Sempre força rebuild do qs —
    # --needed pula se a versão AUR não mudou e deixa qs quebrado (Qt_6_PRIVATE_API).
    local -a aur_pkgs=()
    local -a repo_pkgs=()
    local -a paru_rebuild=(--aur)

    if pacman -Q noctalia-qs &>/dev/null; then
        warn "Removendo noctalia-qs (conflita com Quickshell do Caelestia)..."
        sudo pacman -R --noconfirm noctalia-qs || warn "Falha ao remover noctalia-qs"
    fi

    if pacman -Q quickshell-git &>/dev/null; then
        aur_pkgs+=(quickshell-git)
    elif pacman -Q quickshell &>/dev/null; then
        repo_pkgs+=(quickshell)
    else
        ensure_pandora_quickshell
    fi

    if pacman -Q libcava &>/dev/null; then
        aur_pkgs+=(libcava)
    fi

    if [[ ${#repo_pkgs[@]} -gt 0 ]]; then
        log "Reinstalando Quickshell (repos): ${repo_pkgs[*]}"
        if [[ "$NOCONFIRM" -eq 1 ]]; then
            sudo pacman -S --noconfirm --needed "${repo_pkgs[@]}" || warn "Reinstall quickshell falhou"
        else
            sudo pacman -S --needed "${repo_pkgs[@]}" || warn "Reinstall quickshell falhou"
        fi
    fi

    if [[ ${#aur_pkgs[@]} -eq 0 ]]; then
        [[ ${#repo_pkgs[@]} -gt 0 ]] || warn "Nenhum pacote AUR crítico para rebuild"
        return 0
    fi

    if [[ "$NOCONFIRM" -eq 1 ]]; then
        paru_rebuild+=(--noconfirm)
    fi
    log "Rebuild forçado AUR crítico (Qt/hypr ABI; ignore noctalia-qs): ${aur_pkgs[*]}"
    "$PANDORA_AUR_HELPER" -S "${paru_rebuild[@]}" --ignore noctalia-qs "${aur_pkgs[@]}" \
        || warn "Rebuild AUR parcial falhou — rode: paru -S --aur --ignore noctalia-qs ${aur_pkgs[*]}"
}

# Módulo out-of-tree: precisa recompilar quando o kernel muda.
rebuild_nekro_if_needed() {
    local kver module_ver nekro_dir headers mdir verm
    kver="$(uname -r)"

    nekro_dir=""
    [[ -d "$PANDORA_ROOT/../nekro-sense/.git" ]] && nekro_dir="$PANDORA_ROOT/../nekro-sense"
    [[ -z "$nekro_dir" && -d "$PANDORA_BUILD/nekro-sense/.git" ]] && nekro_dir="$PANDORA_BUILD/nekro-sense"
    [[ -z "$nekro_dir" && -f "$PANDORA_ROOT/../nekro-sense/install-nekro.sh" ]] && nekro_dir="$PANDORA_ROOT/../nekro-sense"

    if [[ -z "$nekro_dir" ]]; then
        warn "nekro-sense: fonte não encontrada — pulei rebuild"
        return 0
    fi

    for headers in /lib/modules/*/build; do
        [[ -d "$headers" ]] || continue
        headers="$(basename "$(dirname "$headers")")"
        mdir="/lib/modules/$headers/kernel/drivers/platform/x86"
        if [[ -f "$mdir/nekro_sense.ko" ]]; then
            verm="$(modinfo -F vermagic "$mdir/nekro_sense.ko" 2>/dev/null | awk '{print $1}' || true)"
            if [[ "$verm" == "$headers" ]]; then
                log "nekro_sense OK para $headers"
                continue
            fi
        fi

        log "Build nekro_sense para $headers..."
        # CachyOS kernels são clang; GCC falha com flags LLVM do Kbuild
        if ! make -C "$nekro_dir" LLVM=1 KVER="$headers" clean all; then
            warn "build falhou para $headers"
            continue
        fi

        if [[ "$headers" == "$kver" ]]; then
            (cd "$nekro_dir" && sudo make LLVM=1 KVER="$headers" install) \
                || warn "install nekro falhou para $headers"
        else
            # Kernel ainda não bootado: só copia o .ko (sem modprobe)
            sudo install -d "$mdir"
            sudo install -m 644 "$nekro_dir/src/nekro_sense.ko" "$mdir/nekro_sense.ko"
            sudo depmod -a "$headers" || true
            log "nekro_sense.ko instalado para $headers (ativa no próximo boot)"
        fi
    done

    sudo systemctl enable --now nekro_sense.service 2>/dev/null || true
}

post_update_overlays() {
    log "Reaplicando overlays Pandora (ZapZap + Spicetify Inferno)..."
    deploy_overlays || warn "deploy_overlays falhou"
    # Garante pacote Inferno (substitui zapzap AUR se ainda estiver genérico)
    if ! pacman -Q zapzap-pandora &>/dev/null; then
        install_zapzap_pandora || warn "install_zapzap_pandora falhou"
    else
        deploy_zapzap_theme || warn "deploy_zapzap_theme falhou"
    fi
    deploy_spicetify_inferno || warn "deploy_spicetify_inferno falhou"
}

run_system_update() {
    ensure_paru
    if is_cachyos; then
        ensure_cachyos_repos || true
    fi

    log "Atualizando archlinux-keyring..."
    if [[ "$NOCONFIRM" -eq 1 ]]; then
        sudo pacman -Sy --noconfirm --needed archlinux-keyring || warn "keyring update falhou"
    else
        sudo pacman -Sy --needed archlinux-keyring || warn "keyring update falhou"
    fi

    # Evita que o CachyOS troque quickshell-git pelo fork Noctalia (incompatível com Caelestia).
    paru_flags+=(--ignore noctalia-qs)

    log "paru ${paru_flags[*]} (repos + AUR)..."
    "$PANDORA_AUR_HELPER" "${paru_flags[@]}" || die "paru -Syu falhou — corrija e rode de novo"

    rebuild_aur_critical
    rebuild_nekro_if_needed
}

run_pandora_update() {
    export PANDORA_FORCE_REBUILD=1
    log "Pandora update (merge forks + rebuild cli/shell + overlays)..."
    bash "$PANDORA_ROOT/scripts/update.sh"
    post_update_overlays
}

run_verify() {
    log "Verificação pós-update..."
    bash "$PANDORA_ROOT/scripts/verify-install.sh" --model "${PANDORA_MODEL:-phn16-72}" || {
        warn "verify-install reportou falhas — veja ~/.local/state/pandora/verify-install-latest.log"
        return 1
    }
}

preflight

if [[ "$SKIP_SYSTEM" -eq 1 ]]; then
    log "Pulando paru -Syu (--skip-system)"
else
    run_system_update
fi

run_pandora_update

if [[ "$SKIP_VERIFY" -eq 1 ]]; then
    log "Pulando verify (--skip-verify)"
else
    run_verify || true
fi

log "system-update concluído."
log "Reinicie a sessão Hyprland (logout/login) para carregar Hyprland/qs/shell novos."
