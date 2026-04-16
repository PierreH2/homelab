#!/bin/bash
# Installation K3s Night Mode (Stop/Start automatique)
# Date: 2026-04-07

set -e

# Détecter le vrai utilisateur (même avec sudo)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
SCRIPT_DIR="$REAL_HOME/scripts/temp-fix"

echo "🌙 Installation K3s Night Mode"
echo "================================"
echo "Configuration:"
echo "- Stop K3s: 23h00 (tous les jours)"
echo "- Start K3s: 12h00 (tous les jours)"
echo ""
echo "Bénéfices:"
echo "- Charge CPU réduite de ~90% la nuit"
echo "- Température -10 à -15°C"
echo "- Ventilateurs ~3000-4000 RPM (au lieu de 6000+)"
echo "- PC reste accessible (SSH fonctionne)"
echo ""

read -p "Continuer l'installation ? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation annulée"
    exit 0
fi

echo ""
echo "1️⃣  Copie des scripts..."
sudo cp "$SCRIPT_DIR/k3s-stop.sh" /usr/local/bin/
sudo cp "$SCRIPT_DIR/k3s-start.sh" /usr/local/bin/
sudo chmod +x /usr/local/bin/k3s-stop.sh
sudo chmod +x /usr/local/bin/k3s-start.sh
echo "   ✅ Scripts copiés dans /usr/local/bin/"

echo ""
echo "2️⃣  Installation des services systemd..."
sudo cp "$SCRIPT_DIR/systemd/k3s-stop-night.service" /etc/systemd/system/
sudo cp "$SCRIPT_DIR/systemd/k3s-stop-night.timer" /etc/systemd/system/
sudo cp "$SCRIPT_DIR/systemd/k3s-start-day.service" /etc/systemd/system/
sudo cp "$SCRIPT_DIR/systemd/k3s-start-day.timer" /etc/systemd/system/
echo "   ✅ Services installés"

echo ""
echo "3️⃣  Rechargement systemd..."
sudo systemctl daemon-reload
echo "   ✅ Systemd rechargé"

echo ""
echo "4️⃣  Activation des timers..."
sudo systemctl enable k3s-stop-night.timer
sudo systemctl enable k3s-start-day.timer
sudo systemctl start k3s-stop-night.timer
sudo systemctl start k3s-start-day.timer
echo "   ✅ Timers activés"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ INSTALLATION TERMINÉE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "📊 Vérification:"
sudo systemctl list-timers --no-pager | grep k3s

echo ""
echo "📅 Prochaines exécutions:"
echo "- Stop K3s:  Ce soir à 23h00"
echo "- Start K3s: Demain à 12h00"
echo ""

echo "🧪 TEST IMMÉDIAT (optionnel):"
echo "Pour tester maintenant:"
echo "  sudo /usr/local/bin/k3s-stop.sh   # Arrêter K3s"
echo "  sleep 10"
echo "  sudo /usr/local/bin/k3s-start.sh  # Redémarrer K3s"
echo ""

echo "🔍 Surveiller les températures après 23h:"
echo "  watch -n 5 'sensors | grep -E \"Tctl|cpu_fan\"'"
echo ""

echo "❌ Désactiver si besoin:"
echo "  sudo systemctl disable --now k3s-stop-night.timer"
echo "  sudo systemctl disable --now k3s-start-day.timer"
echo ""
