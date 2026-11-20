# Vue d'Ensemble des Travaux Pratiques

<div class="admonition note">
<p class="admonition-title">Parcours Pratique Progressif</p>
<p>Les 9 ateliers pratiques (Lab 00 à Lab 08) sont conçus pour être réalisés progressivement. Chaque lab consolide les compétences du précédent tout en construisant pas-à-pas l'application fil rouge <b>Campus Summer Portal</b>.</p>
</div>

---

## Comment utiliser les indices d'aide ?

Dans chaque atelier, vous trouverez des blocs d'indices progressifs pliables :

??? tip "Exemple d'indice interactif (Cliquez pour tester)"
    Bravo ! En cliquant sur cette boîte, vous découvrez des explications méthodologiques, des pistes de réflexion ou des commandes de secours pour vous débloquer de manière autonome.

---

## Parcours des Ateliers

### Partie 1 : Déploiement du Cluster & Fondations d'Orchestration (Jour 1)

| Atelier | Titre du Lab | Concepts Clés Traités |
| :---: | :--- | :--- |
| **[Lab 00](00-provisioning-cluster.md)** | **Provisionnement du Cluster** | Installation de Minikube en local, provisionnement des 3 instances EC2 par Terraform, puis installation du cluster multi-nœuds avec Kubeadm et Calico. |
| **[Lab 01](01-control-plane-anatomy.md)** | **Anatomie du Plan de Contrôle** | Static Pods (`/etc/kubernetes/manifests`), santé et instantané `etcd` avec `etcdctl` (mTLS), requêtes brutes API Server (`/readyz`), panne du Scheduler. |
| **[Lab 02](02-premiers-pods-labels.md)** | **Premiers Pods, Labels & InitContainers** | Pod `campus-backend`, flux déclaratif `--dry-run=client`, variables d'environnement, requests/limits CPU/RAM, InitContainers. |
| **[Lab 03](03-deployments-resilience.md)** | **Déploiements, Résilience & Rollback** | Base PostgreSQL de développement, contrôleur `Deployment`, ReplicaSets, Self-healing, RollingUpdate (`maxSurge`/`maxUnavailable`), Rollback ciblé, placement des pods (`nodeSelector`, taints, `podAntiAffinity`). |
| **[Lab 04](04-services-reseau.md)** | **Réseau, Services & Découverte DNS** | Service `ClusterIP`, résolution DNS CoreDNS, Endpoints & mise en quarantaine, Service `NodePort` et tunnel `port-forward`. |

---

### Partie 2 : Persistance, Exploitation & Sécurité de Production (Jour 2)

| Atelier | Titre du Lab | Concepts Clés Traités |
| :---: | :--- | :--- |
| **[Lab 05](05-configuration-persistance.md)** | **Configuration & Stockage Persistant** | `ConfigMap` (literal/file), `Secret` encodé base64, StorageClass, volumes PV/PVC, PostgreSQL et crash-test de persistance SQL. |
| **[Lab 06](06-exploitation-debugging.md)** | **Exploitation, Observabilité & Debugging** | Sondes `startup`/`liveness`/`readiness`, reverse debugging de 3 pannes, NPD avancé & cordon, pile CNCF complète (Metrics-Server, Fluent Bit, Loki, Prometheus, Grafana). |
| **[Lab 07](07-securite-quotas.md)** | **Sécurité, Quotas & Isolement Réseau** | Admission `LimitRange` + `ResourceQuota`, `NetworkPolicy` Zéro-Trust (*default deny* + 3 flux autorisés), conteneurs non-root, RBAC et restrictions d'accès à `etcd`. |
| **[Lab 08](08-challenge-integration.md)** | **Challenge Final d'Intégration** | Déploiement en autonomie de la plateforme 3-tiers dans `campus-prod`, script d'auto-évaluation et crash-test de résilience. |

---

## Prérequis Techniques
Consultez le [Guide d'installation de l'environnement](../setup-environnement.md) avant de démarrer le premier atelier.
