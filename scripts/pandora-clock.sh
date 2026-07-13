#!/usr/bin/env bash
# Relógio do dashboard — vermelho puro (#ff0000).
set -euo pipefail
export PANDORA_DASHBOARD=1
# Reforça palette (caso o foot herde sequences do schema)
printf '\e]11;#000000\e\\'
printf '\e]10;#ff0000\e\\'
printf '\e]4;1;#ff0000\e\\'
printf '\e]4;9;#ff0000\e\\'
exec tty-clock -c -C 1 -b
