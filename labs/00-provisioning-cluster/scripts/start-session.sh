#!/bin/bash
# ==============================================================================
# Rituel du matin : Démarrage des instances du cluster après arrêt de session
# À exécuter depuis votre machine locale disposant des identifiants AWS Academy
# ==============================================================================
set -euo pipefail

CLUSTER_NAME="${1:-k8s-formation}"

echo "==> Recherche des instances du cluster : ${CLUSTER_NAME}..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=Kubernetes-Administration" "Name=instance-state-name,Values=stopped,stopping" \
  --query "Reservations[].Instances[].InstanceId" --output text)

if [ -z "${INSTANCE_IDS}" ]; then
  echo "Aucune instance arrêtée trouvée pour le projet Kubernetes-Administration."
  echo "Vérifiez vos filtres ou si les instances sont déjà démarrées."
else
  echo "==> Démarrage des instances : ${INSTANCE_IDS}"
  aws ec2 start-instances --instance-ids ${INSTANCE_IDS} >/dev/null
  echo "Attente de l'état 'running'..."
  aws ec2 wait instance-running --instance-ids ${INSTANCE_IDS}
fi

echo ""
echo "==> Récapitulatif des instances actives et nouvelles adresses IP :"
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=Kubernetes-Administration" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,InstanceId,PrivateIpAddress,PublicIpAddress]" \
  --output table

CONTROL_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=k8s-control" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[0].PublicIpAddress" --output text)

echo ""
echo "------------------------------------------------------------------"
echo "Connexion SSH au Control Plane :"
echo "ssh -i labsuser.pem ubuntu@${CONTROL_IP}"
echo ""
echo "Accès Ingress NodePort HTTP :"
echo "http://${CONTROL_IP}:30080"
echo "------------------------------------------------------------------"
