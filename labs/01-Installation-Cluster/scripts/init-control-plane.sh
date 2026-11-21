#!/bin/bash
# ==============================================================================
# Initialisation du Control Plane Kubernetes avec kubeadm & Calico CNI
# À exécuter sur le nœud k8s-control en tant qu'utilisateur ubuntu
# ==============================================================================
set -euo pipefail

echo "==> [1/4] Initialisation de kubeadm (CIDR Pods: 192.168.0.0/16 pour Calico)"
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

echo "==> [2/4] Configuration des accès kubectl pour l'utilisateur ubuntu"
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u)":"$(id -g)" "$HOME/.kube/config"

echo "==> [3/4] Déploiement de Calico CNI v3.28.2 (indispensable pour les NetworkPolicies)"
CALICO_VERSION="v3.28.2"
kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"
# Sur AWS VPC, l'encapsulation VXLAN doit être active entre toutes les instances (VXLAN Always et non VXLANCrossSubnet)
# pour que le trafic réseau inter-noeuds ne soit pas bloqué par le contrôle source/dest d'AWS.
curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml" \
  | sed 's/encapsulation: VXLANCrossSubnet/encapsulation: VXLAN/' \
  | kubectl create -f -

echo "==> [4/4] Génération de la commande de jonction pour les workers"
echo "------------------------------------------------------------------"
echo "Exécutez la commande suivante avec 'sudo' sur chaque worker (k8s-worker-1 et k8s-worker-2) :"
echo ""
sudo kubeadm token create --print-join-command
echo "------------------------------------------------------------------"
echo "Vérifiez ensuite l'état des nœuds avec : kubectl get nodes -w"
