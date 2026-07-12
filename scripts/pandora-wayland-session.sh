#!/bin/bash
# SessionCommand do SDDM (Pandora).
# Evita /usr/share/sddm/scripts/wayland-session → fish --login,
# que no cold start (handoff X11/NVIDIA → Wayland) deixa ~30s de silêncio
# e o SDDM marca "Session started false" + reinicia o greeter.
set -euo pipefail

if [[ $# -eq 1 ]]; then
    exec /bin/bash -c "$1"
fi
exec "$@"
