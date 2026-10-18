#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
export BUILD_DIR="$scratch/build"
source <(sed '/^mkdir -p "\$BUILD_DIR" "\$AUR_CACHE"/,$d' "$ROOT/lib/common.sh")
resolve_user() { REAL_HOME="$scratch/home"; REAL_UID="$(id -u)"; REAL_GID="$(id -g)"; }
as_user() { "$@"; }
resolve_user
mkdir -p "$AUR_CACHE" "$REAL_HOME"
# Missing package files must not be considered ready.
pacman() { [[ "$1" == -Q ]]; }
if pkg_installed broken; then exit 1; fi
pacman() { return 0; }
pkg_installed complete
# Archive identity and payload must both validate before installation.
touch "$AUR_CACHE/demo-debug-1.pkg.tar.zst" "$AUR_CACHE/demo-1.pkg.tar.zst"
pacman() {
  case "$1" in
    -Qp) if [[ "$3" == *debug* ]]; then echo 'demo-debug 1'; else echo 'demo 1'; fi ;;
    -U) printf '%s\n' "$3" > "$scratch/installed" ;;
    *) return 0 ;;
  esac
}
bsdtar() { return 1; }
if restore_cached_package demo; then exit 1; fi
[[ ! -e "$scratch/installed" ]]
bsdtar() { return 0; }
restore_cached_package demo
[[ "$(cat "$scratch/installed")" == "$AUR_CACHE/demo-1.pkg.tar.zst" ]]
# ELF checks reject empty executables and missing shared libraries.
touch "$scratch/empty"; chmod +x "$scratch/empty"
if native_binary_ready "$scratch/empty"; then exit 1; fi
native_binary_ready /usr/bin/true
ldd() { echo 'libmissing.so => not found'; }
if native_binary_ready /usr/bin/true; then exit 1; fi
unset -f ldd
printf 'PASS: package health, cache identity/payload, ELF checks\n'
