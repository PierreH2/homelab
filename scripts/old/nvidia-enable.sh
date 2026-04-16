#!/bin/bash
# Script pour réactiver NVIDIA RTX 3060 (dGPU)
# Objectif: Soulager le CPU en déchargeant le GPU sur la RTX 3060 dédiée
# Date: 2026-04-09

set -e

echo "🎮 RÉACTIVATION NVIDIA RTX 3060 (dGPU)"
echo "======================================="
echo ""
echo "📋 Objectif:"
echo "   - Activer NVIDIA RTX 3060 pour GPU workloads"
echo "   - Soulager AMD iGPU (intégré au CPU)"
echo "   - Réduire charge thermique CPU"
echo ""
echo "⚠️  IMPORTANT:"
echo "   - supergfxd restera DÉSACTIVÉ (c'était lui qui causait les crashes)"
echo "   - Si problème, rollback possible avec nvidia-disable.sh"
echo ""

read -p "Continuer ? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Annulé"
    exit 0
fi

echo ""
echo "📦 1. Sauvegarde config actuelle..."
sudo cp /etc/default/grub /etc/default/grub.backup-$(date +%Y%m%d)
sudo cp /etc/modprobe.d/blacklist-nvidia.conf /etc/modprobe.d/blacklist-nvidia.conf.backup 2>/dev/null || true
echo "   ✅ Backup créé"

echo ""
echo "🔧 2. Retrait blacklist GRUB..."
sudo sed -i 's/module_blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm//' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
echo "   ✅ GRUB mis à jour"

echo ""
echo "🔧 3. Retrait blacklist modprobe..."
sudo rm -f /etc/modprobe.d/blacklist-nvidia.conf
echo "   ✅ Blacklist retiré"

echo ""
echo "🔧 4. Vérification supergfxd RESTE désactivé..."
if systemctl is-enabled --quiet supergfxd 2>/dev/null; then
    echo "   ⚠️  supergfxd est enabled, désactivation..."
    sudo systemctl disable supergfxd
fi
sudo systemctl stop supergfxd 2>/dev/null || true
echo "   ✅ supergfxd désactivé (c'est voulu)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ NVIDIA RÉACTIVÉ (nécessite reboot)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Après reboot:"
echo "   - NVIDIA RTX 3060: ACTIF"
echo "   - AMD iGPU: ACTIF (affichage)"
echo "   - supergfxd: DÉSACTIVÉ (sécurité)"
echo ""
echo "🔍 Vérification après reboot:"
echo "   lsmod | grep nvidia"
echo "   nvidia-smi"
echo ""
echo "🆘 Si problème (crashes):"
echo "   sudo /home/pierre/homelab/scripts/nvidia-disable.sh"
echo ""
echo "🔄 REDÉMARRER MAINTENANT:"
echo "   sudo reboot"
