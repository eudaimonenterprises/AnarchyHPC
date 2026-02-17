#!/bin/bash
set -euo pipefail

# /etc/anarchy requires root
if [ ! -d /etc/anarchy ]; then
    sudo mkdir -p /etc/anarchy
fi

# --------------------------------------------------------------------------------------

function add_message() {
  echo -e "$1" | fold -w70 -s >> /tmp/mesg.$$.dat
}

function show_message() {
  echo "****************************************************************************"
  echo "*                                                                          *"
  while read -r LINE
  do
    printf '*  %-70s  *\n' "$LINE"
  done < /tmp/mesg.$$.dat
  echo "*                                                                          *"
  echo "****************************************************************************"
  truncate -s0 /tmp/mesg.$$.dat
}

function get_confirmation() {
  local DEFAULT=$1
  local MESG=$2
  local CONFIRM=""
  while [ ! "$CONFIRM" ]; do
    case $DEFAULT in
      [Yy]|yes|Yes|YES)
        echo -n "$MESG? (<y>|n): " >&2
        ;;
      *)
        echo -n "$MESG? (y|<n>): " >&2
        ;;
    esac
    read -t 600 CONFIRM
    RET=$?
    if [ "$RET" == "142" ] || [ ! "$CONFIRM" ]; then
      CONFIRM=$DEFAULT
    fi
    case $CONFIRM in
      [Yy]|yes|Yes|YES)
         echo yes
         ;;
      [Nn]|no|No|NO)
         echo no
         ;;
      *)
         CONFIRM=""
         ;;
    esac
  done
}

function store_config() {
  local KEY=$1
  local VALUE=$2
  # prepare.conf lives in /etc → needs sudo
  if sudo test -f /etc/anarchy/prepare.conf && sudo grep -q "^${KEY}=" /etc/anarchy/prepare.conf; then
    sudo sed -i "s/^${KEY}=.*$/${KEY}=${VALUE}/" /etc/anarchy/prepare.conf
  else
    echo "${KEY}=${VALUE}" | sudo tee -a /etc/anarchy/prepare.conf >/dev/null
  fi
}

# --------------------------------------------------------------------------------------

if sudo test -f /etc/anarchy/prepare.conf; then
  # read via sudo, but export into current shell
  while IFS='=' read -ra line; do
    comment=$(echo "${line[*]}" | grep '^#' || true)
    if [ ! "$comment" ]; then
      if [ "${line[*]}" ]; then
        key=$(echo "${line[0]}")
        value=$(echo "${line[1]}")
        declare -x "${key}"="${value}"
        echo "$key = $value"
      fi
    fi
  done < <(sudo cat /etc/anarchy/prepare.conf)
fi

# --------------------- SELINUX TASKS ----------------------

SELINUX=$(getenforce || echo "Disabled")

if [ "$SELINUX" == "Disabled" ]; then
    add_message "SELinux seems to be disabled on the controller"
    add_message "If you continue, the flag enable_selinux will be set to false"
    add_message "This means you will continue without using SELinux"
    show_message
    if [ ! "${NO_SELINUX:-}" ] && [ ! "${GITLAB_CI:-}" ]; then
      NO_SELINUX=$(get_confirmation n "Do you want to proceed without SELinux")
      store_config 'NO_SELINUX' "$NO_SELINUX"
    fi
    if [ "${NO_SELINUX:-}" == "no" ]; then
      add_message "Please have a look in /etc/selinux/config, configure SELINUX to permissive, reboot and try the installation again"
      show_message
      exit 1
    fi
    # group_vars is in repo → no sudo
    sed -i 's/^enable_selinux:\s\+true/enable_selinux: false/g' site/group_vars/all.yml*
else
  if [ "$SELINUX" == "Permissive" ]; then
    echo "SELinux in permissive state"
  else
    add_message "SELinux is currently not configured in permissive state"
    add_message "AnarchyHPC currently only supports permissive SELinux"
    show_message
    PERM_SELINUX=$(get_confirmation y "Do you want to proceed with permissive SELinux")
    if [ "$PERM_SELINUX" == "no" ] && [ ! "${GITLAB_CI:-}" ]; then
      add_message "Please reconsider having a look in /etc/selinux/config, configure SELINUX to permissive, setenforce 0 and try the installation again"
      show_message
      exit 1
    fi
    # needs root
    sudo setenforce 0
    sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
  fi
fi

# --------------------- TUI INSTALL (removed) ---------------------
echo "Skipping vendor TUI download (replaced with upstream-safe version)."

# --------------------- SYSTEM UPDATES & PACKAGES ----------------

if [ "${GITLAB_CI:-}" ]; then
    sudo dnf update -y --exclude=kernel*
