RHEL 10 Image Mode to Proxmox Pipeline
This project automates the creation of a bootable RHEL 10 Container, converts it into a QCOW2 disk image using the bootc-image-builder, and orchestrates the deployment to a Proxmox VE cluster.

🚀 Key Features
Immutable Infrastructure: Apache is configured to serve content from /usr/share/www/html, leveraging the immutable nature of the bootc runtime.

Greenboot Integration: Includes health checks to ensure the httpd service is functional upon boot; otherwise, the system can auto-rollback.

Hybrid Execution: Handles the complex transition between User-space Podman builds and Root-space Image Conversion.

🔐 1. Setup Ansible Vault
The playbook relies on a vars/secrets.yml file. This file must be encrypted with Ansible Vault to protect your registry credentials and Red Hat Subscription details.

Create the Secrets File
Create the directory: mkdir vars

Use the vault to create the file:

Bash
ansible-vault create vars/secrets.yml
Required Variables
Paste the following into your vault file, replacing the values with your actual credentials:

YAML
# Registry Credentials
vault_quay_token: "your-quay-token-or-password"
quay_username: "isrealvarela"

# Red Hat Subscription (Required to pull the base image and builder)
vault_rh_username: "your-rh-customer-portal-username"
vault_rh_password: "your-rh-customer-portal-password"

# Proxmox (If using API, otherwise root password for SCP if keys aren't set)
pm_password: "your-proxmox-root-password"
📂 2. Project Structure
ContainerFile: Defines the RHEL 10 OS image, including the immutable web content and Greenboot checks.

rhel_image_mode_deploy.yml: The main automation engine.

inventory.ini: Maps your build machine and the Proxmox target node.

ansible.cfg: Configured for host_key_checking = False to ensure smooth demo flow.

🛠️ 3. Prerequisites
Ensure your local build machine (RHEL 9 or 10) has the following:

Podman: sudo dnf install -y podman

Ansible Core & Collections:

Bash
ansible-galaxy collection install containers.podman community.general
SSH Keys: Your local SSH key should be authorized on the Proxmox node (ssh-copy-id root@192.168.100.11).

🏃 4. Running the Pipeline
The Full Run
This builds the image, syncs it to root, converts it to a disk, and deploys it:

Bash
ansible-playbook -i inventory.ini rhel_image_mode_deploy.yml --ask-vault-pass --ask-become-pass
Iterating on Proxmox Only
If you've already built the image and just need to tweak the VM settings or re-upload the disk:

Bash
ansible-playbook -i inventory.ini rhel_image_mode_deploy.yml --tags deploy --ask-vault-pass
Conversion Only
To skip the build and just generate the QCOW2 file:

Bash
ansible-playbook -i inventory.ini rhel_image_mode_deploy.yml --tags convert --ask-become-pass
🔍 5. Post-Deployment Verification
Once the VM is up (VMID 400), verify the "Image Mode" characteristics:

Check Immutability:

Bash
ssh root@192.168.100.205 "touch /usr/bin/test_file"
# Result: touch: cannot touch '/usr/bin/test_file': Read-only file system
Verify Web Content:

Bash
curl http://192.168.100.205
# Result: <h1>Hello from RHEL Image Mode Yo</h1>
Check Greenboot Status:

Bash
ssh root@192.168.100.205 "bootc status"
