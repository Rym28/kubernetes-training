
# Corrigé — Atelier 03 : Déploiements — Résilience, Rollback & Scheduling

> 🔒 **Confidentiel formateur.** À diffuser en fin d'atelier uniquement. Énoncé : `labs/03-Les Deploiements & Scheduling/README.md`.

---

## Étape 0 — Préparer l'environnement

Commandes données dans l'énoncé. Attendu : `deployment.apps/campus-postgres` à `1/1`, un pod `campus-postgres-…` en `1/1 Running` et le Service `postgres` (ClusterIP, port 5432).

---

## Exercice 1 — Créer le Deployment du backend

### Étape 1 — Générer le squelette

```bash
kubectl create deployment campus-backend --image=regaieg/campus:backend-1.0.0 --replicas=2 --port=8080 --dry-run=client -o yaml > deployment-backend.yaml
```

Windows PowerShell 5.1 :
```powershell
kubectl create deployment campus-backend --image=regaieg/campus:backend-1.0.0 --replicas=2 --port=8080 --dry-run=client -o yaml | Out-File -Encoding utf8 deployment-backend.yaml
```

* `--dry-run=client` : `kubectl` construit l'objet mais ne l'envoie pas au cluster. `-o yaml` affiche le résultat.
* `kubectl get pods -l app=campus-backend` renvoie `No resources found in campus-dev namespace.` : le dry-run n'a rien créé. Les pods n'apparaissent qu'après l'`apply` de l'étape 4.

### Étape 2 — Lire le manifest généré

* Nombre d'instances : `spec.replicas: 2`.
* Le label `app: campus-backend` apparaît sous `spec.selector.matchLabels` et sous `spec.template.metadata.labels`. Il est **ajouté automatiquement** par `kubectl create deployment`, qui utilise `app: <nom du deployment>`. Les deux valeurs doivent être identiques, sinon l'API Server refuse le manifest (`selector does not match template labels`).
* `spec.template` est le **modèle de pod** : son contenu (`metadata.labels` + `spec.containers`) ressemble au manifest de Pod de l'Atelier 02, sans `apiVersion`, sans `kind` et sans `name`. Le nom est généré pour chaque copie (`campus-backend-<hash>-<suffixe>`).
* Le conteneur s'appelle `campus` : `kubectl` l'a déduit du nom de l'image `regaieg/campus`.

Erreur fréquente : croire que le dry-run « crée » le Deployment. Il ne fait que générer du texte.

### Étape 3 — Manifest complété

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: campus-backend
  name: campus-backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: campus-backend
  template:
    metadata:
      labels:
        app: campus-backend
    spec:
      containers:
      - name: campus-backend
        image: regaieg/campus:backend-1.0.0
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:postgresql://postgres:5432/campus"
        - name: SPRING_DATASOURCE_USERNAME
          value: "campus"
        - name: SPRING_DATASOURCE_PASSWORD
          value: "campus"
