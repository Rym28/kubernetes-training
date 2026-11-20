# Lab 05 : Configuration & Stockage Persistant (PV / PVC / PostgreSQL)

### Objectifs Pédagogiques :
* Découpler la configuration du code applicatif à l'aide des **ConfigMaps** (par variables directes et injection globale `envFrom`).
* Sécuriser les mots de passe et identifiants sensibles avec les **Secrets** Kubernetes.
* Comprendre le cycle de vie du stockage persistant : `StorageClass`, `PersistentVolume` (PV) et `PersistentVolumeClaim` (PVC).
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
> 🗂️ **Namespace de travail : `campus-dev`.** Avant de commencer, créez-le s'il n'existe pas encore et définissez-le comme namespace courant (les commandes sont sans effet s'il existe déjà) :
>
> ```bash
> kubectl create namespace campus-dev --dry-run=client -o yaml | kubectl apply -f -
> kubectl config set-context --current --namespace=campus-dev
> kubectl config view --minify -o jsonpath='{..namespace}'   # doit afficher campus-dev
> ```
>
> *Le namespace est présenté en détail à l'Exercice 0 du [Lab 02](02-premiers-pods-labels.md#exercice-0-le-namespace-votre-perimetre-de-travail).*

---

## Contexte Métier
Depuis le Lab 03, notre API s'appuie sur une base PostgreSQL de **développement** (`postgres-dev.yaml`) qui cumule deux défauts rédhibitoires en production :

* son mot de passe est écrit **en clair** dans le manifest, donc dans le dépôt Git ;
* ses données vivent dans un volume `emptyDir` : **toutes les candidatures disparaissent** à la moindre recréation du pod.

Dans cet atelier, vous externalisez la configuration (ConfigMap), protégez les identifiants (Secret) et rendez la base persistante (PVC), puis vous le prouvez par un crash-test.

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

## Exercice 3 : Définir la Persistance avec un PersistentVolumeClaim (PVC)

Par défaut, le système de fichiers d'un conteneur est éphémère (*stateless*) : à la destruction du pod, toutes les modifications de disque sont perdues. Pour une base de données, nous devons réserver un volume persistant via un **PersistentVolumeClaim** (PVC).

### 1. Vérifier la StorageClass du cluster
Avant de créer une demande de volume, identifiez la classe de stockage par défaut de votre cluster :

```bash
kubectl get storageclass
```
*Sur votre cluster AWS, vous observez la StorageClass `local-path (default)` installée au Lab 00 (étape 5.4) : elle crée chaque volume dans un répertoire du disque local du worker qui héberge le pod.*

> ⚠️ **Aucune StorageClass ?** Le script `setup-addons.sh` du Lab 00 n'a pas été exécuté : sans lui, votre PVC resterait `Pending` indéfiniment. Exécutez-le sur `k8s-control` (Lab 00, étape 5.4).

### 2. Créer le PersistentVolumeClaim
Créez le fichier `postgres-pvc.yaml` :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Appliquez le PVC :

```bash
kubectl apply -f postgres-pvc.yaml
```

### 3. Valider la liaison dynamique (Binding)
Surveillez l'état du PVC :

```bash
kubectl get pvc postgres-pvc
```

> 💡 **Observation clé (`WaitForFirstConsumer`) :** Le PVC reste initialement à l'état **`Pending`** tant qu'aucun Pod ne le réclame. En effet, la StorageClass `local-path` utilise la politique `volumeBindingMode: WaitForFirstConsumer` pour différer la création du volume jusqu'à ce que le Scheduler détermine sur quel nœud worker le Pod PostgreSQL sera exécuté. Dès le déploiement du Pod à l'exercice 4, le volume sera créé sur le nœud assigné et le PVC passera automatiquement à l'état **`Bound`** !

Vous pouvez inspecter les volumes persistants physiques alloués :

```bash
kubectl get pv
```

### 4. Comprendre les modes d'accès aux volumes

| Mode d'accès | Signification | Cas d'usage type |
| :--- | :--- | :--- |
| `ReadWriteOnce` (RWO) | Lecture et écriture par un **seul nœud** à la fois. | Bases de données (PostgreSQL, MySQL, MongoDB). |
| `ReadOnlyMany` (ROX) | Lecture seule par de **multiples nœuds** simultanément. | Référentiel de binaires, contenu web statique. |
| `ReadWriteMany` (RWX) | Lecture et écriture partagée par **plusieurs nœuds**. | Serveur NFS, CMS WordPress (uploads partagés). |

---

## Exercice 4 : Déployer PostgreSQL avec Volume et Secrets

### 1. Créer le manifest de déploiement PostgreSQL
Créez le fichier `postgres-deployment.yaml`, la version « production » de la base de développement du Lab 03. Il porte le **même nom** (`campus-postgres`) et les **mêmes labels** : Kubernetes mettra donc à jour le Deployment existant au lieu d'en créer un second. Il lie le conteneur PostgreSQL officiel, le Secret et le volume persistant monté sur `/var/lib/postgresql/data` :

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
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pvc
```

> 💡 **`strategy: Recreate`** : avec un volume `ReadWriteOnce`, deux pods PostgreSQL ne doivent jamais écrire en même temps sur les mêmes fichiers. `Recreate` arrête l'ancien pod **avant** de démarrer le nouveau (au prix d'une courte coupure), là où `RollingUpdate` ferait coexister les deux.

### 2. Appliquer le déploiement
Appliquez le fichier :

```bash
kubectl apply -f postgres-deployment.yaml
```

Le Service `postgres` créé au Lab 03 n'a pas besoin d'être modifié : son sélecteur `app=campus-postgres` désigne automatiquement le nouveau pod. Vérifiez-le :

```bash
kubectl get endpoints postgres
```

> ⚠️ **Effet attendu sur le backend :** la nouvelle base démarre vide, avec le mot de passe du Secret (`CampusSecret2026!`), alors que le backend utilise encore l'ancien mot de passe `campus`. Ses connexions échouent (`password authentication failed`) jusqu'à l'exercice 5, qui le reconfigure. Les données saisies sur la base de développement sont perdues : c'est exactement le défaut d'`emptyDir` que nous corrigeons.

Attendez que le pod soit en cours d'exécution et vérifiez les logs d'initialisation de PostgreSQL :

```bash
kubectl wait --for=condition=ready pod -l app=campus-postgres --timeout=90s
kubectl logs -l app=campus-postgres --tail=20
```
*Vous devez voir la mention : `database system is ready to accept connections`.*

---

## Exercice 5 : Connexion Backend & Crash-Test de Persistance

### 1. Connecter le backend à la base de données
Mettez à jour votre fichier `deployment-backend.yaml` (état de fin du Lab 03) pour que le backend lise ses paramètres dans le ConfigMap et le Secret, au lieu de valeurs écrites en clair. Seules les sections `env` et `envFrom` changent ; nous revenons aussi à **2 réplicas** pour préserver les ressources des workers :

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

*Résultat : Les données sont parfaitement conservées ! Le nouveau Pod a remonté le volume persistant `postgres-pvc` sans aucune perte d'information.*

---

## Critères de Validation (Checklist)

- [ ] Les paramètres non sensibles sont découplés dans le ConfigMap `campus-config`.
- [ ] Les mots de passe sont protégés dans le Secret `campus-db-credentials` et décodés avec succès.
- [ ] Le PVC `postgres-pvc` est en statut `Bound` avec une StorageClass active.
- [ ] Le Service `postgres` (créé au Lab 03) pointe vers le nouveau pod PostgreSQL persistant.
- [ ] Le backend `campus-backend` est configuré avec la chaîne JDBC pointant vers `postgres:5432/campus`.
- [ ] Le test de destruction du pod confirme la persistance totale des données sur le volume.
