# Cahier des Travaux Pratiques Kubernetes

Bienvenue dans le recueil d'ateliers pratiques Kubernetes. Ce cahier articule deux volets indispensables à tout ingénieur ou administrateur Kubernetes :

1. **L'Infrastructure & le Cluster** : Comprendre comment un cluster multi-nœuds est provisionné de zéro (Kubeadm sur AWS / Minikube / KillerCoda) et ausculter les composants du plan de contrôle (*Control Plane*, `etcd`, `kubelet`, *Static Pods*, requêtes brutes).
2. **L'Application Fil Rouge** : Prendre en main, fiabiliser, interconnecter et sécuriser une application microservices d'entreprise réelle : le **Campus Summer Portal** (Portail Horizon Stages : Frontend Nginx + API Backend Spring Boot + Base de données PostgreSQL).

---

## L'Application Fil Rouge : Campus Summer Portal

L'application est découpée en 3 composants interdépendants :

1. **Frontend Web** (`campus-frontend`) : Interface utilisateur servie par Nginx (`regaieg/campus:frontend-1.0.0`).
2. **API Backend** (`campus-backend`) : API REST Spring Boot (`regaieg/campus:backend-1.0.0`) connectée à la base de données.
3. **Base de Données** (`campus-postgres`) : Instance relationnelle PostgreSQL (`postgres:16-alpine`) nécessitant un stockage persistant.

---

## Comment utiliser les indices d'aide ?

Dans chaque lab, cherchez les blocs d'indices interactifs progressifs :
<details>
<summary>💡 <b>Exemple d'indice pliable (Cliquez ici pour tester)</b></summary>

Bravo ! En cliquant sur cette ampoule, vous découvrez des explications méthodologiques, des pistes de réflexion ou des commandes de secours pour vous débloquer en toute autonomie.
</details>

---

## Synthèse des Ateliers Pratiques

### Partie 1 : Déploiement du Cluster & Fondations d'Orchestration (Jour 1)

| Atelier | Titre du Lab | Concepts Clés Traités |
| :---: | :--- | :--- |
| **[Lab 00](./00-provisioning-cluster/README.md)** | **Provisionnement du Cluster** | Installation de Minikube en local, provisionnement des 3 instances EC2 par Terraform, puis installation du cluster multi-nœuds avec Kubeadm et Calico. |
| **[Lab 02](./02-premiers-pods-labels/README.md)** | **Premiers Pods** | Manifest d'un Pod, cycle de vie, `port-forward`, flux déclaratif `--dry-run=client`, limites du pod isolé. |
| **[Lab 03](./03-deployments-resilience/README.md)** | **Déploiements, Résilience & Rollback** | Base PostgreSQL de développement, contrôleur `Deployment`, ReplicaSets, Self-healing, RollingUpdate (`maxSurge`/`maxUnavailable`), Rollback ciblé, placement des pods (`nodeSelector`, taints, `podAntiAffinity`). |
| **[Lab 04](./04-services-reseau/README.md)** | **Réseau, Services & Découverte DNS** | IP volatiles des pods, Service `ClusterIP` et Endpoints, découverte DNS CoreDNS, Service `NodePort` et répartition de charge. |

---

### Partie 2 : Persistance, Exploitation & Sécurité de Production (Jour 2)

| Atelier | Titre du Lab | Concepts Clés Traités |
| :---: | :--- | :--- |
| **[Lab 05](./05-configuration-persistance/README.md)** | **Configuration & Stockage Persistant** | `ConfigMap` (literal/file), `Secret` encodé base64, StorageClass, volumes PV/PVC, PostgreSQL et crash-test de persistance SQL. |
| **[Lab 06](./06-exploitation-debugging/README.md)** | **Exploitation, Observabilité & Debugging** | Logs, `kubectl exec`, méthode de dépannage sur 3 pannes, Node Problem Detector & cordon/drain, Metrics Server, Prometheus, Fluent Bit, Loki, Grafana. |
| **[Lab 07](./07-securite-quotas/README.md)** | **Sécurité, Quotas & Isolement Réseau** | Admission `LimitRange` + `ResourceQuota`, `NetworkPolicy` Zéro-Trust (*default deny* + 3 flux autorisés), conteneurs non-root, RBAC et restrictions d'accès à `etcd`. |
| **[Lab 08](./08-challenge-integration/README.md)** | **Challenge Final d'Intégration** | Déploiement en autonomie de la plateforme 3-tiers dans `campus-prod`, script d'auto-évaluation et crash-test de résilience. |

---

## Prérequis pour démarrer
Consultez le [Guide d'installation de l'environnement](../docs/setup-environnement.md).
