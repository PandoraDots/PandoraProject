#!/usr/bin/env bash
# Offline regression tests: no package manager or system mutations.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
export BUILD_DIR="$scratch/build" REAL_USER="$(id -un)"
# Load helpers without running common.sh's build-directory initialization.
source <(sed '/^mkdir -p "\$BUILD_DIR" "\$AUR_CACHE"/,$d' "$ROOT/lib/common.sh")
assert_status() {
  local expected="$1" actual=0
  shift
  "$@" || actual=$?
  [[ "$actual" == "$expected" ]] || {
    printf 'FAIL: %s returned %s, expected %s\n' "$*" "$actual" "$expected" >&2
    exit 1
  }
}
restore_cached_package() { return 1; }
pkg_installed() { return 1; }
pac_available() { [[ "$1" != unavailable ]]; }
pacman() { printf 'called\n' >>"$scratch/pacman"; return 23; }
assert_status 1 pac_install available unavailable
[[ ! -e "$scratch/pacman" ]]
assert_status 23 pac_install available
assert_status 23 install_prefer available
pac_available() { return 1; }
aur_available() { return 0; }
aur_install() { return 24; }
assert_status 24 install_prefer aur-package
aur_available() { return 1; }
ensure_paru() { return 1; }
assert_status 1 install_prefer unavailable
pkg_installed() { return 0; }
assert_status 0 pac_install installed
assert_status 0 install_prefer installed
assert_status 0 pac_install
printf 'PASS: required packages, transaction failures, AUR failures, fallback and idempotence\n'
