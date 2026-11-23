# Atelier 05 : Configuration & Stockage Persistant (PV / PVC / PostgreSQL)

### Objectifs Pédagogiques :
* Découpler la configuration du code applicatif à l'aide des **ConfigMaps** (par variables directes et injection globale `envFrom`).
* Sécuriser les mots de passe et identifiants sensibles avec les **Secrets** Kubernetes.
* Distinguer le `PersistentVolume` (PV, l'offre de stockage) du `PersistentVolumeClaim` (PVC, la demande), et brancher un PVC dans un pod à la place d'un volume `emptyDir`.
* Déployer une base de données relationnelle **PostgreSQL** avec stockage persistant.
* Connecter l'API Spring Boot `campus-backend` à la base de données.
* Réaliser un crash-test de persistance démontrant la survie des données après suppression du pod de base de données.

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Compatibilité OS</strong></p>

Les commandes de cet atelier sont **identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)**, sauf le décodage base64 de l'étape 1 de l'exercice 2 et la vérification des logs de l'étape 3 de l'exercice 5 : les deux variantes sont fournies. Toutes les commandes tiennent sur **une seule ligne** : elles fonctionnent telles quelles dans PowerShell.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Environnement : le cluster 3 nœuds (1 control plane + 2 workers) de l'Atelier 01</strong></p>

Réalisez ce lab sur ce cluster, piloté au choix :

* **Option A (Recommandée - Confort DevOps Local) :** depuis votre machine locale, avec votre `kubectl` et votre `kubeconfig`. Dans **chaque nouveau terminal**, placé à la racine du dépôt, pointez d'abord `kubectl` vers le fichier `kubeconfig.yaml` récupéré à l'étape 1 de l'exercice 4 de l'Atelier 01 :
    * Windows (PowerShell) : `$env:KUBECONFIG = "$PWD\labs\01-Installation-Cluster\terraform\kubeconfig.yaml"`
    * Linux / macOS (Bash) : `export KUBECONFIG=$PWD/labs/01-Installation-Cluster/terraform/kubeconfig.yaml`
    * Vérification : `kubectl get nodes` doit afficher les 3 nœuds à l'état `Ready`.
* **Option B (PC d'entreprise verrouillé) :** en SSH sur `k8s-control` : l'outillage et les manifests sont pré-installés dans `~/labs/`.

🛟 **Secours : Minikube sur votre poste** (session AWS indisponible), piloté forcément depuis votre poste comme en Option A. Tout fonctionne à l'identique : le PV fourni prévoit aussi le nœud `minikube`.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Namespace de travail : <code>campus-dev</code></strong></p>

Ce lab est **indépendant des autres** : son étape 0 crée `campus-dev` s'il n'existe pas encore, puis y installe ou met à jour tout ce dont il a besoin. Vous pouvez le réaliser sans avoir fait les labs précédents ; pour le recommencer à zéro, utilisez l'encadré « Repartir de zéro » de l'étape 0.

</div>

---

## Contexte Métier
Notre API s'appuie sur une base PostgreSQL de **développement** (`01-postgres-dev.yaml`, la base utilisée depuis l'Atelier 03) qui cumule deux défauts rédhibitoires en production :

* son mot de passe est écrit **en clair** dans le manifest, donc dans le dépôt Git ;
* ses données vivent dans un volume `emptyDir` : **toutes les candidatures disparaissent** à la moindre recréation du pod.

Dans cet atelier, vous externalisez la configuration (ConfigMap), protégez les identifiants (Secret) et rendez la base persistante (PVC), puis vous le prouvez par un crash-test.

<div class="admonition tip" markdown>
<p class="admonition-title"><strong>Mode d'emploi</strong></p>

* Les encadrés rouges **« À vous de répondre »** contiennent les questions. Pour les commandes déjà vues dans les labs précédents, on vous demande la commande au lieu de vous la donner : cherchez avec `kubectl --help`, `kubectl <commande> --help` ou `kubectl explain`.
* Les commandes nouvelles sont données : copiez-les. Les manifests sont **fournis** dans le dossier `labs/05-Les Volumes/manifests/` : vous les lisez et les appliquez, sans les recopier.
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

