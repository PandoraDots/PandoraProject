#!/usr/bin/env bash
# Aplica permissões PerfectSense (sysfs nekro + platform_profile) sem senha.
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="/etc/tmpfiles.d/nekro_sense.conf"
SUDOERS="/etc/sudoers.d/pandora-perfectsense"
HELPER_SRC="$PANDORA_ROOT/scripts/pandora-sysfs-write"
HELPER_DST="/usr/local/bin/pandora-sysfs-write"
PS="$PANDORA_ROOT/scripts/perfectsense"

chmod +x "$PS" "$HELPER_SRC"
sudo install -Dm755 "$HELPER_SRC" "$HELPER_DST"

entries=(
    "f /sys/module/nekro_sense/drivers/platform:acer-wmi/acer-wmi/back_logo/color 0660 root nekro_sense"
    "f /sys/firmware/acpi/platform_profile 0660 root nekro_sense"
    "f /sys/class/platform-profile/platform-profile-0/profile 0660 root nekro_sense"
)

sudo touch "$CONF"
for e in "${entries[@]}"; do
    grep -qxF "$e" "$CONF" || echo "$e" | sudo tee -a "$CONF" >/dev/null
done
sudo systemd-tmpfiles --create "$CONF" 2>/dev/null || true

if ! getent group nekro_sense >/dev/null; then
    sudo groupadd nekro_sense
fi
sudo usermod -aG nekro_sense "${SUDO_USER:-$USER}" 2>/dev/null || true

# Sem ':' no sudoers — só o helper fixo
cat <<EOF | sudo tee "$SUDOERS" >/dev/null
# Pandora PerfectSense — helper de escrita sysfs
${USER} ALL=(root) NOPASSWD: ${HELPER_DST}
EOF
sudo chmod 440 "$SUDOERS"
sudo visudo -cf "$SUDOERS"

echo "PerfectSense perms OK"
