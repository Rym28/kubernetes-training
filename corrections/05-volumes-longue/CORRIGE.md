# Corrigé — Atelier 05 (version longue) : Configuration & Stockage Persistant (PV / PVC / PostgreSQL)

> 🔒 **Confidentiel formateur.** À diffuser en fin d'atelier uniquement. Énoncé : `corrections/05-volumes-longue/README.md` (archive de la version longue, avec StorageClass `local-path`). La version en vigueur et son corrigé sont `labs/05-Les Volumes/README.md` et `corrections/05-volumes/CORRIGE.md`.

---

## Étape 0 — Préparer l'environnement

Commandes données dans l'énoncé. Attendu : `campus-postgres` (base de développement `emptyDir`), `campus-backend` en 3 réplicas et `campus-frontend` déployés, avec les Services `postgres`, `campus-backend` et `campus-frontend-svc` (NodePort `30088`). La vérification des logs doit afficher 3 lignes `Started CampusOpsApplication`.

---

## Exercice 1 — Externaliser la configuration avec un ConfigMap

### Étape 1 — Créer le ConfigMap `campus-config`

Commande donnée (une seule ligne, valable en Bash comme en PowerShell). Sortie : `configmap/campus-config created`.

```bash
kubectl get configmap campus-config -o yaml
```

Sortie (extrait) :

```yaml
apiVersion: v1
data:
  JAVA_TOOL_OPTIONS: -XX:MaxRAMPercentage=75
  LOGGING_LEVEL_COM_OKDLAB: INFO
  SERVER_PORT: "8080"
  SPRING_PROFILES_ACTIVE: production
kind: ConfigMap
metadata:
  name: campus-config
  namespace: campus-dev
```

* Les quatre valeurs sont rangées sous la rubrique **`data`** (clés triées par ordre alphabétique). Un ConfigMap n'a pas de `spec` : il ne décrit pas un état désiré, il stocke des données.
* Les valeurs sont **en clair** : n'importe qui ayant le droit de lire le ConfigMap les voit. On n'y range **jamais** de mot de passe : c'est le rôle du Secret (exercice 2).

Erreur fréquente : oublier le `-` final de `kubectl apply -f -`, la commande attend alors un nom de fichier.

### Étape 2 — ConfigMap à partir d'un fichier

```bash
kubectl describe configmap campus-app-props
```

Sortie (extrait) :

```text
Name:         campus-app-props
Namespace:    campus-dev
Data
====
extra-config.properties:
----
campus.feature.registration=enabled
campus.notification.channel=email
campus.max.students=250
```

* Une **seule** clé : le **nom du fichier** (`extra-config.properties`). Sa valeur est **tout le contenu** du fichier.
* `--from-file` sert quand l'application attend un **fichier de configuration complet** (`application.properties`, `nginx.conf`…), qu'on monte ensuite dans le conteneur comme un fichier. `--from-literal` convient à quelques variables d'environnement isolées.

Ce ConfigMap n'est pas utilisé par l'application : il sert seulement à montrer la différence clé/fichier.

Erreur fréquente : créer le fichier sous Windows avec `>` dans PowerShell 5.1 (encodage UTF-16) : la valeur affichée est illisible. L'énoncé demande de le créer avec l'éditeur.

---

## Exercice 2 — Protéger les identifiants avec un Secret

### Étape 1 — Créer le Secret

Commande donnée. Sortie : `secret/campus-db-credentials created`.

* On ne versionne pas ce manifest : il contient le mot de passe, simplement **encodé en base64**, donc lisible par quiconque accède au dépôt Git. C'est pourquoi les starters des labs suivants ne contiennent jamais le Secret : leur étape 0 le recrée par une commande.

Erreur fréquente (Bash) : écrire `--from-literal=POSTGRES_PASSWORD=CampusSecret2026!` sans guillemets simples. Dans un terminal Bash interactif, `!` déclenche l'expansion d'historique (`event not found`). Les guillemets simples l'évitent.

### Étape 2 — Lire et décoder le Secret

```bash
kubectl get secret campus-db-credentials -o yaml
```

Sortie (extrait) :

```yaml
apiVersion: v1
data:
  POSTGRES_DB: Y2FtcHVz
  POSTGRES_PASSWORD: Q2FtcHVzU2VjcmV0MjAyNiE=
  POSTGRES_USER: Y2FtcHVz
kind: Secret
type: Opaque
```

