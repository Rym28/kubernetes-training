# Lab 05 : Configuration & Stockage Persistant (PV / PVC / PostgreSQL)

### Objectifs Pédagogiques :
* Découpler la configuration du code applicatif à l'aide des **ConfigMaps** (par variables directes et injection globale `envFrom`).
* Sécuriser les mots de passe et identifiants sensibles avec les **Secrets** Kubernetes.
* Distinguer le `PersistentVolume` (PV, l'offre de stockage) du `PersistentVolumeClaim` (PVC, la demande), et brancher un PVC dans un pod à la place d'un volume `emptyDir`.
* Déployer une base de données relationnelle **PostgreSQL** avec stockage persistant.
* Connecter l'API Spring Boot `campus-backend` à la base de données.
* Réaliser un crash-test de persistance démontrant la survie des données après suppression du pod de base de données.

> 📌 **Note Compatibilité OS :**  
> Les commandes de création et d'application des manifests sont **identiques**. Seule la syntaxe de décodage base64 dans le terminal diffère entre PowerShell et Linux/macOS.
>
> 💡 **Modalités d'exécution (Au choix) :**  
> * **Option A (Recommandée - Confort DevOps Local) :** Exécutez les commandes directement depuis votre machine locale avec votre `kubectl` et votre `kubeconfig`.  
> * **Option B (Secours - PC d'entreprise verrouillé) :** Connectez-vous en SSH sur `k8s-control` : l'outillage et les manifests sont pré-installés dans `~/labs/`.
>
> 🗂️ **Namespace de travail : `campus-dev`.** Ce lab est **indépendant des autres** : son étape 0 recrée `campus-dev` à neuf et y installe tout ce dont il a besoin. Vous pouvez le réaliser sans avoir fait les labs précédents, ou le recommencer à tout moment.

---

## Contexte Métier
Notre API s'appuie sur une base PostgreSQL de **développement** (`01-postgres-dev.yaml`, la base utilisée depuis le Lab 03) qui cumule deux défauts rédhibitoires en production :

* son mot de passe est écrit **en clair** dans le manifest, donc dans le dépôt Git ;
* ses données vivent dans un volume `emptyDir` : **toutes les candidatures disparaissent** à la moindre recréation du pod.

Dans cet atelier, vous externalisez la configuration (ConfigMap), protégez les identifiants (Secret) et rendez la base persistante (PVC), puis vous le prouvez par un crash-test.

---

## Étape 0 : Préparer l'environnement

Le dossier `starter/` du lab installe l'application complète dans son état de départ :

| Fichier | Contenu |
| :--- | :--- |
| `01-postgres-dev.yaml` | La base de développement (volume `emptyDir`, mot de passe `campus` en clair) et son Service `postgres`. |
| `02-backend.yaml` | L'API `campus-backend` (3 réplicas, identifiants en clair) et son Service `campus-backend`. |
| `03-frontend.yaml` | Le frontend et son Service NodePort `campus-frontend-svc` (port `30088`). |

Repartez d'un namespace `campus-dev` vide, puis appliquez le starter. Depuis la racine du dépôt (Option A) ou depuis `~` sur `k8s-control` (Option B : mettez d'abord le dépôt à jour avec `git -C ~/formation pull`, puis remplacez `labs/` par `~/labs/`) :

```bash
kubectl delete namespace campus-dev --ignore-not-found   # ⚠️ supprime tout le contenu de campus-dev
kubectl create namespace campus-dev
kubectl config set-context --current --namespace=campus-dev
kubectl apply -f labs/05-configuration-persistance/starter/
kubectl rollout status deployment/campus-backend --timeout=300s
```

*La suppression du namespace peut prendre jusqu'à une minute. Spring Boot met ensuite 20 secondes à 2 minutes à démarrer.*

---

## Exercice 1 : Externaliser la Configuration avec un ConfigMap

### 1. Créer un ConfigMap avec des variables directes
Créez un ConfigMap nommé `campus-config` contenant les paramètres non sensibles de configuration de l'application :
* `SPRING_PROFILES_ACTIVE` : `production`
* `SERVER_PORT` : `8080`
* `LOGGING_LEVEL_COM_OKDLAB` : `INFO`
* `JAVA_TOOL_OPTIONS` : `-XX:MaxRAMPercentage=75`

> 💡 **Pourquoi `JAVA_TOOL_OPTIONS` ?** Dans un conteneur, la JVM réserve par défaut seulement 25 % de la limite mémoire au tas (*heap*). Avec une limite de 512 Mi, Spring Boot n'aurait que 128 Mi et risquerait des erreurs `OutOfMemoryError`. Porter ce ratio à 75 % est un réglage classique des applications Java sur Kubernetes.

```bash
kubectl create configmap campus-config \
  --from-literal=SPRING_PROFILES_ACTIVE=production \
  --from-literal=SERVER_PORT=8080 \
  --from-literal=LOGGING_LEVEL_COM_OKDLAB=INFO \
  --from-literal=JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=75 \
  --dry-run=client -o yaml > configmap.yaml

kubectl apply -f configmap.yaml
```

Inspectez le contenu enregistré dans etcd :

```bash
kubectl get configmap campus-config -o yaml
```

### 2. Créer un ConfigMap à partir d'un fichier de configuration
Il est également très fréquent d'injecter des fichiers de configuration entiers (`application.properties`, `nginx.conf`, etc.).

1. Créez un fichier local `extra-config.properties` (avec votre éditeur, ou en ligne de commande) :
   * **Bash (Linux, macOS, Git Bash, `k8s-control`)** :
     ```bash
     cat << 'EOF' > extra-config.properties
     campus.feature.registration=enabled
     campus.notification.channel=email
     campus.max.students=250
     EOF
     ```
   * **Windows PowerShell** :
     ```powershell
     @"
     campus.feature.registration=enabled
     campus.notification.channel=email
     campus.max.students=250
     "@ | Out-File -Encoding utf8 extra-config.properties
     ```

2. Créez un second ConfigMap depuis ce fichier :
   ```bash
   kubectl create configmap campus-app-props --from-file=extra-config.properties
   kubectl describe configmap campus-app-props
   ```
   *Constatez que le nom du fichier devient la clé, et son contenu devient la valeur !*

---

## Exercice 2 : Sécuriser les Identifiants avec un Secret

### 1. Créer un Secret pour PostgreSQL
Créez un Secret de type `generic` nommé `campus-db-credentials` contenant les identifiants d'accès à la base de données :
* `POSTGRES_DB` : `campus`
* `POSTGRES_USER` : `campus`
* `POSTGRES_PASSWORD` : `CampusSecret2026!`

```bash
kubectl create secret generic campus-db-credentials \
  --from-literal=POSTGRES_DB=campus \
  --from-literal=POSTGRES_USER=campus \
  --from-literal='POSTGRES_PASSWORD=CampusSecret2026!' \
  --dry-run=client -o yaml > secret.yaml

kubectl apply -f secret.yaml
```

### 2. Observer l'encodage Base64
Affichez le Secret au format YAML :

```bash
kubectl get secret campus-db-credentials -o yaml
```

*Remarquez que les valeurs sont encodées en base64 pour éviter l'affichage accidentel en clair dans les logs ou les consoles.*

### 3. Décoder une valeur du Secret

* **Sous Windows (PowerShell)** :
  ```powershell
  # Remplacez <chaine_base64> par la valeur affichée pour POSTGRES_PASSWORD
  [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("<chaine_base64>"))
  ```

* **Sous Linux (Ubuntu) / macOS (Bash)** :
  ```bash
  # Récupération et décodage direct en une commande :
  kubectl get secret campus-db-credentials -o jsonpath="{.data.POSTGRES_PASSWORD}" | base64 --decode ; echo
  ```

> ⚠️ **Sécurité en Production :** L'encodage Base64 n'est pas un chiffrement (n'importe qui peut le décoder). En production d'entreprise, les secrets doivent être chiffrés au repos dans etcd (*Encryption at Rest*) et gérés via des coffres-forts externes comme HashiCorp Vault ou AWS Secrets Manager via le pilote CSI Secrets Store.

---

## Exercice 3 : Demander du Stockage Persistant (PV et PVC)

Un pod est **éphémère** : les données écrites dans le conteneur, ou dans un volume `emptyDir` comme celui de la base de développement, disparaissent avec le pod. Pour les conserver, on branche dans le conteneur un **volume** qui stocke les données **en dehors** du pod. Kubernetes sépare l'offre de stockage et la demande :

| Objet | Qui le crée ? | Rôle |
| :--- | :--- | :--- |
| `PersistentVolume` (PV) | L'administrateur | L'**offre** : un morceau de stockage réel, pour tout le cluster (pas de namespace). Il annonce une taille, des modes d'accès et une politique de libération. |
| `PersistentVolumeClaim` (PVC) | Le développeur (vous) | La **demande** : une taille et un mode d'accès, dans le namespace de l'application. Kubernetes la **lie** automatiquement à un PV qui convient. |

Le pod ne cite que le PVC : il ignore où se trouve le disque.

> 💡 **Qui crée les PV sur notre cluster ?** Personne ne les écrit à la main : l'outil `local-path`, installé au Lab 00 (étape 5.4), joue le rôle de l'administrateur. Dès qu'un PVC en a besoin, il crée un PV dans un répertoire du disque d'un worker.

### 1. Créer le PersistentVolumeClaim
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

Appliquez le PVC :

```bash
kubectl apply -f pvc-postgres.yaml
```

Kubernetes lie un PVC à un PV selon trois critères : une **taille suffisante**, le **même mode d'accès**, et **un seul PVC par PV**. Les modes d'accès possibles :

| Mode d'accès | Signification | Cas d'usage type |
| :--- | :--- | :--- |
| `ReadWriteOnce` (RWO) | Lecture et écriture par un **seul nœud** à la fois. | Bases de données (PostgreSQL, MySQL, MongoDB). |
| `ReadOnlyMany` (ROX) | Lecture seule par **plusieurs nœuds**. | Référentiel de binaires, contenu web statique. |
| `ReadWriteMany` (RWX) | Lecture et écriture par **plusieurs nœuds**. | Partage de fichiers (NFS), uploads partagés. |

### 2. Observer la demande en attente
Affichez le PVC, puis les PV du cluster :

```bash
kubectl get pvc pvc-postgres
kubectl get pv
```

*Le PVC est **`Pending`** et aucun PV n'existe encore (`No resources found`) : tant qu'aucun PV ne convient, la demande attend. Ici, `local-path` ne crée le PV qu'au moment où un pod utilise le PVC, car il saura alors sur quel worker placer les données. Le PV apparaîtra à l'exercice 4.*

> 🛟 **Sur Minikube :** le PV est créé tout de suite et le PVC est déjà `Bound`. Le résultat final est le même.

---

## Exercice 4 : Déployer PostgreSQL avec Volume et Secrets

### 1. Créer le manifest de déploiement PostgreSQL
Créez le fichier `postgres-deployment.yaml`, la version « production » de la base de développement installée à l'étape 0. Il porte le **même nom** (`campus-postgres`) et les **mêmes labels** : Kubernetes mettra donc à jour le Deployment existant au lieu d'en créer un second. Il lie le conteneur PostgreSQL officiel, le Secret et le volume persistant monté sur `/var/lib/postgresql/data` :

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

> 💡 **Lire le branchement du volume :**
> * `volumes` (niveau pod) déclare **quel** stockage : ici le PVC `pvc-postgres`.
> * `volumeMounts` (niveau conteneur) indique **où** le brancher : `/var/lib/postgresql/data`.
> * Les deux sont reliés par le **même `name`** (`donnees`).
>
> Comparez avec `starter/01-postgres-dev.yaml` : côté stockage, seule la source du volume change, `emptyDir: {}` devient `persistentVolumeClaim`.

> 💡 **`strategy: Recreate`** : avec un volume `ReadWriteOnce`, deux pods PostgreSQL ne doivent jamais écrire en même temps sur les mêmes fichiers. `Recreate` arrête l'ancien pod **avant** de démarrer le nouveau (au prix d'une courte coupure), là où `RollingUpdate` ferait coexister les deux.

### 2. Appliquer le déploiement
Appliquez le fichier, puis attendez la fin du remplacement du pod :

```bash
kubectl apply -f postgres-deployment.yaml
kubectl rollout status deployment/campus-postgres
```

*Avec la stratégie `Recreate`, l'ancien pod s'arrête **avant** que le nouveau démarre : pendant quelques secondes, il n'y a plus de base du tout. `rollout status` attend le nouveau pod (un `kubectl wait` sur le label répondrait trop tôt, en trouvant l'ancien pod encore présent).*

