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
mkdir -p "$REAL_HOME/.config/paru"
conf="$REAL_HOME/.config/paru/paru.conf"
printf '# old installer\nSkipReview\nSudoLoop\nBottomUp\n[bin]\nSudo = sudo\n' >"$conf"
configure_paru
[[ "$(head -1 "$conf")" == '[options]' ]]
[[ "$(grep -c '^SkipReview$' "$conf")" == 1 ]]
grep -qx 'Sudo = sudo' "$conf"
cp "$conf" "$scratch/expected"
configure_paru
cmp "$conf" "$scratch/expected"
touch "$scratch/perfectsense-debug-1.pkg.tar.zst" "$scratch/perfectsense-1.pkg.tar.zst" "$scratch/perfectsense-1.pkg.tar.zst.sig"
pacman() {
  if [[ "$1" == -Qp ]]; then
    case "$3" in
      *-debug-*) echo 'perfectsense-debug 1';;
      *) echo 'perfectsense 1';;
    esac
  else
    printf '%s\n' "$3" >"$scratch/installed"
  fi
}
bsdtar() { return 0; }
install_built_package perfectsense "$scratch"
[[ "$(cat "$scratch/installed")" == "$scratch/perfectsense-1.pkg.tar.zst" ]]
pacman() { if [[ "$1" == -Qp ]]; then echo 'perfectsense 1'; else return 23; fi; }
status=0
install_built_package perfectsense "$scratch" || status=$?
[[ "$status" == 23 ]]
printf 'PASS: Paru repair/idempotence, package identity and installation failure\n'
