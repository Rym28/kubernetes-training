#!/bin/bash
# ==============================================================================
# Récupère le kubeconfig du cluster sur votre poste (Linux / macOS / Git Bash)
#   1. copie ~/.kube/config de k8s-control dans terraform/kubeconfig.yaml (scp) ;
#   2. remplace l'adresse privée de l'API Server par l'Elastic IP de k8s-control.
# Le certificat de l'API Server contient l'Elastic IP (kubeadm init
# --apiserver-cert-extra-sans) : la vérification TLS reste active.
#
# Usage : ../scripts/get-kubeconfig.sh [IP_PUBLIQUE_CONTROL]
#         (sans argument, l'IP est lue dans « terraform output »)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/../terraform" && pwd)"
KEY="${TF_DIR}/labsuser.pem"
OUT="${TF_DIR}/kubeconfig.yaml"

CONTROL_IP="${1:-}"
if [ -z "${CONTROL_IP}" ]; then
  CONTROL_IP="$(terraform -chdir="${TF_DIR}" output -raw control_plane_public_ip)"
fi

if [ ! -f "${KEY}" ]; then
  echo "Clé introuvable : ${KEY} (voir l'étape 4 de l'Atelier 01)." >&2
  exit 1
fi

echo "==> [1/3] Copie du kubeconfig depuis k8s-control (${CONTROL_IP})"
scp -q -i "${KEY}" -o StrictHostKeyChecking=accept-new \
  "ubuntu@${CONTROL_IP}:.kube/config" "${OUT}.tmp"

echo "==> [2/3] Remplacement de l'adresse de l'API Server par ${CONTROL_IP}"
sed -E "s#(server: https://)[^:/]+(:6443)#\1${CONTROL_IP}\2#" "${OUT}.tmp" >"${OUT}"
rm -f "${OUT}.tmp"
chmod 600 "${OUT}"

echo "==> [3/3] Test de la connexion"
KUBECONFIG="${OUT}" kubectl get nodes

echo ""
echo "Kubeconfig enregistré : ${OUT}"
echo "Dans chaque nouveau terminal, placé à la racine du dépôt :"
echo "  export KUBECONFIG=\$PWD/labs/01-Installation-Cluster/terraform/kubeconfig.yaml"
