#!/bin/bash
# Script pour arrêter K3s proprement et tuer tous les pods
# Usage: sudo ./k3s-stop.sh

echo "🛑 Arrêt complet K3s + Pods..."
echo "=============================="
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Vérifier si K3s tourne
if ! systemctl is-active --quiet k3s; then
    echo "⚠️  K3s n'est pas actif"
    # Killer quand même les processus zombies si présents
    if [ -x /usr/local/bin/k3s-killall.sh ]; then
        echo "🧹 Nettoyage processus zombies..."
        /usr/local/bin/k3s-killall.sh 2>/dev/null
    fi
    exit 0
fi

# Pods actifs avant arrêt
echo "📊 Pods actifs avant arrêt:"
kubectl get pods -A --no-headers 2>/dev/null | wc -l
echo ""

# 1. Arrêter le service K3s
echo "🔄 Arrêt du service K3s..."
systemctl stop k3s
sleep 3

# 2. KILLER tous les processus K3s/containerd/pods (crucial!)
echo "💀 Terminaison de TOUS les processus K3s et pods..."
if [ -x /usr/local/bin/k3s-killall.sh ]; then
    /usr/local/bin/k3s-killall.sh
    echo "✅ Tous les processus K3s/containerd/pods terminés"
else
    echo "⚠️  k3s-killall.sh non trouvé, arrêt basique seulement"
fi

# CRITIQUE: Attendre que le CPU termine le nettoyage AVANT de réduire ventilation
echo ""
echo "⏳ Attente fin des tâches CPU (45s)..."
echo "   Le CPU doit finir de nettoyer containerd/cgroups/network"
echo "   Ventilateurs restent en mode Performance pendant ce temps"
sleep 45

# 3. Passer profil ventilateurs en mode QUIET (silencieux)
echo ""
echo "🔇 Passage en mode ventilateurs silencieux..."
if command -v asusctl &> /dev/null; then
    asusctl profile set quiet
    echo "✅ Profil ASUS: Quiet (CPU a terminé ses tâches)"
else
    echo "⚠️  asusctl non disponible, ventilateurs en mode auto"
fi

# Vérifications finales
echo ""
echo "✅ Arrêt complet terminé"
echo ""
echo "📉 Résultats attendus:"
echo "   - Charge CPU: ~1-2% (au lieu de 15-30%)"
echo "   - Température: -15 à -20°C"
echo "   - Ventilateurs: ~2500-3500 RPM mode Quiet"
echo ""
echo "🌡️  Température actuelle:"
sensors 2>/dev/null | grep -E 'Tctl|cpu_fan' || echo "   (sensors non disponible)"

# Relancer les timers night mode (k3s-killall.sh les stoppe via le glob k3s*.service)
echo "🕐 Relance des timers night mode..."
systemctl start k3s-start-day.timer k3s-stop-night.timer 2>/dev/null || true
echo "   ✅ Timers relancés (prochain déclenchement: 12h00 et 23h00)"

logger -t k3s-night-mode "K3s stopped completely (killall + quiet profile)"
