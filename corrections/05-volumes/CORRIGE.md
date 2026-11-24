# Corrigé — Atelier 05 : Configuration & Stockage Persistant (PV / PVC / PostgreSQL)

> 🔒 **Confidentiel formateur.** À diffuser en fin d'atelier uniquement. Énoncé : `labs/05-Les Volumes/README.md` (version optimisée, PV créé à la main, manifests fournis dans `labs/05-Les Volumes/manifests/`). L'ancienne version longue (StorageClass `local-path`, manifests recopiés) est archivée dans `corrections/05-volumes-longue/`.
>
> ✅ **Version testée le 23/11/2026** de bout en bout sur le cluster AWS (kubeadm v1.30, `k8s-control` + `k8s-worker-1` + `k8s-worker-2`, `local-path` installé comme classe par défaut) et sur Minikube (v1.32). Les sorties ci-dessous sont celles du test AWS (noms de pods, adresses IP et durées varient d'une session à l'autre).

---

## Repères pour le formateur

| Point | Ce qu'il faut savoir |
| :--- | :--- |
| Durée | Environ 15 à 20 min de moins que la version longue : manifests fournis (pas de recopie ni d'erreur d'indentation YAML), plus d'attente du backend à l'étape 0, backend reconfiguré en dernier (le démarrage de Spring Boot, 15 s à 1 min 30, se fait pendant que les stagiaires répondent aux questions). |
| Stockage | Le stagiaire crée lui-même le PV `pv-postgres` (provisionnement **statique**). L'atelier ne dépend d'aucune StorageClass : il fonctionne que `local-path` soit installé ou non. Les StorageClasses sont **hors programme XW335** : ne pas les développer, sauf question d'un stagiaire. |
| `storageClassName: ""` | Indispensable dans le PV **et** le PVC : sur le cluster AWS, `local-path` est la classe par défaut ; sans ce champ, le PVC y serait rattaché et ignorerait `pv-postgres`. À présenter simplement : « vide = pas de fabrication automatique, on se lie à un PV existant ». |
| `nodeAffinity` du PV | Liste `k8s-worker-1` (AWS) et `minikube` (secours) : le PV n'est utilisable que sur le nœud qui existe. C'est ce qui garantit que PostgreSQL redémarre là où sont ses données au crash-test. |
| `Retain` | Les données survivent même à un « Repartez de zéro » : en cas de reprise, `CREATE TABLE` répond `already exists` (signalé dans l'encadré, sans gravité). |
| Ateliers suivants | Les starters 06 et 07 (`02-postgres.yaml`) contiennent le même PV et le même PVC : ils s'appliquent sans erreur sur l'état de fin de cet atelier (testé). |

---

## Étape 0 — Préparer l'environnement

Commandes données dans l'énoncé. Sortie en sortant de l'Atelier 04 :

```text
namespace/campus-dev unchanged
Context "kubernetes-admin@kubernetes" modified.
deployment.apps/campus-postgres unchanged
service/postgres unchanged
deployment.apps/campus-backend configured
service/campus-backend configured
deployment.apps/campus-frontend configured
service/campus-frontend-svc unchanged
```

Depuis un namespace vide, toutes les lignes sont en `created`. Attendu : `campus-postgres` (base de développement `emptyDir`), `campus-backend` en 3 réplicas, `campus-frontend` en 2 réplicas, et les Services `postgres`, `campus-backend` et `campus-frontend-svc` (NodePort `30088`).

L'énoncé ne fait **pas** attendre le démarrage du backend : il est cassé à l'exercice 4 (nouveau mot de passe), puis reconfiguré et vérifié à l'étape 3 de l'exercice 5.

« Repartez de zéro » : `kubectl delete namespace campus-dev` puis `kubectl delete pv pv-postgres --ignore-not-found`. Le PV n'appartient à aucun namespace : sans la seconde commande, il resterait `Released` (lié à l'ancien PVC) et le nouveau PVC resterait `Pending`.

---

## Exercice 1 — Externaliser la configuration avec un ConfigMap

### Étape 1 — Créer le ConfigMap `campus-config`

Commande donnée (une seule ligne, valable en Bash comme en PowerShell). Sortie : `configmap/campus-config created`.

**Q1.** 

```bash
kubectl get configmap campus-config -o yaml
```

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

