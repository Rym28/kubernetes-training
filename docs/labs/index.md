# Vue d'Ensemble des Travaux Pratiques

<div class="admonition note">
<p class="admonition-title">Parcours Pratique Progressif</p>
<p>Les ateliers pratiques suivent une progression : chacun ajoute une brique à l'application fil rouge <b>Campus Summer Portal</b>, de la création du cluster jusqu'à la sécurisation de la plateforme en production.</p>
</div>

<div class="admonition tip">
<p class="admonition-title">Des ateliers rejouables indépendamment</p>
<p>À partir de l'Atelier 03, chaque atelier commence par une <b>Étape 0</b> qui crée le namespace <code>campus-dev</code> s'il n'existe pas et applique les manifests de départ (<i>starter</i>). Vous pouvez donc reprendre un atelier sans avoir terminé les précédents, ou le recommencer de zéro avec l'encadré « Repartir de zéro ».</p>
</div>

---

## Comment utiliser les indices d'aide ?

Dans chaque atelier, vous trouverez des blocs d'indices progressifs pliables :

??? tip "Exemple d'indice interactif (Cliquez pour tester)"
    Bravo ! En cliquant sur cette boîte, vous découvrez des explications méthodologiques, des pistes de réflexion ou des commandes de secours pour vous débloquer de manière autonome.

---

## Parcours des Ateliers

### Partie 1 — Déploiement du Cluster & Fondations (Jour 1)

| Atelier | Titre de l'atelier | Concepts Clés Traités |
| :---: | :--- | :--- |
| **[Atelier 01](01-provisionnement-cluster.md)** | **Provisionnement du Cluster** | Cluster local Minikube, provisionnement de 3 instances EC2 par Terraform (AWS Learner Lab), accès SSH, installation du cluster multi-nœuds avec Kubeadm et Calico, composants additionnels (local-path-provisioner, Ingress NGINX, Helm), kubeconfig sur le poste. |
| **[Atelier 02](02-pods-trois-briques.md)** | **Les Pods : les Trois Briques du Campus Summer Portal** | Manifest d'un Pod, cycle de vie, `describe`, `port-forward`, diagnostic d'une erreur classique, flux déclaratif `--dry-run=client`, `kubectl exec`, limites du pod isolé. |
| **[Atelier 03](03-deploiements-resilience-rollback.md)** | **Déploiements — Résilience & Rollback** | Base PostgreSQL de développement, contrôleur `Deployment`, ReplicaSets, Self-healing, mise à l'échelle impérative et déclarative, RollingUpdate (`maxSurge`/`maxUnavailable`), historique des révisions et Rollback. |
| **[Atelier 04](04-reseau-services-dns.md)** | **Réseau, Services & Découverte DNS** | IP volatiles des pods, Service `ClusterIP` et Endpoints, découverte DNS, Service `NodePort` et ses 3 ports, accès depuis le navigateur. |

---

### Partie 2 — Persistance, Exploitation & Sécurité (Jour 2)

| Atelier | Titre de l'atelier | Concepts Clés Traités |
| :---: | :--- | :--- |
| **[Atelier 05](05-configuration-stockage-persistant.md)** | **Configuration & Stockage Persistant (PV / PVC / PostgreSQL)** | `ConfigMap` (literal/file), `Secret` encodé base64, `PersistentVolume` et `PersistentVolumeClaim`, PostgreSQL et crash-test de persistance SQL. |
| **[Atelier 07](07-securite-quotas-isolement-reseau.md)** | **Sécurité, Quotas & Isolement Réseau (NetworkPolicy)** | LimitRange et ResourceQuota, NetworkPolicies *Default Deny* et flux autorisés, `securityContext` non-root, ServiceAccount et RBAC (`kubectl auth can-i`), protection de l'API Server et d'etcd. Réalisé **avant** l'Atelier 06. |
| **[Atelier 06](06-exploitation-observabilite-debugging.md)** | **Exploitation, Observabilité & Reverse Debugging** | `kubectl logs` et événements, `kubectl exec`, méthode de dépannage sur 3 incidents (`CrashLoopBackOff`, `OOMKilled`, Service sans réponse), Node Problem Detector et `cordon`, Metrics Server, Prometheus, Fluent Bit, Loki et Grafana, StackDriver. Réalisé **après** l'Atelier 07. |

Ordre de réalisation au Jour 2 : 05, puis 07 (Sécurité), puis 06 (Administration).

---

## Prérequis Techniques
Consultez le [Guide d'installation de l'environnement](../setup-environnement.md) avant de démarrer le premier atelier.

En cas d'indisponibilité de la session AWS, les ateliers à partir du 03 peuvent être réalisés en secours sur **Minikube** : chaque atelier signale les étapes qui diffèrent.
