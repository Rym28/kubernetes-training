# Guide d'Installation de l'Environnement des Ateliers

Ce guide présente les environnements utilisés pour les travaux pratiques du cours **Kubernetes (Réf. XW335)** et les outils à préparer sur votre poste.

| Ateliers | Environnement |
| :--- | :--- |
| **01** | Minikube (exercice 1), puis construction du cluster **Kubeadm** sur AWS (exercices 2 à 4) |
| **02** | **Minikube** sur votre poste |
| **03 à 07** | Le cluster **Kubeadm 3 nœuds** (1 control plane + 2 workers) construit à l'Atelier 01 ; **Minikube** en secours si la session AWS est indisponible |

---

## Option 1 : Minikube (Cluster local mono-nœud)

**Minikube** est l'outil officiel du projet Kubernetes pour exécuter un cluster complet sur sa machine. Il sert à l'exercice 1 de l'Atelier 01, à tout l'Atelier 02 et de solution de secours pour les ateliers 03 à 07 (chaque atelier signale les étapes qui diffèrent).

### 1.1 Prérequis
- 2 vCPU et 4 Go de RAM libres.
- **Docker Desktop** démarré (vérifiez avec `docker ps`).
- `kubectl` installé ([Documentation officielle](https://kubernetes.io/docs/tasks/tools/)).

### 1.2 Installer Minikube

| Système | Commande |
| :--- | :--- |
| Windows (PowerShell) | `winget install Kubernetes.minikube` |
| macOS | `brew install minikube` |
| Linux | `curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && sudo install minikube-linux-amd64 /usr/local/bin/minikube` |

### 1.3 Démarrer le cluster local
```bash
minikube start --cpus=2 --memory=4096 --driver=docker
kubectl config use-context minikube
kubectl get nodes        # un nœud « minikube » à l'état Ready
```

---

## Option 2 : AWS Academy Learner Lab — Cluster Kubeadm Multi-Nœuds (Environnement de Référence)

C'est l'environnement de référence de la formation : un vrai cluster **Kubeadm** composé d'un plan de contrôle et de deux workers, comme en production.

| Élément | Valeur |
| :--- | :--- |
| Topologie | 3 instances EC2 **Ubuntu 24.04 LTS** : `k8s-control`, `k8s-worker-1`, `k8s-worker-2` |
| Gabarit | `t3.large` (2 vCPU, 8 Gio RAM) par nœud ; disque gp3 de 35 Gio (control plane) et 30 Gio (workers) |
| Région | `us-east-1` par défaut (ou `us-west-2`), seules régions autorisées par le Learner Lab |
| Adresse du control plane | **Elastic IP** fixe : elle ne change pas après un arrêt/redémarrage (les workers, eux, changent d'IP publique) |
| Clé SSH | Paire `vockey` ; fichier `labsuser.pem` téléchargé depuis *AWS Details* de **votre** session et placé dans `labs/01-Installation-Cluster/terraform/` (ne jamais le partager ni le versionner) |
| Provisionnement | Terraform (`labs/01-Installation-Cluster/terraform`) + script d'amorçage `bootstrap.sh` (containerd, kubeadm, kubelet, kubectl **v1.30**, clonage du dépôt dans `~/formation`, raccourci `~/labs`) |
| Amorçage | `kubeadm init` sur `k8s-control`, CNI **Calico**, puis `kubeadm join` sur les workers |
| Composants additionnels | `setup-addons.sh` : Helm 3, StorageClass `local-path` (par défaut), Ingress NGINX en NodePort (HTTP `30080`, HTTPS `30443`), alias `k` |
| Accès depuis votre poste | `get-kubeconfig.ps1` / `get-kubeconfig.sh` génère `terraform/kubeconfig.yaml` (à ne jamais versionner) |
| Budget | 50 $ pour toute la formation : éteignez les instances chaque soir avec `stop-session`, relancez-les avec `start-session`, et `terraform destroy` en fin de formation |

La procédure complète, pas à pas (Learner Lab, Terraform, SSH, Kubeadm, Calico, kubeconfig local), est décrite dans l'[Atelier 01 : Provisionnement du Cluster](labs/01-provisionnement-cluster.md).

Besoin de (re)créer ce cluster rapidement (session réinitialisée, rattrapage, démonstration) ? Le script `create-cluster` enchaîne toutes ces étapes à partir de vos seuls identifiants AWS : voir [Cluster AWS en une commande](cluster-aws-express.md).

> 💡 **Pourquoi pas k3s ou microk8s ?** Ces distributions « tout-en-un » masquent le plan de contrôle (Static Pods, `etcd`, certificats). Or l'Atelier 01 l'installe avec `kubeadm` et l'Atelier 07 (exercice 5) inspecte les manifests statiques d'`etcd` et de l'API Server : seul un cluster Kubeadm permet de les manipuler tels qu'ils existent en production.

---

## Outils à Installer sur votre Poste

Après chaque installation, **rouvrez votre terminal** pour que la commande soit reconnue.

| Outil | Usage | Windows (PowerShell) | macOS | Linux |
| :--- | :--- | :--- | :--- | :--- |
| **Git** | Cloner le dépôt de la formation | `winget install Git.Git` | `brew install git` | `sudo apt install -y git` |
| **kubectl** | Piloter les clusters | `winget install Kubernetes.kubectl` | `brew install kubectl` | [Procédure officielle](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) |
| **Docker Desktop** + **Minikube** | Cluster local (Option 1) | voir §1 | voir §1 | voir §1 |
| **Terraform** (≥ 1.5) | Provisionner les 3 instances EC2 | `winget install HashiCorp.Terraform` | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` | [Procédure APT HashiCorp](https://developer.hashicorp.com/terraform/install#linux) |
| **AWS CLI** | Identifiants du Learner Lab, scripts `start-session` / `stop-session` | `winget install Amazon.AWSCLI` | `brew install awscli` | [Procédure AWS](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| **Client SSH** | Connexion aux nœuds (`ssh`, `scp`) | Intégré (OpenSSH) | Intégré | Intégré |
| **FreeLens** *(optionnel)* | IDE graphique du cluster (Atelier 06) | [freelensapp.github.io](https://freelensapp.github.io/) | idem | idem |

Vérifiez l'ensemble :

```bash
git --version
kubectl version --client
docker ps
minikube version
terraform version
aws --version
ssh -V
```

> 💡 **Poste verrouillé ?** Si `kubectl` ne peut pas être installé ou si le port 6443 est filtré, réalisez les ateliers 03 à 07 en **Option B** : commandes lancées dans la session SSH sur `k8s-control`, manifests dans `~/labs/` (voir l'étape 3 de l'exercice 4 de l'Atelier 01).

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

Sur le cluster Kubeadm, vérifiez également les composants installés par `setup-addons.sh` :

```bash
kubectl get storageclass            # local-path (default)
kubectl get pods -n ingress-nginx   # contrôleur Running
```

### Créer votre namespace de travail

Quel que soit l'environnement, les ateliers 02 à 07 se déroulent dans le namespace `campus-dev`. Créez-le et définissez-le comme namespace courant (voir l'encadré « Namespace de travail » en début d'[Atelier 02](labs/02-pods-trois-briques.md)). Chaque lab rappelle ces commandes, sans effet si le namespace existe déjà :

```bash
kubectl create namespace campus-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace=campus-dev
kubectl config view --minify -o jsonpath='{..namespace}'   # doit afficher campus-dev
```

Tout est prêt ? Vous pouvez passer à l'[Atelier 01 : Provisionnement du Cluster](labs/01-provisionnement-cluster.md) !
