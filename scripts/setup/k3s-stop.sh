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

# 2. KILLER tous les processus K3s/containerd/pods EN ARRIERE-PLAN (crucial!)
# Le processus est détaché pour survivre si systemd tue ce script
echo "💀 Terminaison de TOUS les processus K3s et pods (processus détaché)..."
(
    # Sous-shell détaché qui survit à la mort du script parent
    if [ -x /usr/local/bin/k3s-killall.sh ]; then
        /usr/local/bin/k3s-killall.sh 2>/dev/null
        
        # CRITIQUE: Attendre que le CPU termine le nettoyage AVANT de réduire ventilation
        sleep 45
        
        # Passer profil ventilateurs en mode QUIET (silencieux)
        if command -v asusctl &> /dev/null; then
            asusctl profile set quiet 2>/dev/null
            logger -t k3s-night-mode "Ventilateurs en mode Quiet après killall + sleep 45s"
        fi
        
        # Relancer les timers (au cas où killall les aurait stoppés)
        systemctl start k3s-start-day.timer k3s-stop-night.timer 2>/dev/null || true
        
        logger -t k3s-night-mode "K3s killall + quiet mode terminé (détaché)"
    fi
) &

# Attendre 5s que le killall démarre
sleep 5
echo "✅ Processus de nettoyage lancé en arrière-plan"
echo "   (killall → sleep 45s → mode quiet → restart timers)"

# Vérifications finales
echo ""
echo "✅ Arrêt complet terminé"
echo ""
echo "📉 Résultats attendus (dans ~50s):"
echo "   - Charge CPU: ~1-2% (au lieu de 15-30%)"
echo "   - Température: -15 à -20°C"
echo "   - Ventilateurs: ~2500-3500 RPM mode Quiet"
echo ""
echo "🌡️  Température actuelle:"
sensors 2>/dev/null | grep -E 'Tctl|cpu_fan' || echo "   (sensors non disponible)"

logger -t k3s-night-mode "K3s stop initiated (background cleanup running)"
