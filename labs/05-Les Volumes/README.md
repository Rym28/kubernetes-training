# Lab 05 : Configuration & Stockage Persistant (PV / PVC / PostgreSQL)

### Objectifs Pédagogiques :
* Découpler la configuration du code applicatif à l'aide des **ConfigMaps** (par variables directes et injection globale `envFrom`).
* Sécuriser les mots de passe et identifiants sensibles avec les **Secrets** Kubernetes.
* Distinguer le `PersistentVolume` (PV, l'offre de stockage) du `PersistentVolumeClaim` (PVC, la demande), et brancher un PVC dans un pod à la place d'un volume `emptyDir`.
* Déployer une base de données relationnelle **PostgreSQL** avec stockage persistant.
* Connecter l'API Spring Boot `campus-backend` à la base de données.
* Réaliser un crash-test de persistance démontrant la survie des données après suppression du pod de base de données.

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Compatibilité OS</strong></p>

Les commandes de cet atelier sont **identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)**, sauf le décodage base64 de l'étape 4 : les deux variantes sont fournies. Toutes les commandes tiennent sur **une seule ligne** : elles fonctionnent telles quelles dans PowerShell.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Environnement : le cluster 3 nœuds (1 control plane + 2 workers) du Lab 00</strong></p>

Réalisez ce lab sur ce cluster, piloté au choix :

* **Option A (Recommandée - Confort DevOps Local) :** depuis votre machine locale, avec votre `kubectl` et votre `kubeconfig`. Dans **chaque nouveau terminal**, placé à la racine du dépôt, pointez d'abord `kubectl` vers le fichier `kubeconfig.yaml` récupéré à l'étape 6.1 du Lab 01 :
    * Windows (PowerShell) : `$env:KUBECONFIG = "$PWD\labs\01-Installation-Cluster\terraform\kubeconfig.yaml"`
    * Linux / macOS (Bash) : `export KUBECONFIG=$PWD/labs/01-Installation-Cluster/terraform/kubeconfig.yaml`
    * Vérification : `kubectl get nodes` doit afficher les 3 nœuds à l'état `Ready`.
