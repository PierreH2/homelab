#!/bin/bash
set -e

APPS_DIR="/home/pierre/homelab/homelab/applications"

if [ ! -d "$APPS_DIR" ]; then
  echo "❌ Le dossier $APPS_DIR n'existe pas."
  exit 1
fi

echo "📂 Manifests disponibles dans $APPS_DIR :"
echo

# Lister tous les fichiers .yaml / .yml, même dans sous-dossiers
mapfile -t FILES < <(find "$APPS_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \))

if [ ${#FILES[@]} -eq 0 ]; then
  echo "❌ Aucun fichier YAML trouvé dans $APPS_DIR."
  exit 1
fi

# Affiche un menu numéroté
i=1
for f in "${FILES[@]}"; do
  echo "  $i) $f"
  ((i++))
done

echo
read -p "👉 Choisir le numéro du manifest à appliquer : " choice

# Vérif choix valide
if ! [[ "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#FILES[@]})); then
  echo "❌ Choix invalide."
  exit 1
fi

FILE="${FILES[$((choice-1))]}"

echo
echo "🚀 Application du manifest : $FILE"
kubectl apply -f "$FILE"

echo
echo "✅ Manifest appliqué avec succès."