Le Service `postgres` installé par le starter n'a pas besoin d'être modifié : son sélecteur `app=campus-postgres` désigne automatiquement le nouveau pod. Vérifiez-le :

```bash
kubectl get endpoints postgres
```

Vérifiez les logs d'initialisation de PostgreSQL :

```bash
kubectl logs -l app=campus-postgres --tail=20
```
*Vous devez voir la mention : `database system is ready to accept connections`. Si elle n'apparaît pas encore, PostgreSQL initialise sa base : relancez la commande quelques secondes plus tard.*

> ⚠️ **Effet attendu sur le backend :** la nouvelle base démarre vide, avec le mot de passe du Secret (`CampusSecret2026!`), alors que le backend utilise encore l'ancien mot de passe `campus`. Ses nouvelles connexions échouent (`password authentication failed`) jusqu'à l'exercice 5, qui le reconfigure. Les données saisies sur la base de développement sont perdues : c'est exactement le défaut d'`emptyDir` que nous corrigeons.

### 3. Observer le volume créé automatiquement
Le pod PostgreSQL utilise maintenant le PVC : `local-path` a créé le PV. Affichez à nouveau le PVC et les PV :

```bash
kubectl get pvc pvc-postgres
kubectl get pv
```

*Le PVC est passé à **`Bound`** et un PV au nom généré (`pvc-…`) est apparu. Lisez ses colonnes :*

