# Évaluation des Acquis

Conformément au programme de la formation **XW335**, votre progression est évaluée à deux moments :

| Moment | Support | Durée |
| :--- | :--- | :--- |
| Fin du Jour 1 | [QCM Jour 1](#qcm-jour-1-architecture-installation-et-deploiements) | 10 min |
| Fin du Jour 2 | [QCM Jour 2](#qcm-jour-2-administration-et-securite) puis le [test de positionnement](#test-de-positionnement-fin-de-formation) | 20 min |

La mise en situation pratique (atelier de *reverse debugging* de l'Atelier 06) complète ces questionnaires.

> 💡 Notez vos réponses sur une feuille ou dans un fichier : vous pourrez les comparer au corrigé avec le formateur.

---

## Test de Positionnement (Fin de Formation)

### Partie A : Auto-évaluation sur les objectifs de la formation

Pour chaque objectif, attribuez-vous une note de **1** (je ne sais pas faire) à **4** (je sais le faire seul et l'expliquer à un collègue).

| # | Objectif de la formation | Note (1-4) |
| :---: | :--- | :---: |
| 1 | Connaître le fonctionnement de Kubernetes et ses différents composants | |
| 2 | Savoir installer, configurer et administrer Kubernetes | |
| 3 | Être à même de placer automatiquement ses conteneurs sur un cluster ou dans le Cloud | |
| 4 | Savoir automatiser les déploiements d'applications conteneurisées | |
| 5 | Définir les bonnes pratiques pour travailler avec Kubernetes | |

### Partie B : Connaissances (une seule bonne réponse par question)

**1.** Quel composant stocke l'état complet du cluster (objets, configuration, Secrets) ?

- a) `kubelet`
- b) `etcd`
- c) `kube-proxy`
- d) CoreDNS

**2.** Quelle est la plus petite unité que Kubernetes sait déployer et planifier ?

- a) Le conteneur
- b) Le Pod
- c) Le Deployment
- d) Le nœud

**3.** Sur chaque nœud, quel agent démarre les conteneurs des pods et rend compte de leur état à l'API Server ?

- a) `kube-scheduler`
- b) `kube-controller-manager`
- c) `kubelet`
- d) `etcd`

**4.** Quel outil permet d'initialiser soi-même un cluster multi-nœuds sur des machines virtuelles ?

- a) `minikube`
- b) `kubeadm`
- c) `kubectl`
- d) Docker Compose

**5.** À quoi sert principalement un objet `Service` ?

- a) À sauvegarder les données d'un pod
- b) À fournir une adresse et un nom DNS stables devant un groupe de pods, avec répartition de charge
- c) À redémarrer automatiquement les pods en échec
- d) À limiter la mémoire consommée par un pod

**6.** Quelle commande ouvre un shell interactif dans le conteneur d'un pod en cours d'exécution ?

- a) `kubectl attach <pod> --shell`
- b) `kubectl run <pod> -- sh`
- c) `kubectl exec -it <pod> -- sh`
- d) `kubectl logs -f <pod>`

**7.** Un conteneur passe à l'état `OOMKilled`. Que s'est-il passé ?

- a) Son image est introuvable
- b) Il a dépassé sa limite de mémoire (`limits.memory`)
- c) Sa sonde de disponibilité a échoué
- d) Le nœud a été mis en maintenance

**8.** Quel objet plafonne la consommation **totale** de CPU et de mémoire d'un namespace ?

- a) `LimitRange`
- b) `ResourceQuota`
- c) `NetworkPolicy`
- d) `PodDisruptionBudget`

**9.** Quel objet permet d'autoriser ou d'interdire le trafic réseau entre les pods ?

- a) `Ingress`
- b) `Service`
- c) `NetworkPolicy`
- d) `ServiceAccount`

**10.** Un pod reste `Pending` avec l'événement `didn't match Pod's node affinity/selector`. Quelle est la cause ?

- a) L'image du conteneur est trop volumineuse
- b) Aucun nœud ne porte le label exigé par le `nodeSelector` ou l'affinité du pod
- c) La base `etcd` est indisponible
- d) Le Service associé n'a pas d'Endpoints

---

## QCM Jour 1 : Architecture, Installation et Déploiements

**1.** Sur un cluster Kubeadm, dans quel répertoire le `kubelet` lit-il les manifests des *Static Pods* du plan de contrôle ?

- a) `/var/lib/etcd`
- b) `/etc/kubernetes/manifests`
- c) `~/.kube/config`
- d) `/etc/cni/net.d`

**2.** Quel est le rôle du `kube-scheduler` ?

- a) Démarrer les conteneurs sur les nœuds
- b) Choisir le nœud sur lequel chaque nouveau pod sera exécuté
- c) Stocker les objets du cluster
- d) Router le trafic des Services

**3.** Le `kube-scheduler` est arrêté. Que devient un pod nouvellement créé ?

- a) Il démarre normalement sur le control plane
- b) Il reste `Pending`, alors que les pods déjà en place continuent de fonctionner
- c) Il est supprimé immédiatement
- d) Tous les pods du cluster s'arrêtent

**4.** Que produit `kubectl create deployment web --image=nginx --dry-run=client -o yaml` ?

- a) Un Deployment créé dans le cluster puis affiché
- b) Le manifest YAML du Deployment, sans rien créer dans le cluster
- c) Une erreur, car `--dry-run` exige un fichier
- d) La liste des Deployments existants

