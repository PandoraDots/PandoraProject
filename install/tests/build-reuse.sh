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
# Load only module functions, never its installation entry point.
source <(sed -n '/^hydra_appimage_ready()/,/^log "Codecs/{ /^log "Codecs/d; p; }' "$ROOT/modules/70-apps.sh")
sung_ready() { return 0; }
pac_install() { echo 'unexpected installation' >&2; return 91; }
install_sung
# The reusable native build must reach cmake install without a build invocation.
sung_ready() { [[ -e "$scratch/repaired" ]]; }
mkdir -p "$BUILD_DIR/Sung/.git" "$BUILD_DIR/Sung/build"
printf data > "$BUILD_DIR/Sung/build/cmake_install.cmake"
cp /usr/bin/true "$BUILD_DIR/Sung/build/sung"
pac_install() { return 0; }
as_user() {
  case "$1" in
    cmake) [[ "$2" == --install ]]; touch "$scratch/repaired" ;;
    python3|*/runtime/bin/python) return 0 ;;
    *) echo "unexpected build: $*" >&2; return 92 ;;
  esac
}
install_sung
printf 'PASS: package health, cache identity/payload, ELF checks, Sung skip and build reuse\n'
