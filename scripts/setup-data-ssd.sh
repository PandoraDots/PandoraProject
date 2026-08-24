#!/usr/bin/env bash
# Monta o Kingston 1TB (label DATA) em /mnt/data com fstab + permissões do usuário.
set -euo pipefail

# Kingston 1TB DATA (Pandora) — UUID fixo deste notebook; fallback por LABEL=DATA
UUID="dfd5686c-0b7d-4c4f-9151-104bff20f8c9"
MOUNT="/mnt/data"
USER_NAME="${SUDO_USER:-perfect}"
GROUP_NAME="$(id -gn "$USER_NAME" 2>/dev/null || echo "$USER_NAME")"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Este script precisa de root (sudo/pkexec)." >&2
    exit 1
fi

if ! blkid -U "$UUID" >/dev/null 2>&1; then
    # Portável: tenta LABEL=DATA se o UUID deste Helios não existir
    alt="$(blkid -L DATA 2>/dev/null || true)"
    if [[ -n "$alt" ]]; then
        UUID="$(blkid -s UUID -o value "$alt" 2>/dev/null || true)"
    fi
fi
if [[ -z "$UUID" ]] || ! blkid -U "$UUID" >/dev/null 2>&1; then
    echo "Disco DATA não encontrado (UUID/LABEL). Pulando." >&2
    exit 0
fi

mkdir -p "$MOUNT"

# Desmonta automount udisks e qualquer montagem anterior
if findmnt /run/media/perfect/DATA >/dev/null 2>&1; then
    umount /run/media/perfect/DATA || true
fi
if findmnt "$MOUNT" >/dev/null 2>&1; then
    umount "$MOUNT" || true
fi

if ! grep -qF "$UUID" /etc/fstab; then
    cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d-%H%M%S)"
    cat >>/etc/fstab <<EOF

# Kingston 1TB DATA (Pandora)
UUID=$UUID $MOUNT btrfs defaults,noatime,compress=zstd:1,ssd,discard=async 0 0
EOF
    echo "Entrada adicionada ao /etc/fstab"
else
    echo "UUID já presente no fstab"
fi

findmnt --verify >/dev/null
mount "$MOUNT"
chown "${USER_NAME}:${GROUP_NAME}" "$MOUNT"
chmod 755 "$MOUNT"

# Symlink conveniente no home do usuário
user_home="$(getent passwd "$USER_NAME" | cut -d: -f6)"
if [[ -n "$user_home" && -d "$user_home" ]]; then
    ln -sfn "$MOUNT" "$user_home/DATA"
    chown -h "${USER_NAME}:${GROUP_NAME}" "$user_home/DATA" 2>/dev/null || true
    echo "OK: $user_home/DATA → $MOUNT"
fi

echo "OK: $MOUNT montado e gravável por $USER_NAME"
df -h "$MOUNT"
findmnt "$MOUNT"
stat -c 'owner=%U:%G perms=%A' "$MOUNT"