* Les valeurs ne sont pas lisibles directement : elles apparaissent **encodées en base64** (`Y2FtcHVz` = `campus`).
* Le décodage (commande donnée, Bash ou PowerShell) affiche `CampusSecret2026!`.
* Base64 est un **encodage**, pas un chiffrement : il n'y a aucune clé, tout le monde peut décoder. Peuvent lire le mot de passe tous ceux qui ont le droit `get secret` dans le namespace (RBAC, Atelier 07), et quiconque lit `etcd` si les Secrets n'y sont pas chiffrés au repos.

---

## Exercice 3 — Demander du stockage persistant (PV et PVC)

### Étape 1 — La StorageClass du cluster

Sortie de `kubectl get storageclass` sur le cluster AWS :

```text
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  35h
```

* Classe par défaut : `local-path` (mention `(default)`), fournie par l'outil `rancher.io/local-path`, installé à l'Atelier 01 par `setup-addons.sh`.
* `VOLUMEBINDINGMODE` vaut `WaitForFirstConsumer` : le PV n'est créé qu'au moment où un **pod** utilise le PVC.

Sur Minikube : classe `standard (default)`, provisioner `k8s.io/minikube-hostpath`, mode `Immediate`.

### Étape 2 — Créer le PVC

```bash
kubectl apply -f pvc-postgres.yaml
kubectl get pvc pvc-postgres
kubectl get pv
```

Sorties attendues :

```text
NAME           STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc-postgres   Pending                                      local-path     5s

No resources found
```

* Le PVC est **`Pending`** et **aucun PV** n'existe.
* La demande attend parce que le mode `WaitForFirstConsumer` retarde la création du PV jusqu'au premier pod consommateur : `local-path` doit savoir sur quel worker créer le répertoire. Ce n'est **pas** une erreur.
* Mode demandé : `ReadWriteOnce` (lecture/écriture par un seul nœud). Il convient à une base de données : un seul serveur PostgreSQL doit écrire dans ses fichiers à la fois.

`kubectl describe pvc pvc-postgres` affiche l'événement `WaitForFirstConsumer` : `waiting for first consumer to be created before binding`.

---

## Exercice 4 — Déployer PostgreSQL avec son volume et son Secret

### Étape 1 — Lire le manifest PostgreSQL

* Le conteneur lit `POSTGRES_PASSWORD` (comme `POSTGRES_DB` et `POSTGRES_USER`) dans le Secret `campus-db-credentials`, via `valueFrom.secretKeyRef`. Le mot de passe **n'apparaît pas** dans le fichier.
* `volumes` (niveau pod) déclare **quel** stockage : le PVC `pvc-postgres`. `volumeMounts` (niveau conteneur) indique **où** le brancher : `/var/lib/postgresql/data`. Le champ **`name`** (`donnees`) relie les deux.
* Par rapport au starter, la source du volume passe de `emptyDir: {}` à `persistentVolumeClaim: claimName: pvc-postgres`.

`PGDATA=/var/lib/postgresql/data/pgdata` place les données dans un **sous-répertoire** du volume : PostgreSQL refuse d'initialiser une base dans un répertoire non vide (certains stockages y créent `lost+found`).

### Étape 2 — Appliquer le déploiement

```bash
kubectl apply -f postgres-deployment.yaml
kubectl rollout status deployment/campus-postgres
kubectl get endpoints postgres
kubectl logs -l app=campus-postgres --tail=20
```

* `rollout status` attend le nouveau pod. Avec `Recreate`, l'ancien pod s'arrête d'abord : pendant quelques secondes, il n'y a plus de base.
* `kubectl get endpoints postgres` affiche une seule adresse `<IP-du-nouveau-pod>:5432` : le sélecteur `app=campus-postgres` du Service désigne automatiquement le nouveau pod.
* La base est prête quand les logs affichent `database system is ready to accept connections`. Au premier démarrage, PostgreSQL initialise d'abord le répertoire (`initdb`) avec un serveur temporaire : la phrase peut apparaître deux fois dans les logs complets, la dernière est celle qui compte. Avec `--tail=20`, on n'en voit en général qu'une (constaté en préparation).

Erreur fréquente : PVC créé dans un autre namespace (`default`) : le pod reste `Pending` avec `persistentvolumeclaim "pvc-postgres" not found`.

### Étape 3 — Observer le volume créé

```bash
kubectl get pvc pvc-postgres
kubectl get pv
kubectl get pods -l app=campus-postgres -o wide
```