| Colonne | Valeur | Signification |
| :--- | :--- | :--- |
| `CAPACITY` / `ACCESS MODES` | `1Gi` / `RWO` | La taille et le mode d'accès de votre demande. |
| `RECLAIM POLICY` | `Delete` | Que faire du disque quand le PVC est supprimé : `Delete` l'efface, `Retain` garde les données. |
| `STATUS` | `Bound` | Cycle de vie d'un PV : `Available` (libre) → `Bound` (lié à un PVC) → `Released` (PVC supprimé). |
| `CLAIM` | `campus-dev/pvc-postgres` | Le PVC auquel il est lié. |

> ⚠️ **Où sont les données ?** Avec `local-path`, le PV est un répertoire sur le disque **d'un worker**, comme un volume `hostPath`. Les données survivent à la suppression du pod (c'est ce que prouve le crash-test de l'exercice 5), mais pas à la perte de ce worker, et le pod PostgreSQL ne peut plus démarrer que sur lui (vérifiez avec `kubectl get pods -l app=campus-postgres -o wide`). En production, on utilise un stockage réseau ou cloud (NFS, AWS EBS…), accessible depuis n'importe quel nœud.

<details>
<summary>💡 <b>Indice : le PVC reste <code>Pending</code> alors que le pod PostgreSQL existe</b></summary>