```

Le squelette généré contient aussi `creationTimestamp: null` dans les `metadata` : il est sans effet, on peut le laisser ou le supprimer.

Erreurs fréquentes : `env` placé au niveau de `containers` au lieu de sous le conteneur, tiret manquant devant `- name:`, conteneur non renommé (l'étape 1 de l'exercice 4 échoue alors avec `unable to find container named "campus-backend"`).

### Étape 4 — Appliquer

```bash
kubectl apply -f deployment-backend.yaml
```

### Étape 5 — Observer la chaîne Deployment → ReplicaSet → Pods

```bash
kubectl get deployments
kubectl get rs
kubectl get pods -l app=campus-backend -o wide
kubectl logs -l app=campus-backend --tail=5
```

* Noms : le ReplicaSet s'appelle `campus-backend-<hash>` (le hash est calculé à partir du `template`), et chaque pod `campus-backend-<hash>-<suffixe>`. On lit ainsi la filiation Deployment → ReplicaSet → Pod.
* 2 pods `Running`, en général un sur chaque worker : le Scheduler répartit spontanément les pods d'un même ReplicaSet quand c'est possible. Aucun sur `k8s-control` : sa taint `node-role.kubernetes.io/control-plane:NoSchedule`, posée par kubeadm, refuse les pods applicatifs.
* `kubectl logs -l …` lit les logs de tous les pods qui portent le label.

---

## Exercice 2 — Self-Healing et mise à l'échelle

### Étape 1 — Simuler une panne

```bash
kubectl delete pod <nom-du-pod>
```

### Étape 2 — Observer la réconciliation

```bash
kubectl get pods -l app=campus-backend
```

* On voit toujours 2 pods (parfois 3 pendant quelques secondes, l'ancien étant `Terminating`). L'un d'eux a un `AGE` de quelques secondes : c'est un **nouveau** pod, avec un nouveau nom, pas l'ancien redémarré.
* C'est le contrôleur **ReplicaSet** qui l'a recréé : il constate 1 pod réel pour `replicas: 2` désirés et comble l'écart à partir du `template`. C'est la boucle de réconciliation (observer → comparer → agir), principe du **Self-Healing**.
* À l'Atelier 02, un pod créé seul supprimé disparaissait définitivement : aucun contrôleur ne le surveillait.

### Étape 3 — Monter en charge (impératif)

```bash
kubectl scale deployment campus-backend --replicas=4
kubectl get pods -l app=campus-backend
kubectl get rs
```

* 2 nouveaux pods apparaissent.
* Le ReplicaSet garde le **même nom** : changer `replicas` ne modifie pas le `template`, donc pas de nouvelle révision.

### Étape 4 — Redescendre (déclaratif)

Fichier : `replicas: 3`, puis :
```bash
kubectl apply -f deployment-backend.yaml
kubectl get pods -l app=campus-backend
```

* 3 pods restent. Le ReplicaSet supprime en priorité les pods non prêts ou non placés, puis en général les plus récents.
* Avant l'`apply`, le fichier disait `2`, le cluster `4` : ils divergeaient. Le fichier versionné (Git) est la **source de vérité** partagée par l'équipe : une commande impérative comme `scale` n'est tracée nulle part et sera écrasée au prochain `apply` du fichier.

---

## Exercice 3 — Paramétrer et suivre un Rolling Update

### Étape 1 — Stratégie

```yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```

```bash
kubectl apply -f deployment-backend.yaml
```

* Maximum simultané : `replicas + maxSurge` = 3 + 1 = **4** pods.
* Minimum disponible : `replicas − maxUnavailable` = 3 − 0 = **3** pods.
* Ordre : avec `maxUnavailable: 0`, Kubernetes ne peut supprimer aucun ancien pod tant qu'un nouveau n'est pas prêt. Il **crée d'abord** un nouveau pod (grâce à `maxSurge: 1`), attend qu'il soit prêt, supprime un ancien, et recommence.
* Nuance sur « prêt » : le pod n'a pas encore de `readinessProbe`. « Prêt » signifie donc seulement « conteneur démarré », même si Spring Boot n'écoute pas encore sur le port 8080. Les sondes, ajoutées dans les starters des Ateliers 06 et 07, rendent ce critère fiable.
* Modifier `strategy` ne touche pas au `template` : pas de nouvelle révision, aucun pod remplacé.

### Étape 2 — Livrer une nouvelle version

* `kubectl set env` modifie le `template` : nouvelle révision (révision 2), nouveau ReplicaSet.
* Réappliquer la même image `backend-1.0.0` ne déclencherait **rien** : le `template` désiré serait identique au `template` actuel, il n'y a aucun écart à corriger.

  ```bash
  kubectl set image deployment/campus-backend campus-backend=regaieg/campus:backend-1.0.0
  kubectl rollout history deployment/campus-backend
  ```

  Aucun rollout ne démarre et l'historique ne gagne aucune révision.
* L'`annotate` ne modifie que les `metadata` du Deployment, pas le `template` : il ne crée pas de révision. Le contrôleur recopie l'annotation sur le nouveau ReplicaSet, d'où le `CHANGE-CAUSE` de la révision 2 dans l'Exercice 4.

### Étape 3 — Suivre le rolling update

```bash
kubectl rollout status deployment/campus-backend
kubectl get rs -l app=campus-backend
```

Sortie typique de `rollout status` :

```text
Waiting for deployment "campus-backend" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "campus-backend" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "campus-backend" rollout to finish: 1 old replicas are pending termination...
deployment "campus-backend" successfully rolled out
```

Le rollout est souvent déjà terminé quand le stagiaire tape la commande. Seule la dernière ligne s'affiche alors : c'est normal.

* Le filtre `-l app=campus-backend` fonctionne parce que les ReplicaSets reprennent les labels du `template` (plus un label `pod-template-hash`). Sans filtre, on verrait aussi le ReplicaSet de `campus-postgres`.
* 2 ReplicaSets : le nouveau à `3/3`, l'ancien à `0/0`.
* L'ancien est conservé (vide) pour permettre un **retour arrière** instantané : il garde le `template` de la révision précédente. Le nombre d'anciens ReplicaSets conservés est réglé par `spec.revisionHistoryLimit` (10 par défaut).

---

## Exercice 4 — Gérer un incident de livraison et revenir en arrière

### Étape 1 — Provoquer l'incident

Commandes données. Nouvelle révision 3, avec l'image inexistante.

### Étape 2 — Observer l'incident

```bash
kubectl get pods -l app=campus-backend -w
```

* Le nouveau pod passe en `ErrImagePull` puis `ImagePullBackOff` : le kubelet ne trouve pas l'image et réessaie avec un délai croissant (comme à l'Atelier 02).
* Les **3 anciens pods** restent `Running` : 4 pods au total. Les utilisateurs ne subissent **aucune coupure**.
* Explication : `maxUnavailable: 0` interdit de supprimer un ancien pod tant qu'un nouveau n'est pas prêt. Le nouveau ne le devient jamais, donc le rolling update reste bloqué, sans casse.
* Avec `maxUnavailable: 1` : Kubernetes aurait pu supprimer un ancien pod tout de suite et créer jusqu'à 2 nouveaux pods (tous deux en échec). Il serait resté 2 pods sains sur 3 : pas de coupure totale, mais une capacité réduite d'un tiers pendant tout l'incident.

### Étape 3 — Historique des révisions

```bash
kubectl rollout history deployment/campus-backend
kubectl rollout history deployment/campus-backend --revision=1
```

| Révision | `CHANGE-CAUSE` |
| :--- | :--- |
| 1 | `<none>` |
| 2 | `Livraison 1.0.1 : variable CAMPUS_RELEASE` |
| 3 | `Livraison erronée : backend-invalid-tag` |

* La révision 1 affiche `<none>` : elle a été créée avant toute annotation `kubernetes.io/change-cause`.
* Détail de la révision 1 : image `regaieg/campus:backend-1.0.0`, uniquement les 3 variables `SPRING_DATASOURCE_*` (pas de `CAMPUS_RELEASE`).

### Étape 4 — Rollback

```bash
kubectl rollout undo deployment/campus-backend
```

* Sans option, `undo` revient à la révision **précédente**, c'est-à-dire la 2, pas la 1.
* Version en service : image `backend-1.0.0` **avec** `CAMPUS_RELEASE=1.0.1`. Pour revenir à la version d'origine : `kubectl rollout undo deployment/campus-backend --to-revision=1`.

### Étape 5 — Vérifier la résolution

```bash
kubectl rollout status deployment/campus-backend
kubectl get pods -l app=campus-backend
kubectl rollout history deployment/campus-backend
```

* 3 pods sains `Running`, le pod en `ImagePullBackOff` a disparu.
* L'historique affiche les révisions 1, 3 et **4** : la révision restaurée prend un **nouveau numéro** (4), et la révision 2 disparaît de la liste, puisqu'elle est devenue la 4.

---

## État attendu de `deployment-backend.yaml` en fin de l'Atelier 03

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: campus-backend
  name: campus-backend
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: campus-backend
  template:
    metadata:
      labels:
        app: campus-backend
    spec:
      containers:
      - name: campus-backend
        image: regaieg/campus:backend-1.0.0
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:postgresql://postgres:5432/campus"
        - name: SPRING_DATASOURCE_USERNAME
          value: "campus"
        - name: SPRING_DATASOURCE_PASSWORD
          value: "campus"
```

Les starters des labs suivants partent de cet état et y ajoutent un bloc `podAntiAffinity` (`preferredDuringSchedulingIgnoredDuringExecution`, `topologyKey: kubernetes.io/hostname`) qui répartit les réplicas sur les workers.