Les quatre valeurs sont rangées sous la rubrique **`data`** (clés triées par ordre alphabétique). Un ConfigMap n'a pas de `spec` : il ne décrit pas un état désiré, il stocke des données.

**Q2.** Les valeurs sont **en clair** : n'importe qui ayant le droit de lire le ConfigMap les voit. On n'y range **jamais** de mot de passe : c'est le rôle du Secret (exercice 2).

Erreur fréquente : oublier le `-` final de `kubectl apply -f -`, la commande attend alors un nom de fichier.

### Étape 2 — ConfigMap à partir d'un fichier

Commande donnée. Le fichier `extra-config.properties` est **fourni** dans `labs/05-Les Volumes/manifests/` : pas de saisie, donc pas de piège d'encodage (PowerShell 5.1 écrit en UTF-16 avec `>`). Sortie : `configmap/campus-app-props created`.

**Q1.**

```bash
kubectl describe configmap campus-app-props
```

```text
Name:         campus-app-props
Namespace:    campus-dev
Labels:       <none>
Annotations:  <none>

Data
====
extra-config.properties:
----
campus.feature.registration=enabled
campus.notification.channel=email
campus.max.students=250
```

**Q2.** Une **seule** clé : le **nom du fichier** (`extra-config.properties`). Sa valeur est **tout le contenu** du fichier.

**Q3.** `--from-file` sert quand l'application attend un **fichier de configuration complet** (`application.properties`, `nginx.conf`…), qu'on monte ensuite dans le conteneur comme un fichier. `--from-literal` convient à quelques variables d'environnement isolées.

Ce ConfigMap n'est pas utilisé par l'application : il sert seulement à montrer la différence clé/fichier.

---

## Exercice 2 — Protéger les identifiants avec un Secret

### Étape 1 — Créer, lire et décoder le Secret

Commande de création donnée. Sortie : `secret/campus-db-credentials created`.

**Q1.** On ne versionne pas ce manifest : il contient le mot de passe, simplement **encodé en base64**, donc lisible par quiconque accède au dépôt Git. C'est pourquoi les starters des labs suivants ne contiennent jamais le Secret : leur étape 0 le recrée par une commande.

**Q2.**

```bash
kubectl get secret campus-db-credentials -o yaml
```

```yaml
apiVersion: v1
data:
  POSTGRES_DB: Y2FtcHVz
  POSTGRES_PASSWORD: Q2FtcHVzU2VjcmV0MjAyNiE=
  POSTGRES_USER: Y2FtcHVz
kind: Secret
type: Opaque
```

Les valeurs ne sont pas lisibles directement : elles apparaissent **encodées en base64** (`Y2FtcHVz` = `campus`).

**Q3.** Le décodage (commande donnée, testée en Bash et en PowerShell) affiche `CampusSecret2026!`.

**Q4.** Base64 est un **encodage**, pas un chiffrement : il n'y a aucune clé, tout le monde peut décoder. Peuvent lire le mot de passe tous ceux qui ont le droit `get secret` dans le namespace (RBAC, Atelier 07), et quiconque lit `etcd` si les Secrets n'y sont pas chiffrés au repos.

Erreur fréquente (Bash) : écrire `--from-literal=POSTGRES_PASSWORD=CampusSecret2026!` sans guillemets simples. Dans un terminal Bash interactif, `!` déclenche l'expansion d'historique (`event not found`). Les guillemets simples l'évitent.

---

## Exercice 3 — Offrir et demander du stockage persistant (PV et PVC)

### Étape 1 — Créer le PersistentVolume

**Q1.**

```bash
kubectl apply -f "labs/05-Les Volumes/manifests/01-pv-postgres.yaml"
kubectl get pv
```

```text
persistentvolume/pv-postgres created

NAME          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
pv-postgres   1Gi        RWO            Retain           Available                          <unset>                          0s
```

**Q2.** `1Gi`, `RWO` (`ReadWriteOnce`), politique `Retain` (les données sont gardées quand le PVC est supprimé), statut **`Available`** : le PV est libre, sa colonne `CLAIM` est vide.

**Q3.** Aucun namespace n'a été précisé, et la commande n'en affiche pas : un PV est une ressource **du cluster**, comme un nœud. Il représente un stockage physique, que n'importe quel namespace peut demander via un PVC. `kubectl api-resources | grep persistentvolumes` montre `NAMESPACED false` pour le PV, `true` pour le PVC.

