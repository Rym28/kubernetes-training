#!/bin/bash
# ==============================================================================
# Rituel du soir : Arrêt des instances du cluster pour préserver les crédits
# Les volumes EBS et la persistance du cluster restent conservés
# ==============================================================================
set -euo pipefail

echo "==> Recherche des instances actives du cluster Kubernetes-Administration..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=Kubernetes-Administration" "Name=instance-state-name,Values=running,pending" \
  --query "Reservations[].Instances[].InstanceId" --output text)

if [ -z "${INSTANCE_IDS}" ]; then
  echo "Aucune instance en cours d'exécution trouvée."
else
  echo "==> Arrêt des instances : ${INSTANCE_IDS}"
  aws ec2 stop-instances --instance-ids ${INSTANCE_IDS} >/dev/null
  echo "Attente de l'arrêt complet..."
  aws ec2 wait instance-stopped --instance-ids ${INSTANCE_IDS}
  echo "Instances arrêtées avec succès. Seul le stockage EBS est facturé (quelques centimes)."
fi
