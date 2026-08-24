#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
LOG=/tmp/pandora-update/ps-final.txt
{
  echo "=== final PerfectSense smoke $(date) ==="
  rm -f ~/.local/state/pandora/perfectsense.json
  # Não escrever RGB aqui — pode travar o EC; logo + hypr bastam para baseline
  printf 'ff0000,70,1\n' > /sys/devices/platform/acer-wmi/back_logo/color 2>/dev/null || true
  hyprctl -q eval 'hl.monitor({ output = "eDP-1", mode = "highrr", position = "0x0", scale = 1.25 })' || true
  hyprctl -q eval 'hl.config({ animations = { enabled = true }, decoration = { blur = { enabled = true }, shadow = { enabled = true } } })' || true

  echo '--- quiet ---'
  perfectsense mode set quiet || echo "quiet exit:$?"
  sleep 1
  echo "ec=$(cat /sys/firmware/acpi/platform_profile)"
  echo "logo=$(tr -d '\n' < /sys/devices/platform/acer-wmi/back_logo/color)"
  hyprctl monitors -j | jq -c '.[0]|{hz:.refreshRate}'
  hyprctl getoption animations:enabled -j 2>/dev/null || true

  echo '--- balanced ---'
  perfectsense mode set balanced || echo "balanced exit:$?"
  sleep 1
  echo "ec=$(cat /sys/firmware/acpi/platform_profile)"
  echo "logo=$(tr -d '\n' < /sys/devices/platform/acer-wmi/back_logo/color)"
  hyprctl monitors -j | jq -c '.[0]|{hz:.refreshRate}'
  hyprctl getoption animations:enabled -j 2>/dev/null || true

  if command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
    sudo cp -f /home/perfect/shell/services/PerfectSense.qml /etc/xdg/quickshell/caelestia/services/PerfectSense.qml
    sudo cp -f /home/perfect/shell/modules/dashboard/PerfectSense.qml /etc/xdg/quickshell/caelestia/modules/dashboard/PerfectSense.qml
    sudo cp -f /home/perfect/shell/modules/bar/popouts/Battery.qml /etc/xdg/quickshell/caelestia/modules/bar/popouts/Battery.qml
  else
    echo "(skip QML sync — precisa sudo; rode deploy ou sudo cp)"
  fi
  caelestia shell -k || true
  sleep 1
  caelestia shell -d || true
  sleep 2
  qs -c caelestia ipc call perfectSense status || true
  echo DONE
} | tee "$LOG"
echo
echo "Log: $LOG — Enter para fechar"
read -r