Points de lecture du manifest, à faire remarquer :
* `hostPath` + `type: DirectoryOrCreate` : le kubelet crée `/mnt/donnees/campus-postgres` sur le nœud au premier montage.
* `nodeAffinity` : ce répertoire n'existe que sur `k8s-worker-1` (ou `minikube`).
* `storageClassName: ""` : voir « Repères pour le formateur ».

### Étape 2 — Créer le PersistentVolumeClaim

**Q1.**

```bash
kubectl apply -f "labs/05-Les Volumes/manifests/02-pvc-postgres.yaml"
kubectl get pvc,pv
```

**Q2.**

```text
NAME                                 STATUS   VOLUME        CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/pvc-postgres   Bound    pv-postgres   1Gi        RWO                           <unset>                 0s

NAME                           CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                     STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
persistentvolume/pv-postgres   1Gi        RWO            Retain           Bound    campus-dev/pvc-postgres                  <unset>                          1s
```

Le PVC et le PV sont **`Bound`** immédiatement (taille suffisante, même mode d'accès, PV libre). Le `CLAIM` du PV vaut `campus-dev/pvc-postgres`, et la colonne `VOLUME` du PVC vaut `pv-postgres`. Le cycle de vie `Available` → `Bound` est visible entre les deux étapes.

**Q3.** `ReadWriteOnce` : lecture/écriture par un seul nœud à la fois. Il convient à une base de données : un seul serveur PostgreSQL doit écrire dans ses fichiers à la fois.

Erreurs fréquentes :
* PVC appliqué avant le PV : `Pending`, événement `no persistent volumes available for this claim`. Appliquer le PV suffit, la liaison se fait seule.
* PVC appliqué sans la ligne `storageClassName: ""` (copie d'un ancien manifest) : sur AWS, il est rattaché à `local-path` et reste `Pending` (`WaitForFirstConsumer`) au lieu de se lier à `pv-postgres`. Supprimer le PVC et appliquer le fichier fourni.

---

## Exercice 4 — Déployer PostgreSQL avec son volume et son Secret

### Étape 1 — Lire le manifest PostgreSQL

**Q1.** Le conteneur lit `POSTGRES_PASSWORD` (comme `POSTGRES_DB` et `POSTGRES_USER`) dans le Secret `campus-db-credentials`, via `valueFrom.secretKeyRef`. Le mot de passe **n'apparaît pas** dans le fichier.

**Q2.** `volumes` (niveau pod) déclare **quel** stockage : le PVC `pvc-postgres`. `volumeMounts` (niveau conteneur) indique **où** le brancher : `/var/lib/postgresql/data`. Le champ **`name`** (`donnees`) relie les deux.

**Q3.** Par rapport au starter, la source du volume passe de `emptyDir: {}` à `persistentVolumeClaim: claimName: pvc-postgres`.

`PGDATA=/var/lib/postgresql/data/pgdata` place les données dans un **sous-répertoire** du volume : PostgreSQL refuse d'initialiser une base dans un répertoire non vide (certains stockages y créent `lost+found`).

### Étape 2 — Appliquer le déploiement

**Q1 à Q4.**

```bash
kubectl apply -f "labs/05-Les Volumes/manifests/03-postgres-deployment.yaml"
kubectl rollout status deployment/campus-postgres
kubectl get endpoints postgres
kubectl logs -l app=campus-postgres --tail=20
```

```text
deployment.apps/campus-postgres configured
Waiting for deployment "campus-postgres" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "campus-postgres" rollout to finish: 0 of 1 updated replicas are available...
deployment "campus-postgres" successfully rolled out

NAME       ENDPOINTS             AGE
postgres   192.168.230.17:5432   23s
```

* `rollout status` attend le nouveau pod (7 s environ sur AWS). Avec `Recreate`, l'ancien pod s'arrête d'abord : pendant quelques secondes, il n'y a plus de base.
* `kubectl get endpoints postgres` affiche une seule adresse `<IP-du-nouveau-pod>:5432` : le sélecteur `app=campus-postgres` du Service désigne automatiquement le nouveau pod.
* La base est prête quand les logs affichent `database system is ready to accept connections`. **Constaté sur AWS et sur Minikube** : juste après `rollout status`, la phrase n'est pas encore là, car PostgreSQL initialise la base (`initdb`) avec un serveur temporaire pendant 3 à 10 s. L'énoncé demande de relancer la commande. Dans les logs complets, la phrase apparaît deux fois (serveur temporaire puis serveur définitif) : la dernière est celle qui compte.

Le backend affiche `password authentication failed` à partir de ce moment : c'est attendu (encadré de l'énoncé), il est reconfiguré à l'étape 3 de l'exercice 5.

Erreur fréquente : PVC créé dans un autre namespace (`default`) : le pod reste `Pending` avec `persistentvolumeclaim "pvc-postgres" not found`.

### Étape 3 — Observer où vivent les données

```bash
kubectl get pods -l app=campus-postgres -o wide
```

```text
NAME                              READY   STATUS    RESTARTS   AGE   IP               NODE           NOMINATED NODE   READINESS GATES
campus-postgres-7f44cbd8f-dfwkn   1/1     Running   0          3s    192.168.230.17   k8s-worker-1   <none>           <none>
```

**Q1.** Le pod tourne sur **`k8s-worker-1`** (`minikube` en secours).

**Q2.** La section `nodeAffinity` du PV impose ce nœud à tout pod qui l'utilise : le répertoire `/mnt/donnees/campus-postgres` n'existe que sur son disque. Le scheduler en tient compte automatiquement. Si ce worker tombe, la base ne redémarre pas ailleurs : en production, on utilise un stockage réseau (NFS, AWS EBS…) accessible depuis n'importe quel nœud.

Si le cluster a été monté avec d'autres noms de nœuds, le pod reste `Pending` (`didn't match PersistentVolume's node affinity`) : adapter le nom dans `01-pv-postgres.yaml`, supprimer Deployment, PVC et PV, réappliquer les fichiers 01 à 03 (indice de l'énoncé).