**5.** Vous supprimez manuellement un pod géré par un Deployment à 2 réplicas. Que se passe-t-il ?

- a) Le Deployment passe à 1 réplica
- b) Le ReplicaSet recrée aussitôt un pod pour revenir à 2
- c) Le Deployment est supprimé
- d) Rien tant qu'on ne relance pas `kubectl apply`

**6.** Un Deployment de 3 réplicas utilise `maxSurge: 1` et `maxUnavailable: 0`. Pendant une mise à jour :

- a) Les 3 anciens pods sont arrêtés avant de créer les nouveaux
- b) Il y a toujours au moins 3 pods disponibles, et jusqu'à 4 pods au total
- c) Il peut n'y avoir qu'un seul pod disponible
- d) La mise à jour est impossible

**7.** Quelle commande annule la dernière mise à jour d'un Deployment ?

- a) `kubectl rollout undo deployment/campus-backend`
- b) `kubectl delete deployment campus-backend`
- c) `kubectl rollout pause deployment/campus-backend`
- d) `kubectl scale deployment campus-backend --replicas=0`

**8.** Quel est le nom DNS complet du Service `campus-backend` situé dans le namespace `campus-dev` ?

- a) `campus-backend.cluster.local`
- b) `campus-backend.campus-dev.svc.cluster.local`
- c) `campus-dev.campus-backend.svc`
- d) `campus-backend.pod.cluster.local`

**9.** Quelle est la plage de ports utilisée par défaut pour les Services de type `NodePort` ?

- a) 1-1024
- b) 8000-8999
- c) 30000-32767
- d) 49152-65535

**10.** Pourquoi aucun pod applicatif ne s'exécute-t-il sur le nœud `k8s-control` d'un cluster Kubeadm ?

- a) Il n'a pas de `kubelet`
- b) Il porte la taint `node-role.kubernetes.io/control-plane:NoSchedule`
- c) Il n'a pas d'adresse IP privée
- d) Kubeadm supprime les pods qui s'y trouvent toutes les heures

---

## QCM Jour 2 : Administration et Sécurité

**1.** Par défaut, la valeur d'un `Secret` Kubernetes est :

- a) Chiffrée en AES dans `etcd`
- b) Simplement encodée en base64, donc lisible par qui accède à `etcd` ou peut lire le Secret
- c) Stockée uniquement en mémoire
- d) Inaccessible aux pods

**2.** Quelle est la relation entre un `PersistentVolumeClaim` (PVC) et un `PersistentVolume` (PV) ?

- a) Le PVC est une demande de stockage, satisfaite en la liant à un PV
- b) Le PV est une demande, le PVC le disque réel
- c) Ce sont deux noms du même objet
- d) Le PVC remplace la StorageClass

**3.** Que se passe-t-il lorsque la **readiness probe** d'un pod échoue ?

- a) Le conteneur est redémarré
- b) Le pod est retiré des Endpoints de son Service, sans être redémarré
- c) Le nœud est mis en quarantaine
- d) Le pod est supprimé

**4.** Que se passe-t-il lorsque la **liveness probe** d'un conteneur échoue de façon répétée ?

- a) Le `kubelet` redémarre le conteneur
- b) Le Service s'arrête
- c) Le Deployment est annulé
- d) Rien, l'événement est seulement journalisé

**5.** Comment afficher les logs de l'exécution **précédente** d'un conteneur qui vient de planter ?

- a) `kubectl logs <pod> --previous`
- b) `kubectl describe pod <pod> --logs`
- c) `kubectl get events --previous`
- d) `kubectl exec <pod> -- cat /var/log/previous`

**6.** Quel est le rôle de **Node Problem Detector** ?

- a) Remplacer le `kubelet` en cas de panne
- b) Détecter des problèmes du nœud (noyau, système) et les remonter sous forme de conditions et d'événements Kubernetes
- c) Redémarrer automatiquement les nœuds défaillants
- d) Mesurer la consommation CPU des pods

**7.** Que fait `kubectl cordon k8s-worker-1` ?

- a) Supprime tous les pods du nœud
- b) Marque le nœud comme non planifiable, sans expulser les pods déjà présents
- c) Redémarre le nœud
- d) Retire le nœud du cluster

**8.** Le programme mentionne **StackDriver**. À quoi correspond aujourd'hui ce service ?

- a) À un outil CNCF équivalent à Prometheus
- b) À Google Cloud Observability (Cloud Logging, Cloud Monitoring), la solution managée de Google Cloud
- c) Au tableau de bord officiel de Kubernetes
- d) À un service AWS de collecte de logs

**9.** À quoi sert un `LimitRange` ?

- a) À limiter le nombre de namespaces
- b) À imposer des valeurs par défaut, minimales et maximales de ressources aux conteneurs d'un namespace
- c) À limiter le trafic réseau entrant
- d) À limiter le nombre de nœuds du cluster

**10.** Dans un cluster Kubeadm, qui est autorisé à dialoguer directement avec `etcd` ?

- a) Tous les pods du namespace `kube-system`
- b) Uniquement l'API Server, qui présente un certificat client signé par l'autorité d'`etcd` (TLS mutuel)
- c) N'importe quel utilisateur disposant d'un kubeconfig
- d) Le `kubelet` de chaque nœud
