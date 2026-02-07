# RHEL 10 Bootc Deployment: Image Mode to Proxmox

![Ansible](https://img.shields.io/badge/Ansible-2.16+-red.svg)
![RHEL](https://img.shields.io/badge/RHEL-10-brightgreen.svg)
![Podman](https://img.shields.io/badge/Podman-5.6+-purple.svg)

This project automates the transition from a **RHEL 10 ContainerFile** to a **bootable Virtual Machine** on Proxmox VE. It solves the "User-to-Root" storage gap required for `bootc-image-builder` and orchestrates the Proxmox CLI for disk injection.

## Image Mode Explained
[Image Mode Docs](https://developers.redhat.com/products/rhel-image-mode)

## 📋 Prerequisites
- **RHEL 9 or 10 Workstation** with Podman and Ansible installed.
- **Proxmox VE 8.x** reachable via SSH with root keys.
- **Quay.io Account** (or a private registry) with a repository named `rhel10-bootc`.
- **Red Hat Subscription** to access `registry.redhat.io`.

## 🧩 Architecture Flow
1. **Build:** `podman` builds a RHEL 10 OCI image from `ContainerFile`.
2. **Registry:** Image is pushed to Quay.io (the "Source of Truth").
3. **Convert:** `bootc-image-builder` pulls the image into Root storage and converts it to a binary QCOW2.
4. **Orchestrate:** Ansible SCPs the disk to Proxmox and defines the VM via the `qm` CLI.

## 🔄 Day 2: Seamless Updates
The beauty of Image Mode is that you never run `dnf update` on the VM. 
To update your fleet:
1. Update the `ContainerFile` (e.g., a new security patch).
2. Re-run the `build` tag of the playbook.
3. On the running VM, simply execute:
   ```bash
   bootc upgrade

The VM will pull the new layers from Quay, swap the underlying OS, and reboot into the new version.

## ✅ Post-Deployment Verification
Once logged into the VM, run these commands to confirm it is a true Image Mode system:
- `bootc status`: Shows the running image hash and the registry it came from.
- `cat /etc/image-build-info`: Verify the Git Commit hash baked in during the build.
- `systemctl status httpd`: Confirm the web server started automatically.
- `ls -l /usr/bin/`: Verify the filesystem is read-only (immutable).

## 🛠️ 1. Project Initialization
Set your local environment identity and protect your secrets from accidental exposure.

```bash
# Set Git Identity
git config --global user.name "User Name"
git config --global user.email "UserName@example.com"
git config --global init.defaultBranch main

# Initialize Repository
git init

# Create .gitignore to prevent pushing secrets and large binaries
cat <<EOF > .gitignore
# Ansible Secrets
*.vault
.ansible_vault
vars/secrets.yml.unencrypted
~/.ansible_vault_pass

# Large Build Artifacts
output/
*.qcow2
*.iso

# Python/System
__pycache__/
myenv/
.venv/
.DS_Store
EOF
```
## 🔐 2. Ansible Vault & Secrets Setup
We use Ansible Vault to store registry tokens and subscription credentials securely.Create the secrets file:Bashansible-vault create vars/secrets.yml
Populate with these variables (inside the vault):
```YAML 
vault_quay_token: "your_quay_app_token"
vault_rh_username: "your_rh_portal_user"
vault_rh_password: "your_rh_portal_password"
```
Automate the password (Optional):
```Bash
echo "your_vault_password" > ~/.ansible_vault_pass
```
## 🏗️ 3. ContainerFile Structure
The ContainerFile bakes the Git Hash and build date into the image for traceability.
```Dockerfile
FROM registry.redhat.io/rhel10/rhel-bootc:latest

# Build Metadata Argument
ARG GIT_COMMIT=unknown

# Install Packages
RUN dnf -y install httpd virtio-win qemu-guest-agent \
 greenboot greenboot-default-health-checks \
 && dnf clean all

# Bake Metadata into the image
RUN echo "Build Date: $(date)" > /etc/image-build-info && \
    echo "Git Commit: $GIT_COMMIT" >> /etc/image-build-info

# Enable Apache and set Demo Password
RUN systemctl enable httpd
RUN echo "root:RedHat1234" | chpasswd
```

## 📋 4. Execution Strategy
The playbook is modularized using Tags to allow for granular troubleshooting and faster demos. 
|Section|Tag|Purpose|
| ---   |---|---    |
|Section 1|build|"User-space login, build, and push to Quay."|
|Section 2|sync|Moves images from user storage to Root storage for the builder.|
|Section 3|convert|Runs bootc-image-builder to generate the QCOW2.|
|Section 4|deploy|SCP to Proxmox and VM orchestration via qm CLI.|


## 🚀 5. Running the Pipeline
Full Automation Run:
```Bash
ansible-playbook -i inventory.ini rhel_image_mode_deploy.yml --ask-vault-pass --ask-become-pass
```
Quick Re-Deploy (Proxmox Only):
```Bash
ansible-playbook -i inventory.ini rhel_image_mode_deploy.yml --tags deploy
```
Sync & Convert (Skip the build phase):
```Bash
ansible-playbook -i inventory.ini rhel_image_mode_deploy.yml --tags sync,convert --ask-become-pass
```
## 🏁 6. Git Workflow
```bash
git add .
git commit -m "Initial commit: End-to-end RHEL 10 Bootc to Proxmox pipeline"
git remote add origin <your-repo-url>
git push -u origin main
```
