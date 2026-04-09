# Fix Crashes Thermiques Homelab

**Date**: Avril 6-9, 2026  
**Système**: Arch Linux K3s Homelab (AMD Ryzen 9 5900HX)

---

## Problème

Crashes système récurrents liés à la **température CPU élevée** (90-95°C).

---

## Solution

### 1. Activation Fan Control
- Installation **asusctl** pour débloquer les ventilateurs ASUS ROG
- Activation profil Performance avec fan curves agressives
- **Désactivation supergfxd** (causait conflits GPU)

```bash
sudo systemctl disable supergfxd
asusctl profile set performance
```

**Résultat**: Stabilité thermique restaurée, mais **ventilateurs bruyants** (6000+ RPM).

---

### 2. Automation K3s Night Mode

**Objectif**: Réduire bruit ventilateurs pendant la nuit (23h-12h).

**Solution**: Scripts d'arrêt/démarrage automatique K3s + switch profil ventilateurs.

**Scripts créés**:
- [`k3s-stop.sh`](scripts/k3s-stop.sh): Arrêt K3s à 23h + mode Quiet
- [`k3s-start.sh`](scripts/k3s-start.sh): Démarrage K3s à 12h + mode Performance
- [`install-k3s-night-mode.sh`](scripts/install-k3s-night-mode.sh): Installation timers systemd

**Timers systemd**:
```
k3s-stop-night.timer  → 23:00:00 quotidien
k3s-start-day.timer   → 12:00:00 quotidien
```

**Déploiement**:
```bash
sudo cp scripts/k3s-*.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/k3s-*.sh
./scripts/install-k3s-night-mode.sh
```

---

## Résultat Final

✅ **Système stable** sans crashes thermiques  
✅ **Silence nocturne** (23h-12h) avec K3s arrêté  
✅ **Automatisation complète** via systemd timers  

---

## Finding Technique

⚠️ **Pods zombies après `systemctl stop k3s`**

Le simple arrêt du service K3s ne termine **pas** tous les processus containerd/pods.  
Ils restent en état **zombie**, consommant CPU et mémoire.

**Solution**: Utiliser `/usr/local/bin/k3s-killall.sh` après l'arrêt du service.

```bash
systemctl stop k3s
/usr/local/bin/k3s-killall.sh  # Termine TOUS les processus containerd/pods
```

Ce script est intégré dans [`k3s-stop.sh`](scripts/k3s-stop.sh).

---

**Scripts disponibles**: [homelab/scripts/](scripts/)
