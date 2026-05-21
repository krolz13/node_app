#!/bin/bash
# provision_proxmox.sh - Provision Debian 12 VMs on Proxmox VE for GitLab DevOps Homelab
# To be executed from Andrii's local machine.

set -euo pipefail

# Configuration
PVE_IP="192.168.8.171"
PVE_USER="root"
SSH_KEY_PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGStgiyhwxDj8qky+nvkdmwp95q0YIY+xqRYWTDNTyvP andrii.toll88@gmail.com"

echo "=========================================================="
echo " Starting Proxmox VM Provisioning on $PVE_IP"
echo "=========================================================="

# 1. Generate Cloud-Init User Data YAMLs
echo "Generating Cloud-Init user-data configurations..."
USER_DATA_200=$(cat <<EOF
#cloud-config
hostname: gitlab-debian12
manage_etc_hosts: true
user: debian
ssh_authorized_keys:
  - $SSH_KEY_PUB
chpasswd:
  list: |
    debian:gitlabdevops
  expire: False
package_update: true
package_upgrade: false
packages:
  - qemu-guest-agent
  - curl
  - git
  - apt-transport-https
  - ca-certificates
  - gnupg
runcmd:
  - systemctl enable --now qemu-guest-agent
EOF
)

USER_DATA_201=$(cat <<EOF
#cloud-config
hostname: prod-debian12
manage_etc_hosts: true
user: debian
ssh_authorized_keys:
  - $SSH_KEY_PUB
chpasswd:
  list: |
    debian:proddevops
  expire: False
package_update: true
package_upgrade: false
packages:
  - qemu-guest-agent
  - curl
  - git
  - apt-transport-https
  - ca-certificates
  - gnupg
runcmd:
  - systemctl enable --now qemu-guest-agent
EOF
)

# 2. Upload Cloud-Init configurations to Proxmox snippets storage
echo "Uploading Cloud-Init snippets to Proxmox host..."
ssh -T "$PVE_USER@$PVE_IP" <<EOF
mkdir -p /var/lib/vz/snippets
cat <<'INNEREOF' > /var/lib/vz/snippets/user-data-200.yaml
$USER_DATA_200
INNEREOF
cat <<'INNEREOF' > /var/lib/vz/snippets/user-data-201.yaml
$USER_DATA_201
INNEREOF
EOF

# 3. Download Debian 12 Cloud-Init Image on Proxmox Host if not present
echo "Ensuring Debian 12 Cloud-Init image is downloaded on Proxmox..."
ssh -T "$PVE_USER@$PVE_IP" <<'EOF'
IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
IMAGE_PATH="/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2"

if [ ! -f "$IMAGE_PATH" ]; then
    echo "Downloading Debian 12 generic cloud image (this may take a minute)..."
    wget -q --show-progress -O "$IMAGE_PATH" "$IMAGE_URL"
    echo "Download completed!"
else
    echo "Debian 12 cloud image already exists. Skipping download."
fi
EOF

# 4. Provision VM 200 (GitLab Server) & VM 201 (Production + Runner Server)
provision_vm() {
    local VMID=$1
    local NAME=$2
    local MEM=$3
    local CORES=$4
    local DISK_SIZE=$5
    local SNIPPET=$6

    echo "--------------------------------------------------------"
    echo " Provisioning VM $VMID: $NAME"
    echo "--------------------------------------------------------"

    ssh -T "$PVE_USER@$PVE_IP" <<EOF
    # Stop VM if running
    if qm status $VMID >/dev/null 2>&1; then
        echo "VM $VMID already exists. Stopping and destroying it for a clean deployment..."
        qm stop $VMID || true
        qm destroy $VMID
    fi

    echo "Creating VM container..."
    qm create $VMID --name "$NAME" --memory $MEM --cores $CORES --net0 virtio,bridge=vmbr0 --ostype l26 --cpu host --agent enabled=1

    echo "Importing disk..."
    qm importdisk $VMID /var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2 local-lvm

    echo "Attaching SCSI disk..."
    qm set $VMID --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-$VMID-disk-0

    echo "Adding Cloud-Init drive..."
    qm set $VMID --ide2 local-lvm:cloudinit

    echo "Assigning custom user-data snippet..."
    qm set $VMID --cicustom "user=local:snippets/$SNIPPET"

    echo "Setting boot options..."
    qm set $VMID --boot order=scsi0 --bootdisk scsi0

    echo "Setting serial console..."
    qm set $VMID --serial0 socket --vga serial0

    echo "Resizing disk to $DISK_SIZE..."
    qm resize $VMID scsi0 $DISK_SIZE

    echo "Starting VM $VMID..."
    qm start $VMID
EOF
}

# Run provisioning for both VMs
# VM 200: GitLab DevOps Server (6GB RAM, 4 Cores, 50GB Disk)
provision_vm 200 "gitlab-debian12" 6144 4 "50G" "user-data-200.yaml"

# VM 201: Production + Runner Server (3GB RAM, 2 Cores, 30GB Disk)
provision_vm 201 "prod-debian12" 3072 2 "30G" "user-data-201.yaml"

echo "=========================================================="
echo " Both VMs have been provisioned and started!"
echo " Waiting for them to boot and acquire DHCP IP addresses..."
echo "=========================================================="

get_vm_ip() {
    local VMID=$1
    local NAME=$2
    local IP=""
    local RETRIES=30

    echo -n "Waiting for VM $VMID ($NAME) to report IP..."
    for ((i=1; i<=RETRIES; i++)); do
        # Try getting network interface info via QEMU Guest Agent
        IP=$(ssh -T "$PVE_USER@$PVE_IP" "qm guest network status $VMID 2>/dev/null" | grep -A 3 -E "e(nth|th|np0s)" | grep "ip-address" | grep -oE "192\.168\.[0-9]+\.[0-9]+" | head -n 1 || true)
        if [ -n "$IP" ]; then
            echo -e "\n[SUCCESS] VM $VMID ($NAME) is online! IP: $IP"
            return 0
        fi
        echo -n "."
        sleep 5
    done
    echo -e "\n[TIMEOUT] Could not retrieve IP for VM $VMID via guest agent. Please check console in Proxmox UI."
    return 1
}

# Wait for guest agents to report IPs
get_vm_ip 200 "gitlab-debian12" || true
get_vm_ip 201 "prod-debian12" || true

echo "=========================================================="
echo " Provisioning completed successfully!"
echo " Log in to your new VMs using:"
echo " ssh debian@<VM_IP>"
echo "=========================================================="
