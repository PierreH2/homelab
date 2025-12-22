#!/bin/bash
set -e

echo "📦 Récupération des namespaces..."
namespaces=($(kubectl get ns -o jsonpath='{.items[*].metadata.name}'))

PS3="👉 Choisis un namespace : "
select NAMESPACE in "${namespaces[@]}"; do
  [[ -n "$NAMESPACE" ]] && break || echo "❌ Choix invalide"
done

echo
echo "📂 Namespace sélectionné : $NAMESPACE"
echo

echo "📦 Récupération des services dans le namespace $NAMESPACE..."
services=($(kubectl get svc -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'))

if [[ ${#services[@]} -eq 0 ]]; then
  echo "❌ Aucun service trouvé dans ce namespace"
  exit 1
fi

PS3="👉 Choisis un service : "
select SERVICE in "${services[@]}"; do
  [[ -n "$SERVICE" ]] && break || echo "❌ Choix invalide"
done

echo
echo "🔧 Service sélectionné : $SERVICE"
echo

echo "📡 Ports exposés par le service :"
kubectl get svc "$SERVICE" -n "$NAMESPACE" \
  -o jsonpath='{range .spec.ports[*]}- {.name}: {.port}{"\n"}{end}'

echo
read -p "🔌 Port SERVICE (ex: 443) : " SRC_PORT
read -p "🖥️  Port LOCAL : " DST_PORT

if ! [[ "$SRC_PORT" =~ ^[0-9]+$ && "$DST_PORT" =~ ^[0-9]+$ ]]; then
  echo "❌ Les ports doivent être numériques"
  exit 1
fi

echo
echo "🚀 Port-forward : https://localhost:$DST_PORT -> svc/$SERVICE:$SRC_PORT"
echo "⏹️  Ctrl+C pour arrêter"
echo

kubectl -n "$NAMESPACE" port-forward svc/"$SERVICE" "$DST_PORT:$SRC_PORT"
