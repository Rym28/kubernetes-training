# Lab 01 : Anatomie du Plan de Contrôle Kubernetes

### Objectifs Pédagogiques :
* Inspecter les manifestes des Pods statiques gérés par la `kubelet` dans `/etc/kubernetes/manifests`.
* Interroger l'état, la révision et les membres du cluster `etcd` avec l'outil CLI officiel `etcdctl`, et en réaliser une sauvegarde (*snapshot*).
* Effectuer des requêtes HTTP brutes aux endpoints système de l'API Server avec `kubectl get --raw` (`/livez`, `/readyz`, `/metrics`).
* Provoquer une panne ciblée du plan de contrôle en isolant le `kube-scheduler`.
* Observer le blocage d'un Pod applicatif à l'état `Pending` avec un champ `nodeName` vide (`<none>`).
* Rétablir le composant et observer la prise en charge immédiate par le réconciliateur d'ordonnancement.

---

## Contexte Technique et Métier

Avant de déployer les microservices de l'application **Campus Summer Portal** (Portail Horizon Stages), vous devez qualifier techniquement les composants internes du cluster Kubernetes.

En production, un administrateur ou ingénieur DevOps ne doit pas considérer le plan de contrôle comme une boîte noire :

* Lorsqu'un Pod reste bloqué à l'état `Pending`, est-ce un problème de ressources physiques, de contraintes d'affinité, ou une défaillance du composant d'ordonnancement ?
* Comment vérifier directement l'état de santé du stockage `etcd` ?
* Quel est le chemin exact emprunté par une ressource entre la commande `kubectl apply` et son exécution concrète sur un worker ?

Dans cet atelier, vous allez explorer le Control Plane sur le nœud maître, interroger la base `etcd` en mTLS, ausculter les sondes natives de l'API Server avec `kubectl get --raw`, et observer le comportement d'ordonnancement en isolant temporairement le `kube-scheduler`.

---

## État Initial Requis

