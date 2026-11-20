#!/bin/bash
# ==============================================================================
# Script d'amorçage système (User Data) pour nœuds Kubernetes Ubuntu 24.04 LTS
# Prépare le système, configure containerd et installe Kubernetes v1.30
# ==============================================================================
set -euo pipefail

# Nom du nœud injecté par Terraform (templatefile) : k8s-control, k8s-worker-1 ou k8s-worker-2.
# Kubernetes reprend le hostname comme nom de nœud : les labs y font référence (label, taint, nodeName).
NODE_NAME="${node_name}"
echo "==> [0/6] Nom d'hôte : $NODE_NAME"
hostnamectl set-hostname "$NODE_NAME"
echo "$(hostname -I | awk '{print $1}') $NODE_NAME" >>/etc/hosts
# Empêche cloud-init de remettre le nom AWS (ip-172-31-...) au redémarrage (stop/start-session)
echo "preserve_hostname: true" >/etc/cloud/cloud.cfg.d/99-k8s-hostname.cfg

echo "==> [1/6] Désactivation du swap"
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "==> [2/6] Configuration des modules du noyau Linux"
cat <<EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

echo "==> [3/6] Configuration des paramètres sysctl pour le réseau Kubernetes"
cat <<EOF >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

echo "==> [4/6] Installation et configuration du runtime containerd"
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gpg containerd jq git

mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

echo "==> [5/6] Ajout du dépôt officiel Kubernetes v1.30"
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" >/etc/apt/sources.list.d/kubernetes.list

echo "==> [6/6] Installation et verrouillage des paquets kubelet, kubeadm, kubectl"
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

echo "==> [Bonus] Clonage du dépôt de la formation dans /home/ubuntu/formation (raccourci ~/labs)"
if [ ! -d /home/ubuntu/formation ]; then
  git clone --depth 1 https://github.com/h4mdi/training.git /home/ubuntu/formation \
    || echo "Clonage impossible : clonez le dépôt manuellement (Lab 00, étape 5.4)"
fi
if [ -d /home/ubuntu/formation/labs ]; then
  ln -sfn /home/ubuntu/formation/labs /home/ubuntu/labs
  chown -R ubuntu:ubuntu /home/ubuntu/formation
  chown -h ubuntu:ubuntu /home/ubuntu/labs
fi

echo "==> Initialisation du nœud terminée avec succès !"