* **Option B (PC d'entreprise verrouillé) :** en SSH sur `k8s-control` : l'outillage et les manifests sont pré-installés dans `~/labs/`.

🛟 **Secours : Minikube sur votre poste** (session AWS indisponible), piloté forcément depuis votre poste comme en Option A. Tout fonctionne à l'identique ; seul le comportement du PVC à l'étape 6 diffère (un encadré l'indique).

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Namespace de travail : <code>campus-dev</code></strong></p>

Ce lab est **indépendant des autres** : son étape 0 crée `campus-dev` s'il n'existe pas encore, puis y installe ou met à jour tout ce dont il a besoin. Vous pouvez le réaliser sans avoir fait les labs précédents ; pour le recommencer à zéro, utilisez l'encadré « Repartir de zéro » de l'étape 0.

</div>

---

## Contexte Métier
Notre API s'appuie sur une base PostgreSQL de **développement** (`01-postgres-dev.yaml`, la base utilisée depuis le Lab 03) qui cumule deux défauts rédhibitoires en production :

* son mot de passe est écrit **en clair** dans le manifest, donc dans le dépôt Git ;
* ses données vivent dans un volume `emptyDir` : **toutes les candidatures disparaissent** à la moindre recréation du pod.

Dans cet atelier, vous externalisez la configuration (ConfigMap), protégez les identifiants (Secret) et rendez la base persistante (PVC), puis vous le prouvez par un crash-test.

<div class="admonition tip" markdown>
<p class="admonition-title"><strong>Mode d'emploi</strong></p>

* Les encadrés rouges **« À vous de répondre »** contiennent les questions. Pour les commandes déjà vues dans les labs précédents, on vous demande la commande au lieu de vous la donner : cherchez avec `kubectl --help`, `kubectl <commande> --help` ou `kubectl explain`.
* Les commandes nouvelles et les manifests longs sont donnés : copiez-les.
* Les encadrés **« Indice »** sont repliés : cliquez dessus seulement si vous bloquez.

</div>

---

## Étape 0 : Préparer l'environnement

Le dossier `starter/` du lab installe l'application complète dans son état de départ :

| Fichier | Contenu |
| :--- | :--- |
| `01-postgres-dev.yaml` | La base de développement (volume `emptyDir`, mot de passe `campus` en clair) et son Service `postgres`. |
| `02-backend.yaml` | L'API `campus-backend` (3 réplicas, identifiants en clair) et son Service `campus-backend`. |
| `03-frontend.yaml` | Le frontend et son Service NodePort `campus-frontend-svc` (port `30088`). |

Créez le namespace `campus-dev` s'il n'existe pas encore, sélectionnez-le, puis appliquez le starter. Si vous sortez du lab précédent, vos objets sont conservés et simplement mis à jour. Depuis la racine du dépôt (Option A) ou depuis `~` sur `k8s-control` (Option B : mettez d'abord le dépôt à jour avec `git -C ~/formation pull`, puis remplacez `labs/` par `~/labs/`) :

```bash
kubectl create namespace campus-dev --dry-run=client -o yaml | kubectl apply -f -   # sans effet s'il existe déjà
kubectl config set-context --current --namespace=campus-dev
kubectl apply -f "labs/05-Les Volumes/starter/"
kubectl rollout status deployment/campus-backend --timeout=300s
```

<details class="warning" markdown>
<summary><strong>Environnement incohérent ou lab à recommencer ? Repartez de zéro</strong></summary>

Supprimez le namespace et tout son contenu, puis relancez les commandes ci-dessus :

```bash
kubectl delete namespace campus-dev   # ⚠️ supprime tout le contenu de campus-dev
```

*La suppression peut prendre jusqu'à une minute : `kubectl` rend la main quand elle est terminée.*

</details>

L'API n'a pas de sonde de santé : `rollout status` rend la main dès que les conteneurs tournent, avant que Spring Boot ait fini de démarrer (20 secondes à 2 minutes). Vérifiez que chaque pod backend a bien démarré :

**Linux / macOS**

```bash
kubectl logs -l app=campus-backend --prefix --tail=-1 | grep "Started CampusOpsApplication"
```

**Windows (PowerShell)**

```powershell
kubectl logs -l app=campus-backend --prefix --tail=-1 | Select-String "Started CampusOpsApplication"
```

Relancez la commande jusqu'à obtenir **3 lignes**, une par pod backend.

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Un redémarrage au premier lancement est normal</strong></p>

Les pods créent en même temps les tables de la base neuve : l'un d'eux peut échouer (`relation ... already exists`) avant de repartir.

</div>

---

## Exercice 1 : Externaliser la configuration avec un ConfigMap

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un **ConfigMap** range les paramètres non sensibles **hors** de l'image et du manifest de l'application : on change la configuration sans reconstruire ni réécrire le Deployment.

</div>

### Étape 1 : Créer le ConfigMap `campus-config`

Créez un ConfigMap nommé `campus-config` avec les paramètres non sensibles de l'API :

| Clé | Valeur |
| :--- | :--- |
| `SPRING_PROFILES_ACTIVE` | `production` |
| `SERVER_PORT` | `8080` |
| `LOGGING_LEVEL_COM_OKDLAB` | `INFO` |
| `JAVA_TOOL_OPTIONS` | `-XX:MaxRAMPercentage=75` |

La commande génère le manifest avec `--dry-run=client -o yaml` et l'envoie directement à `kubectl apply` (le `-` final signifie « lire le manifest sur l'entrée standard ») :

```bash
kubectl create configmap campus-config --from-literal=SPRING_PROFILES_ACTIVE=production --from-literal=SERVER_PORT=8080 --from-literal=LOGGING_LEVEL_COM_OKDLAB=INFO --from-literal=JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=75 --dry-run=client -o yaml | kubectl apply -f -
```

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Pourquoi <code>JAVA_TOOL_OPTIONS</code> ?</strong></p>

Dans un conteneur, la JVM réserve par défaut seulement 25 % de la limite mémoire au tas (*heap*). Avec une limite de 512 Mi, Spring Boot n'aurait que 128 Mi et risquerait des erreurs `OutOfMemoryError`. Porter ce ratio à 75 % est un réglage classique des applications Java sur Kubernetes.

</div>

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande affiche le ConfigMap `campus-config` au **format YAML** ?
2. Sous quelle rubrique du manifest sont rangées les quatre valeurs ?
3. Les valeurs sont-elles lisibles en clair ? Pourrait-on y ranger un mot de passe ?

</div>

### Étape 2 : Créer un ConfigMap à partir d'un fichier

On injecte aussi très souvent des **fichiers de configuration entiers** (`application.properties`, `nginx.conf`…). Avec votre éditeur, créez un fichier `extra-config.properties` contenant ces trois lignes :

```properties
campus.feature.registration=enabled
campus.notification.channel=email
campus.max.students=250
```

Créez un second ConfigMap à partir de ce fichier :

```bash
kubectl create configmap campus-app-props --from-file=extra-config.properties
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande affiche la description détaillée du ConfigMap `campus-app-props` ?
2. Combien de clés contient-il ? Quel est le nom de la clé, et que contient sa valeur ?
3. Dans quel cas préférez-vous `--from-file` à `--from-literal` ?

</div>

---

## Exercice 2 : Protéger les identifiants avec un Secret

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un **Secret** s'utilise comme un ConfigMap, mais il est réservé aux données sensibles. Attention : ses valeurs sont **encodées** en base64, pas chiffrées.

</div>

### Étape 3 : Créer le Secret `campus-db-credentials`

Créez un Secret de type `generic` nommé `campus-db-credentials` avec les identifiants de la base :

| Clé | Valeur |
| :--- | :--- |
| `POSTGRES_DB` | `campus` |
| `POSTGRES_USER` | `campus` |
| `POSTGRES_PASSWORD` | `CampusSecret2026!` |

```bash
kubectl create secret generic campus-db-credentials --from-literal=POSTGRES_DB=campus --from-literal=POSTGRES_USER=campus --from-literal='POSTGRES_PASSWORD=CampusSecret2026!' --dry-run=client -o yaml | kubectl apply -f -
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Contrairement à un Deployment, on n'enregistre pas ce manifest dans un fichier du dépôt. Pourquoi ?

</div>

### Étape 4 : Lire et décoder le Secret

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande affiche le Secret `campus-db-credentials` au **format YAML** ?
2. Les valeurs sont-elles lisibles en clair ? Sous quelle forme apparaissent-elles ?

</div>

Décodez maintenant le mot de passe :

**Linux / macOS (Bash)**

```bash
kubectl get secret campus-db-credentials -o jsonpath="{.data.POSTGRES_PASSWORD}" | base64 --decode ; echo
```

**Windows (PowerShell)**

```powershell
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((kubectl get secret campus-db-credentials -o jsonpath="{.data.POSTGRES_PASSWORD}")))
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

3. Quel mot de passe obtenez-vous ?
4. L'encodage base64 est-il un chiffrement ? Qui peut lire ce mot de passe ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : comment protège-t-on vraiment un Secret ?</strong></summary>

Base64 n'est qu'un **encodage** : n'importe qui peut le décoder, comme vous venez de le faire. Un Secret est protégé par les **droits d'accès** (RBAC : qui a le droit de faire `get secret`, Lab 07) et, en production, par le **chiffrement au repos** dans `etcd` ou un coffre-fort externe (HashiCorp Vault, AWS Secrets Manager via le pilote CSI Secrets Store).

</details>

---

## Exercice 3 : Demander du stockage persistant (PV et PVC)

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un pod est **éphémère** : les données écrites dans un volume `emptyDir` disparaissent avec lui. Pour les conserver, on branche un volume qui stocke les données **en dehors** du pod. Kubernetes sépare l'offre de stockage et la demande :

| Objet | Qui le crée ? | Rôle |
| :--- | :--- | :--- |
| `PersistentVolume` (PV) | L'administrateur, ou un outil automatique | L'**offre** : un morceau de stockage réel, pour tout le cluster (pas de namespace). |
| `PersistentVolumeClaim` (PVC) | Le développeur (vous) | La **demande** : une taille et un mode d'accès, dans le namespace de l'application. Kubernetes la **lie** à un PV qui convient. |
| `StorageClass` | L'administrateur | Le **fournisseur** qui fabrique automatiquement un PV pour chaque PVC. |

Le pod ne cite que le PVC : il ignore où se trouve le disque.

</div>

### Étape 5 : Découvrir la StorageClass du cluster

Affichez les classes de stockage disponibles :

```bash
kubectl get storageclass
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle classe est utilisée par défaut ? Quel outil (colonne `PROVISIONER`) fabrique les volumes ?
2. Que vaut la colonne `VOLUMEBINDINGMODE` ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : qui crée les PV sur notre cluster ?</strong></summary>

Personne ne les écrit à la main : l'outil `local-path`, installé au Lab 00 (étape 5.4), joue le rôle de l'administrateur. Dès qu'un PVC en a besoin, il crée un PV dans un répertoire du disque d'un worker.

Le mode `WaitForFirstConsumer` signifie « attendre le premier pod qui utilise le PVC » : `local-path` saura alors sur quel worker placer les données.

</details>

### Étape 6 : Créer le PersistentVolumeClaim

Créez le fichier `pvc-postgres.yaml` :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-postgres
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande crée le PVC à partir de ce fichier ?
2. Quelles commandes affichent le PVC `pvc-postgres`, puis les PV du cluster ? Quel est le statut du PVC ? Combien de PV existent ?
3. Pourquoi la demande reste-t-elle en attente ? (Relisez votre réponse à l'étape 5.)
4. Quel mode d'accès demande ce PVC ? Pourquoi convient-il à une base de données ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : les modes d'accès</strong></summary>

| Mode d'accès | Signification | Cas d'usage type |
| :--- | :--- | :--- |
| `ReadWriteOnce` (RWO) | Lecture et écriture par un **seul nœud** à la fois. | Bases de données (PostgreSQL, MySQL, MongoDB). |
| `ReadOnlyMany` (ROX) | Lecture seule par **plusieurs nœuds**. | Référentiel de binaires, contenu web statique. |
| `ReadWriteMany` (RWX) | Lecture et écriture par **plusieurs nœuds**. | Partage de fichiers (NFS), uploads partagés. |

Kubernetes lie un PVC à un PV selon trois critères : une **taille suffisante**, le **même mode d'accès**, et **un seul PVC par PV**.

</details>

<div class="admonition example" markdown>
<p class="admonition-title"><strong>Sur Minikube</strong></p>

La classe `standard` de Minikube crée le PV tout de suite : le PVC est déjà `Bound`. Le résultat final est le même.

</div>

---

## Exercice 4 : Déployer PostgreSQL avec son volume et son Secret

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un pod branche un PVC comme n'importe quel volume, et lit ses identifiants dans le Secret : plus aucun mot de passe ni aucune donnée ne vit dans le pod lui-même.

</div>

### Étape 7 : Lire le manifest PostgreSQL

Créez le fichier `postgres-deployment.yaml` ci-dessous, la version « production » de la base de développement. Il porte le **même nom** (`campus-postgres`) et les **mêmes labels** : Kubernetes mettra à jour le Deployment existant au lieu d'en créer un second.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: campus-postgres
  labels:
    app: campus-postgres
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: campus-postgres
  template:
    metadata:
      labels:
        app: campus-postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: campus-db-credentials
              key: POSTGRES_DB
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: campus-db-credentials
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: campus-db-credentials
              key: POSTGRES_PASSWORD
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: donnees
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: donnees
        persistentVolumeClaim:
          claimName: pvc-postgres
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Où le conteneur lit-il son mot de passe ? Le mot de passe apparaît-il dans ce fichier ?
2. Quelle section déclare **quel** stockage utiliser ? Quelle section indique **où** le brancher dans le conteneur ? Quel champ relie les deux ?
3. Comparez avec `starter/01-postgres-dev.yaml` : côté stockage, quelle ligne a changé ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : lire le branchement du volume</strong></summary>

* `volumes` (niveau pod) déclare **quel** stockage : ici le PVC `pvc-postgres`.
* `volumeMounts` (niveau conteneur) indique **où** le brancher : `/var/lib/postgresql/data`.
* Les deux sont reliés par le **même `name`** (`donnees`).

Dans le starter, la source du volume était `emptyDir: {}` ; elle devient `persistentVolumeClaim`.

</details>

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Pourquoi <code>strategy: Recreate</code> ?</strong></p>

Avec un volume `ReadWriteOnce`, deux pods PostgreSQL ne doivent jamais écrire en même temps sur les mêmes fichiers. `Recreate` arrête l'ancien pod **avant** de démarrer le nouveau (au prix d'une courte coupure), là où `RollingUpdate` ferait coexister les deux.

</div>

### Étape 8 : Appliquer le déploiement

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande applique `postgres-deployment.yaml` ?
2. Quelle commande attend la fin du remplacement du pod PostgreSQL (vue au Lab 03) ?
3. Le Service `postgres` du starter n'a pas été modifié. Quelle commande (vue au Lab 04) vérifie qu'il envoie bien le trafic au nouveau pod ?
4. Quelle commande affiche les 20 dernières lignes de logs du pod PostgreSQL (label `app=campus-postgres`) ? Quelle phrase indique que la base est prête ?

</div>

<div class="admonition warning" markdown>
<p class="admonition-title"><strong>Effet attendu sur le backend</strong></p>

La nouvelle base démarre **vide**, avec le mot de passe du Secret (`CampusSecret2026!`), alors que le backend utilise encore l'ancien mot de passe `campus`. Ses nouvelles connexions échouent (`password authentication failed`) jusqu'à l'étape 10, qui le reconfigure. Les données de la base de développement sont perdues : c'est exactement le défaut d'`emptyDir` que nous corrigeons.

</div>

### Étape 9 : Observer le volume créé automatiquement

Le pod PostgreSQL utilise maintenant le PVC : `local-path` a créé le PV. Affichez à nouveau le PVC et les PV.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quel est maintenant le statut du PVC ?
2. Un PV est apparu : quels sont sa capacité, son mode d'accès et sa politique de libération (`RECLAIM POLICY`) ? À quel PVC est-il lié ?
3. Sur quel nœud tourne le pod PostgreSQL ? Pourquoi ne pourra-t-il plus démarrer que sur ce nœud ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : lire les colonnes d'un PV</strong></summary>

| Colonne | Valeur attendue | Signification |
| :--- | :--- | :--- |
| `CAPACITY` / `ACCESS MODES` | `1Gi` / `RWO` | La taille et le mode d'accès de votre demande. |
| `RECLAIM POLICY` | `Delete` | Que faire du disque quand le PVC est supprimé : `Delete` l'efface, `Retain` garde les données. |
| `STATUS` | `Bound` | Cycle de vie d'un PV : `Available` (libre) → `Bound` (lié à un PVC) → `Released` (PVC supprimé). |
| `CLAIM` | `campus-dev/pvc-postgres` | Le PVC auquel il est lié. |

Avec `local-path`, le PV est un répertoire sur le disque **d'un worker**. Les données survivent à la suppression du pod, mais pas à la perte de ce worker. En production, on utilise un stockage réseau ou cloud (NFS, AWS EBS…), accessible depuis n'importe quel nœud.

</details>

<details class="tip" markdown>
<summary><strong>Indice : le PVC reste <code>Pending</code> alors que le pod PostgreSQL existe</strong></summary>

* Le pod reste lui aussi `Pending` : `kubectl describe pvc pvc-postgres` explique pourquoi dans sa section `Events`.
* Vérifiez que `local-path` est installé : `kubectl get storageclass` doit afficher `local-path (default)`. Sinon, exécutez le script `setup-addons.sh` sur `k8s-control` (Lab 00, étape 5.4).

</details>

---

## Exercice 5 : Reconnecter le backend et prouver la persistance

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Le backend lit désormais sa configuration dans le ConfigMap et ses identifiants dans le Secret. Puis un crash-test prouve que les données survivent à la destruction du pod.

</div>

### Étape 10 : Reconfigurer le backend

Créez le fichier `deployment-backend.yaml` ci-dessous. Il reprend `starter/02-backend.yaml` (partie Deployment) ; seules les sections `envFrom` et `env` changent, et nous revenons à **2 réplicas** pour préserver les ressources des workers :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: campus-backend
spec:
  replicas: 2
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
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app: campus-backend
      containers:
      - name: campus-backend
        image: regaieg/campus:backend-1.0.0
        ports:
        - containerPort: 8080
        envFrom:
        - configMapRef:
            name: campus-config
        env:
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:postgresql://postgres:5432/campus"
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: campus-db-credentials
              key: POSTGRES_USER
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: campus-db-credentials
              key: POSTGRES_PASSWORD
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle différence faites-vous entre `envFrom` + `configMapRef` et `env` + `secretKeyRef` ?
2. Ce fichier peut-il être versionné dans Git sans risque ? Pourquoi ?
3. Quelles commandes appliquent ce fichier, puis attendent la fin du déploiement ?
4. Avec la commande de vérification de l'étape 0, combien de lignes `Started CampusOpsApplication` obtenez-vous ?

</div>

### Étape 11 : Écrire des données de test dans PostgreSQL

Créez une table et insérez deux candidats directement dans la base, avec le client `psql` du conteneur :

```bash
kubectl exec deployment/campus-postgres -- psql -U campus -d campus -c "CREATE TABLE test_candidats (id SERIAL PRIMARY KEY, nom VARCHAR(100)); INSERT INTO test_candidats (nom) VALUES ('Alice Dubois'), ('Bob Martin');"
```

Relisez la table :

```bash
kubectl exec deployment/campus-postgres -- psql -U campus -d campus -c "SELECT * FROM test_candidats;"
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Combien de lignes contient la table `test_candidats` ?
2. `kubectl exec deployment/campus-postgres` ne cite aucun nom de pod. Dans quel pod la commande s'exécute-t-elle ?

</div>

### Étape 12 : Crash-test, détruire le pod PostgreSQL

Simulez une panne en supprimant le pod PostgreSQL.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande supprime le pod PostgreSQL **à l'aide de son label** `app=campus-postgres` ?
2. Quelle commande suit les pods PostgreSQL **en continu** ? Quittez-la avec `Ctrl + C` quand le nouveau pod est `1/1 Running`.
3. Le nouveau pod porte-t-il le même nom que l'ancien ? Quel composant l'a recréé ?

</div>

### Étape 13 : Vérifier la survie des données

Relancez la commande `SELECT` de l'étape 11.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Les deux candidats sont-ils toujours présents ?
2. Qu'est-ce qui a survécu à la destruction du pod ? Que serait-il arrivé avec le volume `emptyDir` du starter ?

</div>

---

## Critères de Validation (Checklist)

- [ ] Les paramètres non sensibles sont découplés dans le ConfigMap `campus-config`.
- [ ] Les mots de passe sont protégés dans le Secret `campus-db-credentials`, et vous savez qu'un Secret est encodé en base64, pas chiffré.
- [ ] Le PVC `pvc-postgres` est `Bound` à un PV (`kubectl get pvc,pv`) dont vous savez lire la capacité, le mode d'accès, la politique de libération et le statut.
- [ ] Le Service `postgres` (installé par le starter) pointe vers le nouveau pod PostgreSQL persistant (`kubectl get endpoints postgres`).
- [ ] Le backend `campus-backend` lit sa configuration dans `campus-config` et ses identifiants dans `campus-db-credentials`.
- [ ] Le crash-test confirme que les données de `test_candidats` survivent à la suppression du pod PostgreSQL.
