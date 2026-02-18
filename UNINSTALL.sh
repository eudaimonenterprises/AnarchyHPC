#!/bin/bash
set -euo pipefail

echo "=== AnarchyHPC Uninstaller ==="
echo "This will remove AnarchyHPC system modifications."
echo "It will NOT remove user data or unrelated packages."
echo

read -rp "Proceed with uninstall? (y/N): " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && { echo "Aborted."; exit 0; }

# ---------------------------------------------------------------------------
# Helper: remove a file if it exists
# ---------------------------------------------------------------------------
remove_file() {
    local f="$1"
    if sudo test -f "$f"; then
        echo "Removing file: $f"
        sudo rm -f "$f"
    fi
}

# ---------------------------------------------------------------------------
# Helper: remove a directory if it exists
# ---------------------------------------------------------------------------
remove_dir() {
    local d="$1"
    if sudo test -d "$d"; then
        echo "Removing directory: $d"
        sudo rm -rf "$d"
    fi
}

# ---------------------------------------------------------------------------
# 1. Remove AnarchyHPC configuration directory
# ---------------------------------------------------------------------------
echo
echo "--- Removing /etc/anarchy ---"
remove_dir /etc/anarchy

# ---------------------------------------------------------------------------
# 2. Restore SELinux configuration if we modified it
# ---------------------------------------------------------------------------
if sudo test -f /etc/selinux/config; then
    echo
    echo "--- Checking SELinux state ---"
    if grep -q "SELINUX=permissive" /etc/selinux/config; then
        echo "Restoring SELinux to enforcing mode"
        sudo sed -i 's/SELINUX=permissive/SELINUX=enforcing/' /etc/selinux/config || true
        echo "Attempting to re-enable enforcing mode (may require reboot)"
        sudo setenforce 1 || true
    fi
fi

# ---------------------------------------------------------------------------
# 3. Remove ZFS if installed by AnarchyHPC
# ---------------------------------------------------------------------------
echo
echo "--- Checking for ZFS installation ---"
if rpm -q zfs >/dev/null 2>&1; then
    echo "Removing ZFS packages"
    sudo dnf remove -y zfs zfs-dkms || true
fi

remove_file /etc/modules-load.d/zfs.conf

# ---------------------------------------------------------------------------
# 4. Remove repos added by prepare.sh
# ---------------------------------------------------------------------------
echo
echo "--- Removing EPEL and ZFS repos if present ---"

if rpm -q epel-release >/dev/null 2>&1; then
    echo "Removing epel-release"
    sudo dnf remove -y epel-release || true
fi

# ZFS repo file name varies; remove any matching patterns
for f in /etc/yum.repos.d/zfs*.repo /etc/yum.repos.d/zfsonlinux*.repo; do
    [[ -f "$f" ]] && remove_file "$f"
done

# ---------------------------------------------------------------------------
# 5. Remove Ansible collections installed by prepare.sh
# ---------------------------------------------------------------------------
echo
echo "--- Removing Ansible collections installed by AnarchyHPC ---"

# Remove collections manually if they exist
COLL_DIR="$HOME/.ansible/collections/ansible_collections"

sudo rm -rf "$COLL_DIR/community/mysql" 2>/dev/null || true
sudo rm -rf "$COLL_DIR/ansible/posix" 2>/dev/null || true
sudo rm -rf "$COLL_DIR/community/general" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 6. Remove packages installed specifically by prepare.sh
# ---------------------------------------------------------------------------
echo
echo "--- Removing packages installed by AnarchyHPC ---"

sudo dnf remove -y ansible ansible-core || true

# ---------------------------------------------------------------------------
# 7. Remove leftover temp files
# ---------------------------------------------------------------------------
echo
echo "--- Cleaning up temporary files ---"
sudo rm -f /tmp/mesg.*.dat 2>/dev/null || true

# ---------------------------------------------------------------------------
# 8. Final message
# ---------------------------------------------------------------------------
echo
echo "=== Uninstall complete ==="
echo "System-level components installed by AnarchyHPC have been removed."
echo "Your site/ directory and user SSH keys were intentionally preserved."
echo
echo "A reboot is recommended if SELinux or kernel modules were modified."
