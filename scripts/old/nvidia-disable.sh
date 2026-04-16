#!/bin/bash
# Script pour RE-DÉSACTIVER NVIDIA (rollback)
# Utiliser en cas de problème après nvidia-enable.sh
# Date: 2026-04-09

set -e

echo "🚫 DÉSACTIVATION NVIDIA (ROLLBACK)"
echo "===================================="
echo ""
echo "Ce script restaure la configuration stable (NVIDIA blacklisté)"
echo ""

read -p "Continuer ? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Annulé"
    exit 0
fi

echo ""
echo "🔧 1. Recréation blacklist GRUB..."
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet module_blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm"/' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
echo "   ✅ GRUB blacklist restauré"

echo ""
echo "🔧 2. Recréation blacklist modprobe..."
sudo tee /etc/modprobe.d/blacklist-nvidia.conf > /dev/null << 'EOF'
# Désactivation du GPU NVIDIA pour éviter les freezes système
# Le GPU AMD intégré (amdgpu) gère l'affichage principal
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
EOF
echo "   ✅ modprobe blacklist restauré"

echo ""
echo "✅ NVIDIA RE-BLACKLISTÉ (nécessite reboot)"
echo ""
echo "🔄 REDÉMARRER:"
echo "   sudo reboot"