Créez le namespace `campus-dev` s'il n'existe pas encore, sélectionnez-le, puis appliquez le starter. Si vous sortez du lab précédent, vos objets sont conservés et simplement mis à jour. Depuis la racine du dépôt (Option A) ou depuis `~` sur `k8s-control` (Option B : mettez d'abord le dépôt à jour avec `git -C ~/formation pull`, puis remplacez `labs/` par `~/labs/` dans toutes les commandes de l'atelier) :

```bash
kubectl create namespace campus-dev --dry-run=client -o yaml | kubectl apply -f -   # sans effet s'il existe déjà
kubectl config set-context --current --namespace=campus-dev
kubectl apply -f "labs/05-Les Volumes/starter/"
```

Inutile d'attendre la fin du démarrage de l'API : le backend sera reconfiguré à l'exercice 5, et vous vérifierez alors qu'il démarre. Passez directement à l'exercice 1.

<details class="warning" markdown>
<summary><strong>Environnement incohérent ou lab à recommencer ? Repartez de zéro</strong></summary>

Supprimez le namespace et tout son contenu, ainsi que le PV de la base, puis relancez les commandes ci-dessus :

```bash
kubectl delete namespace campus-dev   # ⚠️ supprime tout le contenu de campus-dev
kubectl delete pv pv-postgres --ignore-not-found   # le PV n'appartient à aucun namespace
```

*La suppression peut prendre jusqu'à une minute : `kubectl` rend la main quand elle est terminée. Les données de la base restent sur le disque du worker : à l'étape 1 de l'exercice 5, `CREATE TABLE` signalera alors que la table existe déjà, sans gravité.*

</details>

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

1. Quelle commande affiche le ConfigMap `campus-config` au **format YAML** ? Sous quelle rubrique du manifest sont rangées les quatre valeurs ?
2. Les valeurs sont-elles lisibles en clair ? Pourrait-on y ranger un mot de passe ?

</div>

### Étape 2 : Créer un ConfigMap à partir d'un fichier

On injecte aussi très souvent des **fichiers de configuration entiers** (`application.properties`, `nginx.conf`…). Le fichier `manifests/extra-config.properties` contient trois lignes :

```properties
campus.feature.registration=enabled
campus.notification.channel=email
campus.max.students=250
```

Créez un second ConfigMap à partir de ce fichier :