else
    sudo dnf update -y
fi

sudo dnf install -y curl tar git

# ------------------- ANSIBLE INSTALL --------------------

OS_ID=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
OS_VER=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')

case "$OS_ID" in
  rhel)
    echo "Detected RHEL $OS_VER"
    ARCH=$(uname -m)
    sudo subscription-manager repos --enable codeready-builder-for-rhel-${OS_VER}-${ARCH}-rpms
    sudo dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_VER}.noarch.rpm"
    ;;

  rocky|almalinux)
    echo "Detected $OS_ID $OS_VER"
    sudo dnf install -y epel-release
    sudo dnf config-manager --set-enabled crb || true
    ;;

  centos)
    echo "Detected CentOS Stream $OS_VER"
    sudo dnf install -y epel-release
    sudo dnf config-manager --set-enabled crb || true
    ;;

  *)
    echo "Unknown OS: $OS_ID — attempting generic EPEL install"
    sudo dnf install -y epel-release || true
    ;;
esac

sudo dnf install -y ansible ansible-core ansible-collection-community-general ansible-collection-ansible-posix || true

# ansible-galaxy can run unprivileged (installs into user space by default)
ansible-galaxy collection install community.mysql
ansible-galaxy install OndrejHome.pcs-modules-2

# --------------------- KERNEL CHECK ----------------------

CURRENT_KERNEL=$(uname -r)
LATEST_KERNEL=$(ls -tr /lib/modules/ | tail -n1)

if [ "${USE_CURRENT_KERNEL:-}" != "yes" ] && [ "$CURRENT_KERNEL" != "$LATEST_KERNEL" ] && [ ! "${GITLAB_CI:-}" ]; then
  add_message "Current running kernel is not the latest installed. It comes highly recommended to reboot prior continuing installation."
  add_message "After reboot, please re-run prepare.sh to make sure all requirements are met."
  show_message
  USE_CURRENT_KERNEL=$(get_confirmation n "Do you want to proceed with current kernel")
  if [ "$USE_CURRENT_KERNEL" == "no" ]; then
    exit 1
  fi
fi

# ---------------------- ZFS INSTALL ----------------------

if [ ! "${WITH_ZFS:-}" ] && [ ! "${GITLAB_CI:-}" ]; then
  add_message "Would you prefer to include ZFS?" 
  add_message "ZFS is supported in the shared_fs_disk/HA role. If you prefer to use ZFS there, please confirm below."
  show_message
  WITH_ZFS=$(get_confirmation y "Do you want to install ZFS")
fi
store_config 'WITH_ZFS' "${WITH_ZFS:-no}"

if [ "${WITH_ZFS:-no}" == "yes" ] || [ "${GITLAB_CI:-}" ]; then
  ARCH=$(uname -m)
  if [ "$ARCH" == "aarch64" ]; then
    add_message "Automated ZFS support for ARM is limited. To have ZFS support for ARM based systems, please follow the below steps:"
    add_message "- have CRB repo installed and available if applicable"
    add_message "- dnf install -y kernel-devel kernel-headers dkms libtirpc-devel"
    add_message "- dnf install -y libblkid-devel libuuid-devel zlib-devel autoconf automake libtool"
    add_message "- git clone https://github.com/openzfs/zfs.git"
    add_message "- cd zfs"
    add_message "- sh autogen.sh"
    add_message "- ./configure"
    add_message "- make -s -j8"
    add_message "- make install"
    show_message
  else
    yes y | sudo dnf -y install "https://zfsonlinux.org/epel/zfs-release-2-8$(rpm --eval "%{dist}").noarch.rpm"
    yes y | sudo dnf -y install zfs zfs-dkms
    echo "zfs" | sudo tee /etc/modules-load.d/zfs.conf >/dev/null
    sudo modprobe zfs
  fi
fi

# ---------------------- MISC TASKS -----------------------

if [ ! -f site/hosts ]; then
  add_message "Please modify the site/hosts.example and save it as site/hosts"  
else
  if ! grep -q "^$(hostname -s)\s*" site/hosts; then
    add_message "Please note the hostnames are not matching (see site/hosts)."
  fi
fi

if [ ! -f site/group_vars/all.yml ]; then
    add_message "Please modify the site/group_vars/all.yml.example and save it as site/group_vars/all.yml"
else
  if ! grep -q "^anarchy_ctrl1_hostname:\s*$(hostname -s)\s*$" site/group_vars/all.yml; then
    add_message "Please note the hostnames are not matching (see site/group_vars/all.yml)."
  fi
fi

add_message "Please configure the network before starting Ansible"

# mark prepare done (in /etc → sudo)
sudo touch /etc/anarchy/prepare.done
show_message
