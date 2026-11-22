#!/bin/bash
# ==============================================================================
# Installation des composants additionnels de formation
# À exécuter sur k8s-control une fois que tous les nœuds sont en état 'Ready'
# ==============================================================================
set -euo pipefail

echo "==> [1/4] Installation de Helm 3"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "==> [2/4] Configuration de l'autocomplétion kubectl et des alias utiles"
if ! grep -q "kubectl completion bash" ~/.bashrc; then
  cat <<'EOF' >>~/.bashrc

# Kubernetes aliases and completion
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
alias kgp="kubectl get pods"
alias kgs="kubectl get svc"
alias kgn="kubectl get nodes"
EOF
fi

echo "==> [3/4] Déploiement de Rancher local-path-provisioner (StorageClass par défaut)"
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "==> [4/4] Déploiement de Ingress NGINX en mode NodePort (HTTP: 30080, HTTPS: 30443)"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443

# Metrics-Server n'est volontairement pas installé ici : il est déployé par les stagiaires à l'Atelier 06.

echo "------------------------------------------------------------------"
echo "Addons installés avec succès ! Vérification avec 'kubectl get pods -A'"

