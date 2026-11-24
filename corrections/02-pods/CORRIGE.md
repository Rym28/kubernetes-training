# Corrigé — Atelier 02 : Les Pods

> 🔒 **Confidentiel formateur.** À diffuser en fin d'atelier uniquement. Énoncé : `labs/02-Les Pods/README.md`.

---

## Exercice 1 — Écrire et créer un Pod

### Étape 1 — Manifest `pod-frontend-test.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: frontend-test
  labels:
    app: frontend-test
    tier: frontend
spec:
  hostAliases:
  - ip: "192.0.2.1"
    hostnames:
    - campus-backend
  containers:
  - name: frontend
    image: regaieg/campus:frontend-1.0.0
    ports:
    - containerPort: 8080
```

Erreurs fréquentes : tabulations, `hostAliases` placé sous `containers`, tiret manquant devant `- name:`.

### Étape 2 — Créer le Pod

```bash
kubectl apply -f pod-frontend-test.yaml
```

### Étape 3 — Suivre le démarrage

```bash
kubectl get pods -w
kubectl get pods -o wide
```

* Statuts : `ContainerCreating` puis `Running`. Pendant `ContainerCreating`, le kubelet télécharge l'image et prépare le conteneur.
* `-o wide` ajoute `NODE` (sur Minikube : `minikube`, le seul nœud, choisi par le scheduler) et `IP` (chaque pod a sa propre adresse IP).

## Exercice 2 — Inspecter le Pod et accéder à l'application

### Étape 1 — Observer les détails

```bash
kubectl describe pod frontend-test
```

* Image, nœud et IP : lignes `Image:`, `Node:` et `IP:`.
* `Events` dans l'ordre : `Scheduled` (scheduler, choix du nœud), `Pulling` / `Pulled` (kubelet, téléchargement de l'image), `Created` / `Started` (kubelet, démarrage du conteneur). C'est le premier réflexe en cas de problème.
* ⚠️ Si l'image est déjà présente sur le nœud (pod recréé, Minikube déjà utilisé), il n'y a pas de `Pulling` : seulement `Pulled … already present on machine`. C'est normal, `imagePullPolicy: IfNotPresent`.

`kubectl get pod frontend-test -o yaml` :

* Ajouts dans `metadata` (API Server) : `uid`, `creationTimestamp`, `resourceVersion`, `namespace: campus-dev`, annotation `kubectl.kubernetes.io/last-applied-configuration`.
* Valeurs par défaut dans `spec` : `restartPolicy: Always`, `imagePullPolicy: IfNotPresent`, `protocol: TCP`, `dnsPolicy: ClusterFirst`, `terminationGracePeriodSeconds: 30`, `serviceAccountName: default`. Le scheduler a aussi écrit `nodeName`.
* La rubrique ajoutée est `status`, tenue à jour par le kubelet. `spec` = **état désiré** (ce que l'on demande), `status` = **état réel** (ce que le cluster constate). La commande `jsonpath` affiche `Running`.

### Étape 2 — Port-forward et logs

* La page **Campus Summer Portal** s'affiche (contenu statique servi par Nginx). Les blocs de données restent vides puis affichent `502 Bad Gateway` : les appels `/api/` partent vers l'adresse fictive `192.0.2.1`, qui ne répond jamais.

```bash
kubectl logs frontend-test --tail=5
```

* On y voit `"GET / HTTP/1.1" 200` et l'erreur `connect() failed … upstream: "http://192.0.2.1:8080/…"`.
* Les logs montrent **ce que fait l'application** ; `describe` montre **ce que fait Kubernetes** (placement, image, démarrage).

## Exercice 3 — Diagnostiquer une erreur classique

### Étape 1 — Erreur d'image

* Statuts : `ErrImagePull`, puis `ImagePullBackOff` (Kubernetes réessaie avec un délai croissant).

```bash
kubectl describe pod frontend-typo
```

* Section `Events` : événement `Failed`, l'image `regaieg/campus:frontend-9.9.9` est introuvable (`not found`).
* `kubectl logs` est inutile : le conteneur n'a jamais démarré, il n'y a aucun log applicatif. La commande renvoie seulement une erreur (`container "frontend-typo" … is waiting to start: trying and failing to pull image`), sans la cause précise.
* Règle à faire retenir au débriefing :
  * `Pending` qui dure, `ErrImagePull`, `ImagePullBackOff` : le conteneur **n'a pas démarré** → `kubectl describe pod`, section `Events`.
  * `CrashLoopBackOff`, `Error` : le conteneur **a démarré puis s'est arrêté** → `kubectl logs` (`--previous` pour les logs du conteneur qui a planté).

## Exercice 4 — Supprimer et rejouer un manifest

### Étape 1 — Supprimer les Pods

```bash
kubectl delete -f pod-frontend-test.yaml
kubectl delete pod frontend-typo
kubectl get pods
```

### Étape 2 — Rejouer le manifest

```bash
kubectl apply -f pod-frontend-test.yaml
kubectl get pods
kubectl delete -f pod-frontend-test.yaml
```

* Le pod revient à l'identique : même nom, mêmes labels, même image, même port, même `hostAliases`.
* Pour recréer `frontend-typo`, il faut retrouver la commande exacte dans l'historique du terminal : rien d'autre ne l'a enregistrée.
* L'approche **déclarative** (fichier) se versionne dans Git et se rejoue. `kubectl run` est une commande qui sera oubliée.

## Exercice 5 — Générer un manifest avec `--dry-run`

### Étape 1 — `--dry-run`

```bash
kubectl get pods   # aucun pod campus-frontend : --dry-run=client n'envoie rien au cluster
```

### Étape 2 — Manifest attendu `pod-frontend.yaml`

* Label généré : `run: campus-frontend`. Champs ajoutés : `resources: {}`, `dnsPolicy`, `restartPolicy`, `status: {}`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: campus-frontend
  name: campus-frontend
spec:
  hostAliases:
  - ip: "192.0.2.1"
    hostnames:
    - campus-backend
  containers:
  - image: regaieg/campus:frontend-1.0.0
    name: campus-frontend
    ports:
    - containerPort: 8080
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
```

### Étape 3 — Appliquer

```bash
kubectl apply -f pod-frontend.yaml
kubectl get pods
```

## Exercice 6 — Entrer dans le conteneur et tester la résilience

### Étape 1 — `kubectl exec`

* `wget` renvoie le début du HTML de la page.
* La dernière ligne de `/etc/hosts` est `192.0.2.1	campus-backend`, ajoutée par `hostAliases`. Nginx vérifie au démarrage que l'hôte `campus-backend` (cible des appels `/api/`) existe ; sans cette ligne, il s'arrête et le pod part en `CrashLoopBackOff`.

### Étape 2 — Crash-test du Pod isolé

```bash
kubectl delete pod campus-frontend
kubectl get pods
```

* Le pod **ne revient pas** : un Pod isolé (*bare pod*) n'est rattaché à aucun contrôleur. S'il plante, meurt ou est supprimé, il est définitivement perdu.
* L'énoncé annonce ensuite les **Deployments** (Atelier 03) : en ouvrant l'atelier 03, on peut montrer que le Deployment (via son ReplicaSet) recrée le pod supprimé.