* Le pod reste lui aussi `Pending` : `kubectl describe pvc pvc-postgres` explique pourquoi dans sa section `Events`.
* Vérifiez que l'outil `local-path` est installé : `kubectl get storageclass` doit afficher `local-path (default)`. Sinon, exécutez le script `setup-addons.sh` sur `k8s-control` (Lab 00, étape 5.4).
</details>

---

## Exercice 5 : Connexion Backend & Crash-Test de Persistance

### 1. Connecter le backend à la base de données
Créez le fichier `deployment-backend.yaml` en partant de `starter/02-backend.yaml` (partie Deployment), pour que le backend lise ses paramètres dans le ConfigMap et le Secret, au lieu de valeurs écrites en clair. Seules les sections `env` et `envFrom` changent ; nous revenons aussi à **2 réplicas** pour préserver les ressources des workers :

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

> 💡 `envFrom` injecte **toutes** les clés du ConfigMap comme variables d'environnement, alors que `env` + `secretKeyRef` choisit précisément chaque clé du Secret. Le mot de passe n'apparaît plus nulle part dans le manifest : il peut être versionné dans Git sans risque.

Appliquez le déploiement :

```bash
kubectl apply -f deployment-backend.yaml
kubectl rollout status deployment/campus-backend
```

*Vérifiez dans les logs que l'API se connecte bien à la nouvelle base : `kubectl logs -l app=campus-backend --tail=5` doit afficher `Started CampusOpsApplication`.*

