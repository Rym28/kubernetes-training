# Guide d'Installation de l'Environnement de Lab

Ce guide présente les différentes options d'environnement pour exécuter les travaux pratiques du cours **Kubernetes (Réf. XW335)**. Choisissez l'option la plus adaptée à votre configuration matérielle ou à la politique de votre entreprise.

---

## Option 1 : Minikube (Standard du Développement Local sur PC / Mac / Linux)

**Minikube** est l'outil officiel du projet Kubernetes pour exécuter un cluster complet directement sur sa machine locale, avec un riche catalogue d'extensions (Ingress, Dashboard, Metrics Server).

### 1.1 Prérequis
- Docker Desktop, Podman ou Hyper-V / VirtualBox actif.
- `kubectl` installé ([Documentation officielle](https://kubernetes.io/docs/tasks/tools/)).

### 1.2 Démarrage du cluster local
```bash
minikube start --cpus=2 --memory=4096 --driver=docker
```

### 1.3 Activer les add-ons recommandés
```bash
minikube addons enable ingress
minikube addons enable metrics-server
```

### 1.4 Accéder aux services NodePort
```bash
minikube service <nom-du-service> --url
```

---

## Option 2 : KillerCoda (Zéro Installation locale dans le Navigateur)

Idéal pour les postes d'entreprise verrouillés (sans droits administrateur ou sans virtualisation locale).

1. Rendez-vous sur [killercoda.com/playgrounds](https://killercoda.com/playgrounds).
2. Choisissez l'environnement **Kubernetes Playground (Latest)**.
3. Vous disposez instantanément d'un cluster Kubernetes 2 nœuds (Control Plane + Worker) dans votre navigateur, avec accès `kubectl` complet.

---

## Option 3 : AWS Academy Learner Lab — Cluster Kubeadm Multi-Nœuds (Environnement de Référence)

C'est l'environnement de référence de la formation : un vrai cluster **Kubeadm** composé d'un plan de contrôle et de deux workers, comme en production.

| Élément | Valeur |
| :--- | :--- |
| Topologie | 3 instances EC2 Ubuntu : `k8s-control`, `k8s-worker-1`, `k8s-worker-2` |
| Gabarit | `t3.large` (2 vCPU, 8 Gio RAM) par nœud |
| Région | `us-east-1` (ou `us-west-2`), seules régions autorisées par le Learner Lab |
| Clé SSH | `labsuser.pem`, téléchargée depuis *AWS Details* de **votre** session (ne jamais la partager ni la versionner) |
| Provisionnement | Terraform (`labs/00-provisioning-cluster/terraform`) + script d'amorçage `bootstrap.sh` (containerd, kubeadm, kubelet, kubectl) |
| Amorçage | `kubeadm init` sur `k8s-control`, CNI **Calico**, puis `kubeadm join` sur les workers |

La procédure complète, pas à pas (console AWS, Terraform, SSH/MobaXterm, Kubeadm, kubeconfig local), est décrite dans le [Lab 00 : Déploiement de l'Infrastructure](labs/00-provisioning-cluster.md).

> 💡 **Pourquoi pas k3s ou microk8s ?** Ces distributions « tout-en-un » masquent le plan de contrôle (Static Pods, `etcd`, certificats). Or les labs 01 et 07 inspectent justement ces composants : seul un cluster Kubeadm permet de les manipuler tels qu'ils existent en production.

---

## Outils Complémentaires Recommandés

Pour une expérience optimale lors des ateliers pratiques, préparez les outils suivants sur votre poste :

### 1. Terraform (Infrastructure as Code)
Requis pour automatiser le déploiement multi-nœuds AWS dans le Lab 00 :
* **Windows (PowerShell)** : `winget install HashiCorp.Terraform` (ou déposez l'exécutable portable `terraform.exe` dans votre dossier).
* **Linux (Ubuntu / Debian)** :
  ```bash
  sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
  wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt install -y terraform
  ```
* **macOS (Homebrew)** : `brew tap hashicorp/tap && brew install hashicorp/tap/terraform`

### 2. MobaXterm & FreeLens
* **MobaXterm** (Windows) : Client SSH avec mode Multi-Exec et SFTP intégré ([mobaxterm.mobatek.net](https://mobaxterm.mobatek.net/)).
* **FreeLens** : IDE open-source pour visualiser l'état du cluster Kubernetes ([freelensapp.github.io](https://freelensapp.github.io/)).

---

## Validation de l'Environnement

Exécutez les commandes suivantes pour vous assurer que tout est opérationnel :

```bash
# Vérifier la connexion au cluster
kubectl cluster-info

# Vérifier que les nœuds sont en état 'Ready'
kubectl get nodes

# Vérifier les pods système du cluster
kubectl get pods -n kube-system
```

### Créer votre namespace de travail

Quel que soit l'environnement choisi (Minikube, KillerCoda ou AWS), tous les ateliers se déroulent dans le namespace `campus-dev`. Créez-le et définissez-le comme namespace courant (détails dans le [Lab 00, §6.5](labs/00-provisioning-cluster.md#65-creer-votre-espace-de-travail-le-namespace-campus-dev)) :

```bash
kubectl create namespace campus-dev
kubectl config set-context --current --namespace=campus-dev
kubectl config view --minify -o jsonpath='{..namespace}'   # doit afficher campus-dev
```

Tout est prêt ? Vous pouvez passer au [Lab 00 : Déploiement de l'Infrastructure](labs/00-provisioning-cluster.md) !