* Un cluster Kubernetes opérationnel (issu du **Lab 00**).
* Accès SSH avec privilèges `sudo` sur le nœud de contrôle (`k8s-control`).
* Le namespace de travail `campus-dev`, créé et défini comme namespace courant sur `k8s-control` (commandes ci-dessous) : le Pod de test `scheduler-probe` de l'exercice 4 y sera créé, tandis que les composants du plan de contrôle restent dans `kube-system`. Le namespace est présenté en détail à l'Exercice 0 du [Lab 02](../02-premiers-pods-labels/README.md#exercice-0--le-namespace-votre-périmètre-de-travail).

> ⚠️ **Environnement d'exécution pour ce lab :**  
> Contrairement aux ateliers suivants qui pourront être exécutés confortablement depuis votre poste local avec votre `kubectl` et votre IDE, **ce Lab 01 nécessite obligatoirement d'être connecté en SSH sur `k8s-control`**. Nous allons en effet auditer des répertoires système hôtes (`/etc/kubernetes/manifests`), manipuler le service `kubelet` et interroger la base `etcd` en local, ce qui est impossible à distance.

### Préparation et vérification

**k8s-control — SSH**
```bash
kubectl get nodes
# Créer le namespace de travail s'il n'existe pas encore (sans effet s'il existe déjà)
kubectl create namespace campus-dev --dry-run=client -o yaml | kubectl apply -f -
# En faire le namespace courant, puis vérifier
kubectl config set-context --current --namespace=campus-dev
kubectl config view --minify -o jsonpath='{..namespace}'
```
*Le nœud de contrôle et les deux workers doivent être à l'état `Ready`, et le namespace courant doit être `campus-dev`.*

---

## Exercice 1 : Inspection des Manifestes Statiques du Plan de Contrôle
Connectez-vous en SSH sur le nœud `k8s-control` :

1. Rendez-vous dans le répertoire de configuration des Pods statiques :
   ```bash
   sudo ls -lh /etc/kubernetes/manifests/
   ```
2. Identifiez les 4 composants majeurs démarrés et surveillés directement par la `kubelet` locale :
   * `kube-apiserver.yaml` : la porte d'entrée REST de toutes les opérations du cluster.
   * `kube-controller-manager.yaml` : la boucle de contrôle qui réconcilie l'état désiré et réel (ReplicaSets, Nodes, Endpoints).
   * `kube-scheduler.yaml` : le moteur qui affecte chaque nouveau Pod à un nœud éligible.
   * `etcd.yaml` : la base clé-valeur distribuée hautement cohérente.
3. Observez la configuration d'écoute et les certificats TLS de l'API Server :
   ```bash
   sudo grep -E "etcd-servers|client-ca-file|tls-cert-file" /etc/kubernetes/manifests/kube-apiserver.yaml
   ```

---

## Exercice 2 : Interrogation Directe de la Base etcd avec etcdctl
`etcd` est le cœur battant du cluster. Si `etcd` est inaccessible, tout le cluster est paralysé.
1. Vérifiez la présence du client ou installez le paquet utilitaire :
   ```bash
   which etcdctl || sudo apt-get install -y etcd-client
   ```
2. Interrogez la santé du cluster etcd en fournissant les certificats mTLS officiels situés dans `/etc/kubernetes/pki/etcd/` :
   ```bash
   sudo ETCDCTL_API=3 etcdctl \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     endpoint health
   ```
   *Sortie attendue : `https://127.0.0.1:2379 is healthy: successfully committed proposal`.*
3. Affichez la liste des membres et l'état des endpoints sous forme de tableau :
   ```bash
   sudo ETCDCTL_API=3 etcdctl \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     member list -w table

   sudo ETCDCTL_API=3 etcdctl \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     endpoint status -w table
   ```
   *Notez la taille de la base (`DB SIZE`) et l'index de révision (`RAFT REVISION`).*

4. **Le réflexe d'administrateur : sauvegarder `etcd`.** Toute la configuration du cluster tient dans cette base : une sauvegarde régulière est la première assurance-vie d'un cluster Kubeadm. Créez un instantané puis vérifiez-le :
   ```bash
   sudo ETCDCTL_API=3 etcdctl \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     snapshot save /tmp/etcd-backup.db

   sudo ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db -w table
   ```
   *Le tableau affiche le nombre de clés et la taille de l'instantané. En production, ce fichier est copié hors du nœud (stockage objet, autre site) et protégé comme un secret : il contient tous les `Secrets` du cluster (voir Lab 07).*

---

## Exercice 3 : Requêtes Brutes à l'API Server avec kubectl get --raw
`kubectl get --raw` permet de sonder directement les points de terminaison HTTP internes de l'API Server sans passer par les abstractions de ressources.
1. Interrogez les sondes de disponibilité de l'API Server avec le détail verbeux :
   ```bash
   kubectl get --raw '/livez?verbose'
   kubectl get --raw '/readyz?verbose'
   ```
   *Observez la longue liste des vérifications individuelles (etcd, cache, poststarthook...).*

2. Consultez un échantillon des métriques Prometheus brutes exposées par le plan de contrôle :
   ```bash
   kubectl get --raw /metrics | head -n 25
   ```

---

## Exercice 4 : Injection de Panne — Arrêt du Kube-Scheduler et Observation SRE
Pour comprendre le découplage entre l'admission d'une ressource et son affectation à un serveur, provoquons une panne d'ordonnancement.

1. Déplacez le fichier du scheduler hors de la surveillance de la kubelet :
   ```bash
   sudo mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/kube-scheduler.yaml
   ```
2. Observez la disparition du Pod `kube-scheduler` dans le namespace `kube-system` :
   ```bash
   kubectl get pods -n kube-system | grep scheduler
   ```
   *(Le pod disparaît de la liste en une dizaine de secondes).*

3. Tentez maintenant de déployer une charge applicative de test (représentant une sonde de l'application Université Horizon) :
   ```bash
   kubectl apply -f - << 'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: scheduler-probe
     labels:
       app.kubernetes.io/name: scheduler-probe
       app.kubernetes.io/part-of: campus-summer-portal
   spec:
     containers:
     - name: probe
       image: busybox:1.36
       command: ["sh", "-c", "echo 'Scheduler probe running' && sleep 3600"]
       resources:
         requests:
           cpu: 50m
           memory: 32Mi
   EOF
   ```
4. Observez le statut du Pod :
   ```bash
   kubectl get pod scheduler-probe -o wide
   ```
   * **Constat frappant :** Le Pod est à l'état `Pending`, et son champ `NODE` est strictement vide (`<none>`) !
5. Inspectez les événements du Pod :
   ```bash
   kubectl describe pod scheduler-probe | tail -n 10
   ```
   * **Analyse SRE :** L'API Server a validé le Pod et l'a écrit dans `etcd` sans la moindre erreur. Mais en l'absence de scheduler, aucun algorithme ne calcule de nœud éligible. Les kubelets des workers ne prennent pas en charge le conteneur car leur nom n'est pas inscrit dans `spec.nodeName`.
6. Rétablissez le scheduler en remettant son manifeste en place :
   ```bash
   sudo mv /tmp/kube-scheduler.yaml /etc/kubernetes/manifests/kube-scheduler.yaml
   ```
7. Observez la réactivation immédiate :
   ```bash
   kubectl get pods -n kube-system | grep scheduler
   kubectl get pod scheduler-probe -o wide
   ```
   *Dès que le Pod du scheduler redevient `Running`, il détecte le Pod en attente, le lie à l'un des workers (`k8s-worker-1` ou `2`), et le statut passe aussitôt à `Running` !*

   > 💡 Conservez le Pod `scheduler-probe` : il sert à la validation finale (section 8), qui se charge de le supprimer.

---

## 5. Contraintes du Lab

* Ne touchez pas aux certificats TLS dans `/etc/kubernetes/pki`.
* Ne redémarrez pas la machine hôte.
* La panne doit être diagnostiquée et résolue uniquement par la manipulation des manifestes statiques et la lecture d'événements.

---

## 6. Points de contrôle et validation intermédiaire

### Checkpoint 1 : Liste des Pods statiques
```bash
sudo ls -l /etc/kubernetes/manifests/
kubectl get pods -n kube-system
```
*Vérifiez la présence de `kube-apiserver`, `kube-controller-manager`, `kube-scheduler` et `etcd`.*

### Checkpoint 2 : Santé etcd
```bash
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
```
*Le statut retourné doit être `is healthy`.*

### Checkpoint 3 : Diagnostic du Pod en attente
*À réaliser pendant l'exercice 4, **avant** de rétablir le scheduler (étape 6).*
```bash
kubectl get pod scheduler-probe -o wide
kubectl describe pod scheduler-probe
```
*Le champ `Node:` doit être `<none>` et aucun événement `Scheduled` ne doit apparaître.*

---

## 7. Indices progressifs

<details>
<summary>Indice 1 — Comment la kubelet gère-t-elle les manifestes statiques ?</summary>

La kubelet surveille en continu le dossier `/etc/kubernetes/manifests`. Dès qu'un fichier YAML y est ajouté, modifié ou supprimé, la kubelet crée ou détruit le conteneur correspondant sans passer par l'API Server.
</details>

<details>
<summary>Indice 2 — Quels drapeaux TLS sont requis par etcdctl ?</summary>

etcd n'écoute pas en HTTP clair. Il exige une authentification mutuelle (mTLS) :
`--cacert=/etc/kubernetes/pki/etcd/ca.crt`
`--cert=/etc/kubernetes/pki/etcd/server.crt`
`--key=/etc/kubernetes/pki/etcd/server.key`
`--endpoints=https://127.0.0.1:2379`
</details>

<details>
<summary>Indice 3 — Pourquoi le Pod est-il en Pending sans message d'erreur de mémoire ou CPU ?</summary>

L'API Server a persisté le Pod dans `etcd`. Mais tant que le `kube-scheduler` n'est pas actif pour calculer un nœud éligible et renseigner `spec.nodeName`, aucune kubelet de worker ne prend en charge l'exécution du conteneur.
</details>

---

## 8. Validation finale

Vérifiez que le Pod `scheduler-probe` est désormais `Running` et qu'un événement `Scheduled` a été enregistré :
```bash
kubectl get pod scheduler-probe -o wide
kubectl get events --field-selector involvedObject.name=scheduler-probe
# Nettoyage
kubectl delete pod scheduler-probe
```

---

## 9. Ce qu'il faut retenir

1. **Persistance vs Réalisation** : L'API Server enregistre l'état désiré dans `etcd`. Le déploiement effectif est ensuite délégué aux contrôleurs spécialisés (le scheduler pour le placement, le kubelet pour l'exécution).
2. **Statut des Pods statiques** : Si le plan de contrôle est instable, le premier réflexe de l'administrateur est de vérifier `/etc/kubernetes/manifests/` et les journaux de la kubelet (`journalctl -u kubelet`).
3. **Lien avec le Portail Horizon Stages** : Dans le prochain atelier, nous déploierons l'application complète. Si un composant reste bloqué en `Pending`, vous saurez immédiatement distinguer un problème d'ordonnancement d'un problème de conteneur.