```bash
kubectl create configmap campus-app-props --from-file="labs/05-Les Volumes/manifests/extra-config.properties" --dry-run=client -o yaml | kubectl apply -f -
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

### Étape 1 : Créer, lire et décoder le Secret `campus-db-credentials`

Créez un Secret de type `generic` nommé `campus-db-credentials` avec les identifiants de la base :

| Clé | Valeur |
| :--- | :--- |
| `POSTGRES_DB` | `campus` |
| `POSTGRES_USER` | `campus` |
| `POSTGRES_PASSWORD` | `CampusSecret2026!` |

```bash
kubectl create secret generic campus-db-credentials --from-literal=POSTGRES_DB=campus --from-literal=POSTGRES_USER=campus --from-literal='POSTGRES_PASSWORD=CampusSecret2026!' --dry-run=client -o yaml | kubectl apply -f -
```

Affichez le Secret au **format YAML** (même commande que pour le ConfigMap), puis décodez le mot de passe :

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

1. Contrairement à un Deployment, on n'enregistre pas ce manifest dans un fichier du dépôt. Pourquoi ?
2. Quelle commande affiche le Secret au format YAML ? Les valeurs sont-elles lisibles en clair ? Sous quelle forme apparaissent-elles ?
3. Quel mot de passe obtenez-vous au décodage ?
4. L'encodage base64 est-il un chiffrement ? Qui peut lire ce mot de passe ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : comment protège-t-on vraiment un Secret ?</strong></summary>

Base64 n'est qu'un **encodage** : n'importe qui peut le décoder, comme vous venez de le faire. Un Secret est protégé par les **droits d'accès** (RBAC : qui a le droit de faire `get secret`, Atelier 07) et, en production, par le **chiffrement au repos** dans `etcd` ou un coffre-fort externe (HashiCorp Vault, AWS Secrets Manager via le pilote CSI Secrets Store).

</details>

---

## Exercice 3 : Offrir et demander du stockage persistant (PV et PVC)

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un pod est **éphémère** : les données écrites dans un volume `emptyDir` disparaissent avec lui. Pour les conserver, on branche un volume qui stocke les données **en dehors** du pod. Kubernetes sépare l'offre de stockage et la demande :

| Objet | Qui le crée ? | Rôle |
| :--- | :--- | :--- |
| `PersistentVolume` (PV) | L'administrateur (ici, vous) | L'**offre** : un morceau de stockage réel, pour tout le cluster (pas de namespace). |
| `PersistentVolumeClaim` (PVC) | Le développeur (vous aussi) | La **demande** : une taille et un mode d'accès, dans le namespace de l'application. Kubernetes la **lie** à un PV qui convient. |

Le pod ne cite que le PVC : il ignore où se trouve le disque.

</div>

### Étape 1 : Créer le PersistentVolume (l'offre)

Le fichier `manifests/01-pv-postgres.yaml` met à disposition 1 Gio de stockage, dans un répertoire du disque du worker `k8s-worker-1` :

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-postgres
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""                    # PV créé à la main : aucune fabrication automatique
  hostPath:
    path: /mnt/donnees/campus-postgres    # répertoire sur le disque du nœud
    type: DirectoryOrCreate
  nodeAffinity:                           # le disque n'existe que sur ce nœud
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - k8s-worker-1                  # cluster AWS
          - minikube                      # secours Minikube
```

Appliquez-le, puis affichez les PV du cluster.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelles commandes créent le PV, puis l'affichent ?
2. Quels sont sa capacité, son mode d'accès et sa politique de libération (`RECLAIM POLICY`) ? Quel est son statut ?
3. Avez-vous précisé un namespace ? Pourquoi un PV n'en a-t-il pas ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : lire les colonnes d'un PV</strong></summary>

| Colonne | Valeur attendue | Signification |
| :--- | :--- | :--- |
| `CAPACITY` / `ACCESS MODES` | `1Gi` / `RWO` | La taille et le mode d'accès offerts. |
| `RECLAIM POLICY` | `Retain` | Que faire du disque quand le PVC est supprimé : `Retain` garde les données, `Delete` les efface. |
| `STATUS` | `Available` | Cycle de vie d'un PV : `Available` (libre) → `Bound` (lié à un PVC) → `Released` (PVC supprimé). |
| `CLAIM` | *(vide)* | Le PVC auquel il est lié : aucun pour l'instant. |

Un PV est une ressource **du cluster**, comme un nœud : il ne dépend d'aucun namespace, et n'importe quel namespace peut le demander.

</details>

### Étape 2 : Créer le PersistentVolumeClaim (la demande)

Le fichier `manifests/02-pvc-postgres.yaml` demande 1 Gio de stockage :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-postgres
spec:
  storageClassName: ""                    # se lier à un PV existant, sans fabrication automatique
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Appliquez-le, puis affichez le PVC et les PV du cluster en une seule commande :

