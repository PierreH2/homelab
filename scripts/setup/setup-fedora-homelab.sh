#!/bin/bash
#
# Setup Fedora Homelab Server
# Installs packages, creates directory structure, and deploys K3s
#

set -e  # Exit on error

echo "=== Fedora Homelab Setup ==="

# ============================================================================
# 0. DISABLE GUI (PERMANENT)
# ============================================================================
echo ""
echo "[0/4] Disabling GUI permanently..."

sudo systemctl set-default multi-user.target
echo "✓ GUI disabled (will take effect on next boot)"

# ============================================================================
# 1. INSTALL PACKAGES
# ============================================================================
echo ""
echo "[1/4] Installing packages..."

sudo dnf update -y

# Essential tools
sudo dnf install -y \
    iproute iputils net-tools \
    lm_sensors htop \
    vim git curl wget tree jq \
    gcc make kernel-devel

# Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    sudo dnf install -y dnf-plugins-core
    sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker $USER
fi

# Kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
fi

# Helm
if ! command -v helm &> /dev/null; then
    echo "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Terraform
if ! command -v terraform &> /dev/null; then
    echo "Installing Terraform..."
    sudo dnf install -y dnf-plugins-core
    sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
    sudo dnf install -y terraform
fi

# Ansible
if ! command -v ansible &> /dev/null; then
    echo "Installing Ansible..."
    sudo dnf install -y ansible
fi

# ASUS-specific tools (asusctl + supergfx)
echo "Installing ASUS control tools..."
if ! dnf copr list | grep -q "lukenukem/asus-linux"; then
    sudo dnf copr enable -y lukenukem/asus-linux
fi
sudo dnf install -y asusctl supergfxctl
# asusd starts automatically via D-Bus, just start supergfxd
sudo systemctl enable --now supergfxd.service 2>/dev/null || true

echo "✓ Packages installed"

# ============================================================================
# 2. CREATE DIRECTORY STRUCTURE
# ============================================================================
echo ""
echo "[2/4] Creating directory structure..."

# Define directories
DIRS=(
    "/data/nas/private/prometheus"
    "/data/nas/private/grafana"
    "/data/nas/public/registry"
    "/data/nas/public/apache"
    "/data/nas/public/plex/media"
    "/data/nas/public/plex/config"
)

# Create directories
for dir in "${DIRS[@]}"; do
    sudo mkdir -p "$dir"
    echo "Created: $dir"
done

# Set permissions (chmod 777 for pod accessibility)
sudo chmod -R 777 /data/nas

# Set ownership to current user
sudo chown -R $USER:$USER /data/nas

echo "✓ Directory structure created"

# ============================================================================
# 3. CONFIGURE SELINUX (for K3s)
# ============================================================================
echo ""
echo "[3/4] Configuring SELinux..."

# Set SELinux to permissive mode for K3s
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

echo "✓ SELinux configured"

# ============================================================================
# 4. DEPLOY K3S
# ============================================================================
echo ""
echo "[4/4] Deploying K3s..."

if ! command -v k3s &> /dev/null; then
    echo "Installing K3s..."
    curl -sfL https://get.k3s.io | sh -
    
    # Wait for K3s to be ready
    echo "Waiting for K3s to start..."
    sudo systemctl enable k3s
    sudo systemctl start k3s
    sleep 10
fi

# Setup kubeconfig
mkdir -p $HOME/kube
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/kube/config
sudo chown $USER:$USER $HOME/kube/config
sudo chmod 600 $HOME/kube/config

# Update kubeconfig to use server IP
sed -i 's/127.0.0.1/192.168.1.100/g' $HOME/kube/config

# Set KUBECONFIG environment variable
if ! grep -q "KUBECONFIG" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Kubernetes config" >> ~/.bashrc
    echo "export KUBECONFIG=\$HOME/kube/config" >> ~/.bashrc
fi

if ! grep -q "KUBECONFIG" ~/.zshrc 2>/dev/null; then
    echo "" >> ~/.zshrc
    echo "# Kubernetes config" >> ~/.zshrc
    echo "export KUBECONFIG=\$HOME/kube/config" >> ~/.zshrc
fi

export KUBECONFIG=$HOME/kube/config

# Test kubectl
kubectl get nodes

echo "✓ K3s deployed and configured"

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "==================================="
echo "✓ Setup Complete!"
echo "==================================="
echo ""
echo "Next steps:"
echo "1. Reboot to disable GUI: sudo reboot"
echo "2. Logout and login again (to apply docker group)"
echo "3. Verify kubectl: kubectl get nodes"
echo "4. Test asusctl: asusctl profile -l"
echo "5. Deploy your apps from homelab repo"
echo ""
echo "KUBECONFIG: \$HOME/kube/config"
echo "GUI: Disabled (multi-user.target)"
echo ""
