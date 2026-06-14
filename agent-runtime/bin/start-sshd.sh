#!/bin/bash
# Start SSH server (for VS Code Remote-SSH)
set -e

if ! command -v sshd &>/dev/null; then
    return 0 2>/dev/null || exit 0
fi

SSH_KEYS_DIR=/home/work/.ssh-keys
AK_FILE=$SSH_KEYS_DIR/authorized_keys

mkdir -p "$SSH_KEYS_DIR"
if [ -n "$SSH_PUBLIC_KEY" ]; then
    echo "$SSH_PUBLIC_KEY" > "$AK_FILE"
elif ls /home/work/.ssh/*.pub &>/dev/null; then
    cat /home/work/.ssh/*.pub > "$AK_FILE"
fi

if [ -f "$AK_FILE" ]; then
    chown -R node:node "$SSH_KEYS_DIR"
    chmod 700 "$SSH_KEYS_DIR"
    chmod 600 "$AK_FILE"
fi

if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

if ! grep -q AuthorizedKeysFile /etc/ssh/sshd_config.d/onecode.conf 2>/dev/null; then
    echo "AuthorizedKeysFile /home/work/.ssh-keys/authorized_keys" >> /etc/ssh/sshd_config.d/onecode.conf
fi

/usr/sbin/sshd
echo "[ssh] SSH server started on port ${SSH_PORT:-8222}"