### 2. Écrire des données de test dans PostgreSQL
Connectez-vous directement en SQL au conteneur PostgreSQL :

```bash
kubectl exec -it deployment/campus-postgres -- psql -U campus -d campus
```

Exécutez les commandes SQL suivantes :

```sql
CREATE TABLE test_candidats (
    id SERIAL PRIMARY KEY,
    nom VARCHAR(100),
    filiere VARCHAR(100),
    date_inscription TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO test_candidats (nom, filiere) VALUES ('Alice Dubois', 'Cloud DevOps Kubernetes');
INSERT INTO test_candidats (nom, filiere) VALUES ('Bob Martin', 'Architecte Microservices');

SELECT * FROM test_candidats;
\q
```

### 3. Crash-Test : Destruction brutale du Pod
Simulons une panne matérielle ou un redémarrage impromptu du serveur en supprimant immédiatement le pod PostgreSQL :

```bash
kubectl delete pod -l app=campus-postgres --force --grace-period=0
```

Observez le contrôleur Deployment recréer immédiatement un nouveau pod de remplacement :

```bash
kubectl get pods -l app=campus-postgres -w
```

### 4. Vérification de la survie des données
Dès que le nouveau pod est `1/1 Running`, reconnectez-vous en SQL pour interroger la table :

```bash
kubectl exec -it deployment/campus-postgres -- psql -U campus -d campus -c "SELECT * FROM test_candidats;"
```

*Résultat : Les données sont parfaitement conservées ! Le nouveau Pod a remonté le volume persistant `pvc-postgres` sans aucune perte d'information.*

---

## Critères de Validation (Checklist)

- [ ] Les paramètres non sensibles sont découplés dans le ConfigMap `campus-config`.
- [ ] Les mots de passe sont protégés dans le Secret `campus-db-credentials` et décodés avec succès.
- [ ] Le PVC `pvc-postgres` est `Bound` à un PV (`kubectl get pvc,pv`) dont vous savez lire la capacité, le mode d'accès, la politique de libération et le statut.
- [ ] Le Service `postgres` (installé par le starter) pointe vers le nouveau pod PostgreSQL persistant.
- [ ] Le backend `campus-backend` est configuré avec la chaîne JDBC pointant vers `postgres:5432/campus`.
- [ ] Le test de destruction du pod confirme la persistance totale des données sur le volume.
