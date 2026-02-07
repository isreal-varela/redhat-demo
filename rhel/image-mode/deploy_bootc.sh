#!/bin/bash

# --- Configuration Variables ---
CONTAINERFILE="ContainerFile"
QUAY_REPO="isrealvarela"
IMAGE_NAME="rhel10-bootc"
TAG="latest"
FULL_IMAGE_PATH="quay.io/${QUAY_REPO}/${IMAGE_NAME}:${TAG}"
OUTPUT_DIR="./output"
BUILDER_IMAGE="registry.redhat.io/rhel10/bootc-image-builder:latest"

# --- Proxmox Variables ---
PM_USER="root"
PM_HOST="192.168.100.11" # <-- CHANGE THIS
PM_VMID="400"
PM_STORAGE="local-lvm"
PM_IMG_PATH="/var/lib/vz/template/qcow/disk.qcow2"

echo "🔍 Running Pre-flight Registry Checks..."

check_login() {
    podman login --get-login "$1" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ Error: Not logged into $1. Run: podman login $1"
        exit 1
    fi
}

check_login "quay.io"
check_login "registry.redhat.io"

# 1. Build & Push as Current User
echo "📦 Building container as $USER..."
podman build -f "$CONTAINERFILE" -t "$FULL_IMAGE_PATH" . || exit 1

echo "📤 Pushing to Quay.io..."
podman push "$FULL_IMAGE_PATH" || exit 1

# 2. Cleanup & Sync Root's Storage
echo "🧹 Cleaning up root's old images..."
# We use || true so the script doesn't exit if there are no images to remove
sudo podman image rm $(sudo podman image ls -q) --force 2>/dev/null || true

echo "📥 Warming up root storage for conversion..."
# Pulling these as root ensures the builder doesn't have to pull them internally
sudo podman pull "$BUILDER_IMAGE"
sudo podman pull "$FULL_IMAGE_PATH"

# 3. Image Mode Conversion
echo "💿 Converting container to QCOW2 (as root)..."
mkdir -p $OUTPUT_DIR
sudo podman run \
    --rm -it --privileged \
    -v $(pwd)/$OUTPUT_DIR:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v ${XDG_RUNTIME_DIR}/containers/auth.json:/run/containers/0/auth.json:Z \
    "$BUILDER_IMAGE" \
    --type qcow2 \
    "$FULL_IMAGE_PATH"

echo "✅ Local Build & Conversion Complete."

# 4. Automated Proxmox Deployment
echo "📡 Deploying to Proxmox at $PM_HOST..."

echo "📤 Uploading image..."
scp "$OUTPUT_DIR/qcow2/disk.qcow2" "$PM_USER@$PM_HOST:$PM_IMG_PATH" || exit 1

echo "🛠️ Reconfiguring VM $PM_VMID..."
ssh "$PM_USER@$PM_HOST" << EOF
    qm stop $PM_VMID 2>/dev/null
    qm destroy $PM_VMID 2>/dev/null
    qm create $PM_VMID --name $IMAGE_NAME --memory 4096 --cores 2 --cpu host --net0 virtio,bridge=vmbr0 --agent 1
    qm importdisk $PM_VMID $PM_IMG_PATH $PM_STORAGE
    qm set $PM_VMID --scsihw virtio-scsi-pci --scsi0 $PM_STORAGE:vm-$PM_VMID-disk-0
    qm set $PM_VMID --boot "order=scsi0"
    qm start $PM_VMID
EOF

echo "------------------------------------------------------------"
echo "🎉 Deployment Successful!"
echo "VM $PM_VMID is booting on Proxmox."
echo "------------------------------------------------------------":