```bash
kubectl get pvc,pv
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande crée le PVC à partir du fichier fourni ?
2. Quel est maintenant le statut du PVC et du PV ? À quel PVC le PV est-il lié (colonne `CLAIM`) ?
3. Quel mode d'accès demande ce PVC ? Pourquoi convient-il à une base de données ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : les modes d'accès et la liaison</strong></summary>

| Mode d'accès | Signification | Cas d'usage type |
| :--- | :--- | :--- |
| `ReadWriteOnce` (RWO) | Lecture et écriture par un **seul nœud** à la fois. | Bases de données (PostgreSQL, MySQL, MongoDB). |
| `ReadOnlyMany` (ROX) | Lecture seule par **plusieurs nœuds**. | Référentiel de binaires, contenu web statique. |
| `ReadWriteMany` (RWX) | Lecture et écriture par **plusieurs nœuds**. | Partage de fichiers (NFS), uploads partagés. |

Kubernetes lie un PVC à un PV selon trois critères : une **taille suffisante**, le **même mode d'accès**, et **un seul PVC par PV**. Si le PVC reste `Pending`, `kubectl describe pvc pvc-postgres` en donne la raison dans sa section `Events` : le plus souvent, le PV n'a pas été créé.

</details>

---

## Exercice 4 : Déployer PostgreSQL avec son volume et son Secret

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un pod branche un PVC comme n'importe quel volume, et lit ses identifiants dans le Secret : plus aucun mot de passe ni aucune donnée ne vit dans le pod lui-même.

</div>

### Étape 1 : Lire le manifest PostgreSQL

Le fichier `manifests/03-postgres-deployment.yaml`, reproduit ci-dessous, est la version « production » de la base de développement. Il porte le **même nom** (`campus-postgres`) et les **mêmes labels** : Kubernetes mettra à jour le Deployment existant au lieu d'en créer un second.

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

### Étape 2 : Appliquer le déploiement

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande applique `manifests/03-postgres-deployment.yaml` ?
2. Quelle commande attend la fin du remplacement du pod PostgreSQL (vue à l'Atelier 03) ?
3. Le Service `postgres` du starter n'a pas été modifié. Quelle commande (vue à l'Atelier 04) vérifie qu'il envoie bien le trafic au nouveau pod ?
4. Quelle commande affiche les 20 dernières lignes de logs du pod PostgreSQL (label `app=campus-postgres`) ? Quelle phrase indique que la base est prête ? (Au premier démarrage, PostgreSQL initialise la base pendant quelques secondes : si la phrase n'apparaît pas encore, relancez la commande.)

</div>

<div class="admonition warning" markdown>
<p class="admonition-title"><strong>Effet attendu sur le backend</strong></p>

La nouvelle base démarre **vide**, avec le mot de passe du Secret (`CampusSecret2026!`), alors que le backend utilise encore l'ancien mot de passe `campus`. Ses nouvelles connexions échouent (`password authentication failed`) jusqu'à l'étape 3 de l'exercice 5, qui le reconfigure. Les données de la base de développement sont perdues : c'est exactement le défaut d'`emptyDir` que nous corrigeons.

</div>

### Étape 3 : Observer où vivent les données

Affichez le pod PostgreSQL avec son nœud.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Sur quel nœud tourne le pod PostgreSQL ?
2. Pourquoi ne pourra-t-il plus démarrer que sur ce nœud ? (Relisez le PV de l'étape 1 de l'exercice 3.)

</div>

<details class="tip" markdown>
<summary><strong>Indice : un disque attaché à un nœud</strong></summary>

Le PV est un répertoire sur le disque **de `k8s-worker-1`** : sa section `nodeAffinity` oblige tout pod qui l'utilise à tourner sur ce nœud. Les données survivent à la suppression du pod, mais pas à la perte de ce worker. En production, on utilise un stockage réseau ou cloud (NFS, AWS EBS…), accessible depuis n'importe quel nœud.

</details>

<details class="tip" markdown>
<summary><strong>Indice : le pod PostgreSQL reste <code>Pending</code></strong></summary>

`kubectl describe pod -l app=campus-postgres` en donne la raison dans sa section `Events`. Si aucun nœud ne correspond (`didn't match PersistentVolume's node affinity`), vos nœuds ne s'appellent pas `k8s-worker-1` : remplacez ce nom dans `manifests/01-pv-postgres.yaml` par celui d'un de vos workers (`kubectl get nodes`), supprimez le Deployment `campus-postgres`, le PVC et le PV, puis réappliquez les fichiers 01 à 03.

</details>

---

## Exercice 5 : Prouver la persistance et reconnecter le backend

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un crash-test prouve que les données survivent à la destruction du pod. Puis le backend lit désormais sa configuration dans le ConfigMap et ses identifiants dans le Secret.

</div>

### Étape 1 : Écrire des données de test dans PostgreSQL

Créez une table et insérez deux candidats directement dans la base, avec le client `psql` du conteneur, puis relisez la table :

```bash
kubectl exec deployment/campus-postgres -- psql -U campus -d campus -c "CREATE TABLE test_candidats (id SERIAL PRIMARY KEY, nom VARCHAR(100)); INSERT INTO test_candidats (nom) VALUES ('Alice Dubois'), ('Bob Martin');"
```

```bash
kubectl exec deployment/campus-postgres -- psql -U campus -d campus -c "SELECT * FROM test_candidats;"
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Combien de lignes contient la table `test_candidats` ?
2. `kubectl exec deployment/campus-postgres` ne cite aucun nom de pod. Dans quel pod la commande s'exécute-t-elle ?

