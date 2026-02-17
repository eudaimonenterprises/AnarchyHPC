#!/usr/bin/env bash
set -euo pipefail

echo "=== AnarchyHPC SSH Setup ==="

# -----------------------------
# 1. Select LOCAL user (owner of the private key)
# -----------------------------
echo
echo "Which LOCAL user should own the SSH key?"
echo "(This user will manage the cluster after installation. Root can still use the key during install.)"
read -rp "Local username [$(logname)]: " LOCAL_USER
LOCAL_USER=${LOCAL_USER:-$(logname)}

# Determine local user's home directory
LOCAL_HOME=$(eval echo "~${LOCAL_USER}")

if [[ ! -d "$LOCAL_HOME" ]]; then
    echo "ERROR: Local user '$LOCAL_USER' does not exist or has no home directory." >&2
    exit 1
fi

DEFAULT_KEY_PATH="${LOCAL_HOME}/.ssh/anarchy_id_ed25519"

# -----------------------------
# 2. Controller connection info
# -----------------------------
echo
read -rp "Controller hostname or IP: " CONTROLLER_HOST

read -rp "SSH username for controller [centos]: " CONTROLLER_USER
CONTROLLER_USER=${CONTROLLER_USER:-centos}

echo
echo "Do you already have SSH key-based access to the controller?"
read -rp "[y/N]: " HAVE_KEY
HAVE_KEY=${HAVE_KEY:-n}

SSH_KEY_PATH=""

# -----------------------------
# 3. Existing key path
# -----------------------------
if [[ "$HAVE_KEY" =~ ^[Yy]$ ]]; then
    read -rp "Path to your existing LOCAL SSH private key: " SSH_KEY_PATH
    SSH_KEY_PATH=${SSH_KEY_PATH/#\~/$LOCAL_HOME}

    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        echo "ERROR: Key '$SSH_KEY_PATH' not found." >&2
        exit 1
    fi

    chmod 600 "$SSH_KEY_PATH" || true

    echo
    echo "Testing SSH access..."
    if ! ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=10 \
        "${CONTROLLER_USER}@${CONTROLLER_HOST}" true 2>/dev/null; then
        echo "ERROR: Unable to authenticate with the provided key." >&2
        exit 1
    fi

else
    # -----------------------------
    # 4. Choose where to store new key (LOCAL machine)
    # -----------------------------
    echo
    echo "Where should the new LOCAL SSH key be stored?"
    echo "1) Default: ${DEFAULT_KEY_PATH}"
    echo "2) Custom path"
    read -rp "Choose [1/2]: " KEY_CHOICE

    case "$KEY_CHOICE" in
        1|"")
            SSH_KEY_PATH="$DEFAULT_KEY_PATH"
            ;;
        2)
            read -rp "Enter full path for new LOCAL SSH private key: " SSH_KEY_PATH
            SSH_KEY_PATH=${SSH_KEY_PATH/#\~/$LOCAL_HOME}
            ;;
        *)
            echo "Invalid choice." >&2
            exit 1
            ;;
    esac

    SSH_PUB_PATH="${SSH_KEY_PATH}.pub"
    SSH_DIR=$(dirname "$SSH_KEY_PATH")

    # -----------------------------
    # 5. Ensure directory exists with correct permissions
    # -----------------------------
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chown "$LOCAL_USER":"$LOCAL_USER" "$SSH_DIR"

    # -----------------------------
    # 6. Generate key if missing
    # -----------------------------
    if [[ -f "$SSH_KEY_PATH" ]]; then
        echo
        read -rp "Key already exists at '$SSH_KEY_PATH'. Reuse it? [Y/n]: " REUSE
        REUSE=${REUSE:-y}
        if [[ ! "$REUSE" =~ ^[Yy]$ ]]; then
            echo "Aborting to avoid overwriting existing key." >&2
            exit 1
        fi
    else
        echo
        echo "Generating SSH key at '$SSH_KEY_PATH'..."
        ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "anarchyhpc@${HOSTNAME}"

        # Fix ownership and permissions
        chown "$LOCAL_USER":"$LOCAL_USER" "$SSH_KEY_PATH" "$SSH_PUB_PATH"
        chmod 600 "$SSH_KEY_PATH"
        chmod 644 "$SSH_PUB_PATH"
    fi

    # -----------------------------
    # 7. Install public key on controller
    # -----------------------------
    echo
    echo "Installing public key on controller (you will be prompted for password)..."

    if command -v ssh-copy-id >/dev/null 2>&1; then
        ssh-copy-id -i "$SSH_PUB_PATH" "${CONTROLLER_USER}@${CONTROLLER_HOST}"
    else
        echo "ssh-copy-id not found, using fallback method."
        scp "$SSH_PUB_PATH" "${CONTROLLER_USER}@${CONTROLLER_HOST}:/tmp/anarchyhpc_key.pub"
        ssh "${CONTROLLER_USER}@${CONTROLLER_HOST}" \
            "mkdir -p ~/.ssh && cat /tmp/anarchyhpc_key.pub >> ~/.ssh/authorized_keys && rm -f /tmp/anarchyhpc_key.pub && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
    fi

    # -----------------------------
    # 8. Test key-based access
    # -----------------------------
    echo
    echo "Testing SSH access with new key..."
    if ! ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=10 \
        "${CONTROLLER_USER}@${CONTROLLER_HOST}" true 2>/dev/null; then
        echo "ERROR: Key-based SSH login failed." >&2
        exit 1
    fi
fi

# -----------------------------
# 9. Output inventory snippet
# -----------------------------
echo
echo "=== SSH setup complete ==="
echo
echo "Use this in your Ansible inventory:"
echo
cat <<EOF
[controllers]
controller1 ansible_host=${CONTROLLER_HOST} ansible_user=${CONTROLLER_USER} ansible_ssh_private_key_file=${SSH_KEY_PATH} ansible_become=true
EOF

echo
echo "Note: Ansible will prompt for the sudo password when needed."
