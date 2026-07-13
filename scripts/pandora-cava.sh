#!/usr/bin/env bash
# Espera o dashboard redimensionar o foot (bars=32 precisa de ~100+ cols), depois: cava
set -euo pipefail
export PANDORA_DASHBOARD=1

for _ in $(seq 1 120); do
    cols="$(tput cols 2>/dev/null || echo 0)"
    if [[ "$cols" -ge 100 ]]; then
        break
    fi
    sleep 0.05
done

exec cava