</div>

### Étape 2 : Crash-test, détruire le pod PostgreSQL et vérifier la survie des données

Simulez une panne en supprimant le pod PostgreSQL, suivez sa recréation, puis relancez la commande `SELECT` de l'étape 1.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande supprime le pod PostgreSQL **à l'aide de son label** `app=campus-postgres` ?
2. Quelle commande suit les pods PostgreSQL **en continu** ? Quittez-la avec `Ctrl + C` quand le nouveau pod est `1/1 Running`.
3. Le nouveau pod porte-t-il le même nom que l'ancien ? Quel composant l'a recréé ?
4. Les deux candidats sont-ils toujours présents ?
5. Qu'est-ce qui a survécu à la destruction du pod ? Que serait-il arrivé avec le volume `emptyDir` du starter ?

</div>

### Étape 3 : Reconfigurer le backend

Le fichier `manifests/04-deployment-backend.yaml` reprend `starter/02-backend.yaml` (partie Deployment) ; seules les sections `envFrom` et `env` changent, et nous revenons à **2 réplicas** pour préserver les ressources des workers :

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

Appliquez-le et attendez la fin du déploiement. L'API n'a pas de sonde de santé : `rollout status` rend la main dès que les conteneurs tournent, avant que Spring Boot ait fini de démarrer (20 secondes à 2 minutes). Répondez aux questions 1 et 2 pendant ce temps, puis vérifiez que chaque pod backend a bien démarré :

**Linux / macOS**

```bash
kubectl logs -l app=campus-backend --prefix --tail=-1 | grep "Started CampusOpsApplication"
```

**Windows (PowerShell)**

```powershell
kubectl logs -l app=campus-backend --prefix --tail=-1 | Select-String "Started CampusOpsApplication"
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle différence faites-vous entre `envFrom` + `configMapRef` et `env` + `secretKeyRef` ?
2. Ce fichier peut-il être versionné dans Git sans risque ? Pourquoi ?
3. Quelles commandes appliquent ce fichier, puis attendent la fin du déploiement ?
4. Relancez la vérification des logs jusqu'à obtenir une ligne par pod : combien de lignes `Started CampusOpsApplication` obtenez-vous ?

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Un redémarrage au démarrage est normal</strong></p>

Les pods créent en même temps les tables de la base neuve : l'un d'eux peut échouer (`relation ... already exists`) avant de repartir.

</div>

---

## Critères de Validation (Checklist)

- [ ] Les paramètres non sensibles sont découplés dans le ConfigMap `campus-config`.
- [ ] Les mots de passe sont protégés dans le Secret `campus-db-credentials`, et vous savez qu'un Secret est encodé en base64, pas chiffré.
- [ ] Le PVC `pvc-postgres` est `Bound` à un PV (`kubectl get pvc,pv`) dont vous savez lire la capacité, le mode d'accès, la politique de libération et le statut.
- [ ] Le Service `postgres` (installé par le starter) pointe vers le nouveau pod PostgreSQL persistant (`kubectl get endpoints postgres`).
- [ ] Le crash-test confirme que les données de `test_candidats` survivent à la suppression du pod PostgreSQL.
- [ ] Le backend `campus-backend` lit sa configuration dans `campus-config` et ses identifiants dans `campus-db-credentials`.