Sorties attendues :

```text
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc-postgres   Bound    pvc-3f2a…                                  1Gi        RWO            local-path     3m

NAME        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                     STORAGECLASS   AGE
pvc-3f2a…   1Gi        RWO            Delete           Bound    campus-dev/pvc-postgres   local-path     1m
```

* Le PVC est **`Bound`**.
* Le PV (nom généré `pvc-<uid>`) : `1Gi`, `RWO`, politique `Delete`, lié à `campus-dev/pvc-postgres`.
* Le pod PostgreSQL tourne sur l'un des workers (colonne `NODE`). Le PV `local-path` est un **répertoire sur le disque de ce worker** (`/opt/local-path-provisioner/…`) : le PV porte une affinité de nœud, et le pod ne peut plus être placé ailleurs. Si ce worker tombe, la base ne redémarre pas.

---

## Exercice 5 — Reconnecter le backend et prouver la persistance

### Étape 1 — Reconfigurer le backend

* `envFrom` + `configMapRef` injecte **toutes** les clés du ConfigMap comme variables d'environnement, d'un coup. `env` + `secretKeyRef` choisit **une** clé précise du Secret et lui donne le nom de variable voulu (`POSTGRES_PASSWORD` → `SPRING_DATASOURCE_PASSWORD`).
* Oui, le fichier peut être versionné : il ne contient que des **références** (`campus-config`, `campus-db-credentials`), aucune valeur sensible.

```bash
kubectl apply -f deployment-backend.yaml
kubectl rollout status deployment/campus-backend
```

Linux / macOS :
```bash
kubectl logs -l app=campus-backend --prefix --tail=-1 | grep "Started CampusOpsApplication"
```

Windows (PowerShell) :
```powershell
kubectl logs -l app=campus-backend --prefix --tail=-1 | Select-String "Started CampusOpsApplication"
```

* **2 lignes** : le Deployment est passé à 2 réplicas, et les deux pods ont démarré avec le nouveau mot de passe.

Erreur fréquente : appliquer le backend **avant** le Secret. Les pods restent en `CreateContainerConfigError` (`secret "campus-db-credentials" not found`). Créer le Secret suffit : le kubelet réessaie tout seul.

### Étape 2 — Écrire des données de test

Sorties attendues :

```text
CREATE TABLE
INSERT 0 2

 id |     nom
----+--------------
  1 | Alice Dubois
  2 | Bob Martin
(2 rows)
```

* La table contient **2 lignes**.
* `kubectl exec deployment/campus-postgres` choisit **un pod du Deployment** (ici le seul) : pratique quand on ne connaît pas le nom généré du pod.

`psql` se connecte par le socket local du conteneur, sans mot de passe : l'image officielle autorise les connexions locales (`trust`).

### Étape 3 — Crash-test

```bash
kubectl delete pod -l app=campus-postgres
kubectl get pods -l app=campus-postgres -w
```

* Le nouveau pod porte un **nouveau nom** (`campus-postgres-<hash>-<autre suffixe>`).
* Le **ReplicaSet** du Deployment l'a recréé pour revenir à `replicas: 1` (Self-Healing, Atelier 03).

### Étape 4 — Vérifier la survie des données

```bash
kubectl exec deployment/campus-postgres -- psql -U campus -d campus -c "SELECT * FROM test_candidats;"
```

* Les deux lignes `Alice Dubois` et `Bob Martin` sont toujours là.
* Le pod a été détruit, mais le **PVC** et son **PV** (le répertoire sur le worker) existent toujours : le nouveau pod a remonté le même volume. Avec l'`emptyDir` du starter, le volume naît et meurt avec le pod : la table aurait disparu (`relation "test_candidats" does not exist`).

Si la commande renvoie `error: unable to upgrade connection` ou `container not found`, le nouveau pod n'est pas encore prêt : attendre `1/1 Running`.

---

## Récapitulatif — Manifests de fin de lab

Les manifests `pvc-postgres.yaml`, `postgres-deployment.yaml` et `deployment-backend.yaml` sont ceux de l'énoncé, sans modification. ⚠️ Cette version longue n'est **pas** compatible avec les starters actuels des Ateliers 06 et 07, qui contiennent le PV manuel `pv-postgres` et un PVC `storageClassName: ""` : après cette version, `kubectl apply` du starter 06 échoue sur le PVC (champ immuable). Avant l'Atelier 06, repartir de zéro (`kubectl delete namespace campus-dev`).
