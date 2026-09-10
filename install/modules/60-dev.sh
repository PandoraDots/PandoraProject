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
  rustup \
  dotnet-sdk-8.0 dotnet-sdk-10.0 \
  docker docker-compose

# rustup default toolchain as user
if command -v rustup >/dev/null; then
  as_user rustup default stable || as_user rustup toolchain install stable
  as_user rustup component add rustfmt clippy || true
fi

install_prefer cursor-bin || warn "cursor-bin (AUR) falhou"
install_prefer rider || warn "rider (AUR) falhou — IDE grande; tente depois: paru -S rider"

# Docker opcional para o user
usermod -aG docker "$REAL_USER" 2>/dev/null || true
systemd_enable docker.service || true

ok "Dev stack instalada"
