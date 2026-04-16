#!/bin/bash
# Script pour démarrer K3s avec profil performance
# Usage: sudo ./k3s-start.sh

echo "🚀 Démarrage de K3s..."
echo "======================"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Vérifier si K3s est déjà actif
if systemctl is-active --quiet k3s; then
    echo "✅ K3s est déjà actif"
    kubectl get nodes 2>/dev/null
    exit 0
fi

# 1. Passer profil ventilateurs en mode PERFORMANCE
echo "⚡ Passage en mode ventilateurs performance..."
if command -v asusctl &> /dev/null; then
    asusctl profile set performance
    echo "✅ Profil ASUS: Performance (refroidissement optimal)"
else
    echo "⚠️  asusctl non disponible, ventilateurs en mode auto"
fi
echo ""

# 2. Démarrer K3s
echo "🔄 Démarrage du service K3s..."
systemctl start k3s

# Attendre que K3s soit prêt
echo "⏳ Attente du démarrage (peut prendre 30-60s)..."
sleep 10

# Attendre que l'API soit disponible
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if kubectl get nodes &>/dev/null; then
        echo "✅ API Kubernetes disponible"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "   Attente... ${ELAPSED}s/${TIMEOUT}s"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "⚠️  Timeout: API Kubernetes non disponible après ${TIMEOUT}s"
    echo "   K3s démarre toujours en arrière-plan"
fi

# Afficher état
echo ""
echo "📊 État du cluster:"
kubectl get nodes 2>/dev/null || echo "   En cours de démarrage..."
echo ""
echo "📦 Pods en démarrage:"
kubectl get pods -A --no-headers 2>/dev/null | wc -l || echo "   En cours..."

echo ""
echo "✅ K3s démarré"
echo "   Note: Les pods peuvent prendre 2-5 minutes pour être tous Running"
echo ""
echo "🌡️  Température actuelle:"
sensors 2>/dev/null | grep -E 'Tctl|cpu_fan' || echo "   (sensors non disponible)"

logger -t k3s-night-mode "K3s started - performance mode active"