---

## Exercice 5 — Prouver la persistance et reconnecter le backend

### Étape 1 — Écrire des données de test

Commandes données.

```text
CREATE TABLE
INSERT 0 2

 id |     nom
----+--------------
  1 | Alice Dubois
  2 | Bob Martin
(2 rows)
```

**Q1.** La table contient **2 lignes**.

**Q2.** `kubectl exec deployment/campus-postgres` choisit **un pod du Deployment** (ici le seul) : pratique quand on ne connaît pas le nom généré du pod.

`psql` se connecte par le socket local du conteneur, sans mot de passe : l'image officielle autorise les connexions locales (`trust`).

Si le lab a été repris après un « Repartez de zéro », `CREATE TABLE` répond `relation "test_candidats" already exists` : les données ont été conservées sur le worker (`Retain`). Sans gravité, le `SELECT` fonctionne.

### Étape 2 — Crash-test et survie des données

**Q1 et Q2.**

```bash
kubectl delete pod -l app=campus-postgres
kubectl get pods -l app=campus-postgres -w
```

```text
pod "campus-postgres-7f44cbd8f-dfwkn" deleted from campus-dev namespace
NAME                              READY   STATUS    RESTARTS   AGE
campus-postgres-7f44cbd8f-xzr2v   1/1     Running   0          3s
```

**Q3.** Le nouveau pod porte un **nouveau nom** (même préfixe `campus-postgres-<hash>`, suffixe différent). Le **ReplicaSet** du Deployment l'a recréé pour revenir à `replicas: 1` (Self-Healing, Atelier 03). Il est de nouveau sur `k8s-worker-1`, imposé par le PV.

**Q4.**

```bash
kubectl exec deployment/campus-postgres -- psql -U campus -d campus -c "SELECT * FROM test_candidats;"
```

Les deux lignes `Alice Dubois` et `Bob Martin` sont toujours là.

**Q5.** Le pod a été détruit, mais le **PVC**, le **PV** et le répertoire `/mnt/donnees/campus-postgres` du worker existent toujours : le nouveau pod a remonté le même volume. Avec l'`emptyDir` du starter, le volume naît et meurt avec le pod : la table aurait disparu (`relation "test_candidats" does not exist`).

Si `exec` renvoie `error: unable to upgrade connection` ou `container not found`, le nouveau pod n'est pas encore prêt : attendre `1/1 Running`.

### Étape 3 — Reconfigurer le backend

**Q1.** `envFrom` + `configMapRef` injecte **toutes** les clés du ConfigMap comme variables d'environnement, d'un coup. `env` + `secretKeyRef` choisit **une** clé précise du Secret et lui donne le nom de variable voulu (`POSTGRES_PASSWORD` → `SPRING_DATASOURCE_PASSWORD`).

