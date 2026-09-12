#!/usr/bin/env bash
# 60 — Dev toolchains: vim, node, .NET 8+10, Rider, C/C++, Rust, Cursor
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_root
resolve_user

log "Toolchains de desenvolvimento"

pac_install \
  vim neovim \
  nodejs npm \
  clang llvm lld lldb \
  gcc gdb cmake ninja meson \
  python python-pip python-virtualenv \
  dotnet-sdk-8.0 dotnet-sdk-10.0 \
  docker docker-compose

# paru may already have installed the distro Rust toolchain; rustup conflicts
# with that package. Keep a working distro toolchain on repeated installations.
if ! pkg_installed rust && ! pkg_installed rustup; then
  pac_install rustup
fi

# rustup default toolchain as user
if command -v rustup >/dev/null; then
  if as_user rustup show active-toolchain 2>/dev/null | grep -q '^stable-'; then
    already_ok
  else
    as_user rustup default stable
  fi
  for component in rustfmt clippy; do
    if as_user rustup component list --installed | grep -q "^${component}-"; then
      already_ok
    else
      as_user rustup component add "$component" || true
    fi
  done
fi

install_prefer cursor-bin || warn "cursor-bin (AUR) falhou"
install_prefer rider || warn "rider (AUR) falhou — IDE grande; tente depois: paru -S rider"

# Docker opcional para o user
if id -nG "$REAL_USER" | tr ' ' '\n' | grep -qx docker; then
  already_ok
else
  usermod -aG docker "$REAL_USER" 2>/dev/null || true
fi
systemd_enable docker.service || true

ok "Dev stack instalada"
