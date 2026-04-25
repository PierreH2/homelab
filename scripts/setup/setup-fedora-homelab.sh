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
echo "[0/7] Disabling GUI permanently..."

sudo systemctl set-default multi-user.target
echo "✓ GUI disabled (will take effect on next boot)"

# ============================================================================
# 1. INSTALL PACKAGES
# ============================================================================
echo ""
echo "[1/7] Installing packages..."

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

# ASUS-specific tools (asusctl only - NOT supergfxctl)
# Note: supergfxctl causes ACPI crashes on ASUS firmware (bug with D-state transitions)
#       See: https://github.com/PierreH2/homelab for fix scripts
echo "Installing ASUS control tools..."
if ! dnf copr list | grep -q "lukenukem/asus-linux"; then
    sudo dnf copr enable -y lukenukem/asus-linux
fi
sudo dnf install -y asusctl
# asusd starts automatically via D-Bus (no manual start needed)

# Disable all LED lighting
echo "Disabling keyboard/system LED lighting..."
sleep 2  # Wait for asusd to be ready
asusctl led-mode static -c 000000 2>/dev/null || asusctl -k off 2>/dev/null || true
# Disable LED brightness completely
asusctl -k 0 2>/dev/null || true

echo "✓ Packages installed"

# ============================================================================
# 2. CREATE DIRECTORY STRUCTURE
# ============================================================================
echo ""
echo "[2/7] Creating directory structure..."

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
# 3. CONFIGURE SELINUX (for K3s) & SYSTEM SETTINGS
# ============================================================================
echo ""
echo "[3/7] Configuring SELinux and system settings..."

# Set SELinux to permissive mode for K3s
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# Disable lid suspend (prevent sleep when closing laptop lid)
echo "Configuring lid behavior (no suspend on lid close)..."
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/00-homelab-lid.conf > /dev/null <<EOF
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
sudo systemctl restart systemd-logind

echo "✓ SELinux and system settings configured"

# ============================================================================
# 4. CONFIGURE FIREWALLD FOR K3S
# ============================================================================
echo ""
echo "[4/7] Configuring firewalld for K3s..."

# Open K3s ports
echo "Opening K3s ports..."
sudo firewall-cmd --permanent --add-port=6443/tcp     # API server
sudo firewall-cmd --permanent --add-port=10250/tcp    # Kubelet
sudo firewall-cmd --permanent --add-port=8472/udp     # Flannel VXLAN
sudo firewall-cmd --permanent --add-port=51820/udp    # Flannel Wireguard
sudo firewall-cmd --permanent --add-port=51821/udp    # Flannel Wireguard

# Enable masquerade for NAT
echo "Enabling masquerade..."
sudo firewall-cmd --permanent --add-masquerade

# Add CNI interfaces to trusted zone
echo "Configuring trusted zone for CNI..."
sudo firewall-cmd --permanent --zone=trusted --add-interface=cni0 2>/dev/null || true
sudo firewall-cmd --permanent --zone=trusted --add-interface=flannel.1 2>/dev/null || true

# Add Pod and Service CIDR to trusted zone
echo "Adding Pod and Service CIDR to trusted zone..."
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16  # Pod CIDR
sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16  # Service CIDR

# Reload firewalld
echo "Reloading firewalld..."
sudo firewall-cmd --reload

echo "✓ Firewalld configured for K3s"

# ============================================================================
# 5. CONFIGURE KERNEL PARAMETERS FOR K3S
# ============================================================================
echo ""
echo "[5/7] Configuring kernel parameters for K3s..."

# Create sysctl configuration for K3s
sudo tee /etc/sysctl.d/k3s.conf > /dev/null <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Load br_netfilter module
sudo modprobe br_netfilter

# Make br_netfilter load on boot
echo "br_netfilter" | sudo tee /etc/modules-load.d/k3s.conf

# Apply sysctl settings
sudo sysctl --system

echo "✓ Kernel parameters configured"

# ============================================================================
# 6. DEPLOY K3S
# ============================================================================
echo ""
echo "[6/7] Deploying K3s..."

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
# 7. VERIFY K3S NETWORKING CONFIGURATION
# ============================================================================
echo ""
echo "[7/7] Verifying K3s networking configuration..."

# Wait for CNI interfaces to be created
sleep 5

# Add CNI interfaces to trusted zone (may have been created after K3s install)
sudo firewall-cmd --permanent --zone=trusted --add-interface=cni0 2>/dev/null || true
sudo firewall-cmd --permanent --zone=trusted --add-interface=flannel.1 2>/dev/null || true
sudo firewall-cmd --reload

echo "Firewall configuration:"
sudo firewall-cmd --zone=trusted --list-all

echo "✓ K3s networking verified"

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "==================================="
echo "✓ Setup Complete!"
echo "==================================="
echo ""
echo "Configuration applied:"
echo "✓ Packages installed (Docker, kubectl, Helm, Terraform, Ansible)"
echo "✓ Directory structure created (/data/nas)"
echo "✓ SELinux set to permissive mode"
echo "✓ Lid suspend disabled"
echo "✓ Firewalld configured for K3s (ports, masquerade, trusted zones)"
echo "✓ Kernel parameters configured (IP forwarding, bridge netfilter)"
echo "✓ K3s deployed and configured"
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
echo "LED: Disabled (to re-enable: asusctl -k 3)"
echo "Lid: Suspend disabled (lid close won't sleep the system)"
echo "Firewalld: Configured for K3s with masquerade and trusted zones"
echo ""