**Q2.** Oui, le fichier peut être versionné : il ne contient que des **références** (`campus-config`, `campus-db-credentials`), aucune valeur sensible.

**Q3.**

```bash
kubectl apply -f "labs/05-Les Volumes/manifests/04-deployment-backend.yaml"
kubectl rollout status deployment/campus-backend
```

```text
deployment.apps/campus-backend configured
Waiting for deployment "campus-backend" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "campus-backend" rollout to finish: 1 old replicas are pending termination...
deployment "campus-backend" successfully rolled out
```

**Q4.** Linux / macOS :

```bash
kubectl logs -l app=campus-backend --prefix --tail=-1 | grep "Started CampusOpsApplication"
```

Windows (PowerShell) :

```powershell
kubectl logs -l app=campus-backend --prefix --tail=-1 | Select-String "Started CampusOpsApplication"
```

```text
[pod/campus-backend-6c955b9fd8-sdwqs/campus-backend] ... Started CampusOpsApplication in 13.316 seconds (process running for 14.927)
[pod/campus-backend-6c955b9fd8-svwkb/campus-backend] ... Started CampusOpsApplication in 12.982 seconds (process running for 14.561)
```

**2 lignes** : le Deployment est passé à 2 réplicas, et les deux pods ont démarré avec le nouveau mot de passe. Temps mesurés : environ 20 s après l'`apply` sur AWS, 80 s sur Minikube. Les pods se répartissent sur les deux workers (anti-affinité).

Pendant le démarrage, la commande peut afficher 0 ou 1 ligne, voire `Error from server (NotFound)` si un ancien pod disparaît pendant la lecture : relancer.

Vérification facultative de l'injection :

```bash
kubectl exec deployment/campus-backend -- env | grep -E "SPRING_|JAVA_TOOL|SERVER_PORT|LOGGING"
```

```text
SPRING_PROFILES_ACTIVE=production
SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/campus
SPRING_DATASOURCE_USERNAME=campus
SPRING_DATASOURCE_PASSWORD=CampusSecret2026!
JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=75
LOGGING_LEVEL_COM_OKDLAB=INFO
SERVER_PORT=8080
```

Bout en bout : `http://<IP_PUBLIQUE_WORKER>:30088/actuator/health` répond `200` (portail → API → base persistante).

Erreur fréquente : appliquer le backend **avant** le Secret. Les pods restent en `CreateContainerConfigError` (`secret "campus-db-credentials" not found`). Créer le Secret suffit : le kubelet réessaie tout seul.

Redémarrage possible : sur une base neuve, les deux pods créent les tables en même temps, l'un peut échouer (`relation ... already exists`) et redémarrer une fois. Non observé lors du test, mais possible : c'est normal (encadré de l'énoncé).

---

## Checklist de validation — commandes de contrôle

```bash
kubectl get configmap campus-config
kubectl get secret campus-db-credentials
kubectl get pvc,pv                       # pvc-postgres Bound à pv-postgres (1Gi, RWO, Retain)
kubectl get endpoints postgres           # une adresse :5432
kubectl get deployment campus-backend -o jsonpath="{.spec.template.spec.containers[0].envFrom}"; echo
kubectl exec deployment/campus-postgres -- psql -U campus -d campus -c "SELECT count(*) FROM test_candidats;"   # 2
```

---

## Récapitulatif — Manifests de fin de lab

Les fichiers `manifests/01-pv-postgres.yaml`, `02-pvc-postgres.yaml`, `03-postgres-deployment.yaml`, `04-deployment-backend.yaml` et `extra-config.properties` sont fournis dans le dossier du lab et reproduits dans l'énoncé, sans modification. Tous passent `kubectl apply --dry-run=server`.

Les starters des Ateliers 06 et 07 reprennent cet état : ConfigMap `campus-config` (`01-config.yaml`), PV `pv-postgres` + PVC `pvc-postgres` + PostgreSQL persistant + Service `postgres` (`02-postgres.yaml`), backend à 2 réplicas branché sur `campus-config` et `campus-db-credentials` (`03-backend.yaml`). Testé : le starter 06 s'applique sans erreur sur l'état de fin de cet atelier (`persistentvolume/pv-postgres configured`, le reste `unchanged`), et après un « Repartez de zéro » il recrée le PV, qui se lie aussitôt au PVC. Le Secret, lui, n'est jamais versionné : l'étape 0 de ces labs le recrée.
