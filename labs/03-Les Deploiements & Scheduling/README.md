# Atelier 03 : Déploiements — Résilience & Rollback

### Objectifs Pédagogiques :
* Comprendre le rôle du contrôleur **Deployment** et de la boucle de réconciliation du **ReplicaSet**.
* Expérimenter la résilience automatique (*Self-Healing*) de Kubernetes lors de la perte brutale d'un pod.
* Déployer l'API `campus-backend` en haute disponibilité (plusieurs réplicas).
* Configurer finement la stratégie de mise à jour progressive (*Rolling Update*) avec `maxSurge` et `maxUnavailable`.
* Réagir à une livraison défectueuse : vérifier que `maxUnavailable: 0` préserve le service, puis revenir à une révision saine (*Rollback* ciblé).

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Compatibilité OS</strong></p>

Toutes les commandes de cet atelier (`kubectl create deployment`, `kubectl scale`, `kubectl set image`, `kubectl rollout`) sont **rigoureusement identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)**. Quand une commande diffère, des onglets vous proposent les deux variantes.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Environnement : le cluster 3 nœuds (1 control plane + 2 workers) de l'Atelier 01</strong></p>

Réalisez ce lab sur ce cluster, piloté au choix :

* **Option A (Recommandée - Confort DevOps Local) :** depuis votre machine locale, avec votre `kubectl` et votre `kubeconfig`. Dans **chaque nouveau terminal**, placé à la racine du dépôt, pointez d'abord `kubectl` vers le fichier `kubeconfig.yaml` récupéré à l'étape 17 de l'Atelier 01 :
    * Windows (PowerShell) : `$env:KUBECONFIG = "$PWD\labs\01-Installation-Cluster\terraform\kubeconfig.yaml"`
    * Linux / macOS (Bash) : `export KUBECONFIG=$PWD/labs/01-Installation-Cluster/terraform/kubeconfig.yaml`
    * Vérification : `kubectl get nodes` doit afficher les 3 nœuds à l'état `Ready`.
* **Option B (PC d'entreprise verrouillé) :** en SSH sur `k8s-control` : l'outillage et les manifests sont pré-installés dans `~/labs/`.

🛟 **Secours : Minikube sur votre poste** (session AWS indisponible), piloté forcément depuis votre poste comme en Option A. Les Deployments, le *Rolling Update* et le *Rollback* fonctionnent à l'identique ; seule la colonne `NODE` affiche toujours `minikube`, le seul nœud.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Namespace de travail : <code>campus-dev</code></strong></p>

Ce lab est **indépendant des autres** : son étape 0 crée `campus-dev` s'il n'existe pas encore, puis y installe ou met à jour tout ce dont il a besoin. Vous pouvez le réaliser sans avoir fait les labs précédents ; pour le recommencer à zéro, utilisez l'encadré « Repartir de zéro » de l'étape 0.

</div>

---

## Contexte Métier
L'API métier du campus (`campus-backend`) traite les offres de stages et les candidatures pour 25 000 étudiants. Elle ne peut souffrir d'aucune interruption de service. Vous devez la déployer sous forme d'un **Deployment** avec au moins 2 réplicas, vérifier sa résistance aux pannes, tester une montée de version applicative, ajuster les garde-fous de disponibilité et maîtriser la procédure d'urgence de retour en arrière.

* Image Backend v1 : `regaieg/campus:backend-1.0.0`
* Port d'écoute : `8080`

<div class="admonition tip" markdown>
<p class="admonition-title"><strong>Mode d'emploi</strong></p>

* Les encadrés rouges **« À vous de répondre »** contiennent les questions. Pour les commandes déjà vues, on vous demande la commande au lieu de vous la donner : cherchez avec `kubectl --help`, `kubectl <commande> --help` ou `kubectl explain`.
* Les commandes nouvelles sont données.
* Les encadrés **« Indice »** sont repliés : cliquez dessus seulement si vous bloquez.

</div>

---

## Étape 0 : Préparer l'environnement (base de données de développement)

L'API Spring Boot se connecte à PostgreSQL **dès son démarrage** : sans base joignable, elle s'arrête en erreur et ses pods tournent en `CrashLoopBackOff`. Avant de déployer le backend, installez donc une base PostgreSQL de **développement**, fournie clé en main dans le dossier `starter/` du lab.

Créez le namespace `campus-dev` s'il n'existe pas encore, sélectionnez-le, puis appliquez le starter. Si vous sortez du lab précédent, vos objets sont conservés et simplement mis à jour. Depuis la racine du dépôt (Option A) ou depuis `~` sur `k8s-control` (Option B : mettez d'abord le dépôt à jour avec `git -C ~/formation pull`, puis remplacez `labs/` par `~/labs/`) :

```bash
kubectl create namespace campus-dev --dry-run=client -o yaml | kubectl apply -f -   # sans effet s'il existe déjà
kubectl config set-context --current --namespace=campus-dev
kubectl apply -f "labs/03-Les Deploiements & Scheduling/starter/"
kubectl get deployment,pods,service -l app=campus-postgres
```

<details class="warning" markdown>
<summary><strong>Environnement incohérent ou lab à recommencer ? Repartez de zéro</strong></summary>

Supprimez le namespace et tout son contenu, puis relancez les commandes ci-dessus :

```bash
kubectl delete namespace campus-dev   # ⚠️ supprime tout le contenu de campus-dev
```

*La suppression peut prendre jusqu'à une minute : `kubectl` rend la main quand elle est terminée.*

</details>

<details class="example" markdown>
<summary><strong>Contenu du manifest <code>postgres-dev.yaml</code> (à lire, pas à recopier)</strong></summary>

```yaml
# ==============================================================================
# Atelier 03 - Base PostgreSQL de DÉVELOPPEMENT (éphémère)
# ------------------------------------------------------------------------------
# L'API campus-backend (Spring Boot + JPA) se connecte à PostgreSQL dès son
# démarrage : sans base joignable, elle s'arrête en erreur.
# Cette base de développement stocke ses données dans un volume emptyDir :
# elles DISPARAISSENT à chaque recréation du pod.
# L'Atelier 05 la transformera en base persistante et sécurisée (Secret + PVC).
# ==============================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: campus-postgres
  labels:
    app: campus-postgres
spec:
  replicas: 1
  # Une base de données ne doit jamais tourner en double sur les mêmes fichiers :
  # Recreate arrête l'ancien pod AVANT de démarrer le nouveau.
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
          value: "campus"
        - name: POSTGRES_USER
          value: "campus"
        - name: POSTGRES_PASSWORD
          value: "campus"          # Mot de passe en clair : acceptable en dev, corrigé à l'Atelier 05
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: postgres-dev-data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-dev-data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  labels:
    app: campus-postgres
spec:
  type: ClusterIP
  selector:
    app: campus-postgres
  ports:
  - port: 5432
    targetPort: 5432
```

Deux choix à remarquer, que vous retravaillerez à l'Atelier 05 :

* les données sont dans un volume **`emptyDir`** : elles sont perdues à chaque recréation du pod ;
* le mot de passe est écrit **en clair** dans le manifest.

</details>

---

## Exercice 1 : Créer le Deployment du backend

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un Deployment ne lance pas les pods lui-même. Il crée un **ReplicaSet**, qui fabrique les pods à partir d'un **modèle** (`template`).

</div>

### Étape 1 : Générer le squelette du manifest

Plutôt que d'écrire tout le YAML à la main, faites-le générer par `kubectl`, **sans rien créer dans le cluster**, et enregistrez-le dans un fichier `deployment-backend.yaml` :

**Linux / macOS, Git Bash, PowerShell 7**

```bash
kubectl create deployment campus-backend --image=regaieg/campus:backend-1.0.0 --replicas=2 --port=8080 --dry-run=client -o yaml > deployment-backend.yaml
```

**Windows PowerShell 5.1**

```powershell
kubectl create deployment campus-backend --image=regaieg/campus:backend-1.0.0 --replicas=2 --port=8080 --dry-run=client -o yaml | Out-File -Encoding utf8 deployment-backend.yaml
```

| Élément | Rôle |
| :--- | :--- |
| `campus-backend` | Nom du Deployment |
| `--image=regaieg/campus:backend-1.0.0` | Image du conteneur |
| `--replicas=2` | Nombre de pods désirés |
| `--port=8080` | Port exposé par le conteneur |
| `--dry-run=client` | « Fait semblant » : l'objet est construit par `kubectl`, mais **rien n'est envoyé au cluster** |
| `-o yaml` | Affiche l'objet construit au format YAML |
| `> deployment-backend.yaml` | Enregistre cet affichage dans un fichier (`Out-File -Encoding utf8` sous PowerShell 5.1, dont la redirection `>` écrit en UTF-16, illisible par `kubectl`) |

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Vérifiez qu'aucun pod backend n'a été créé : quelle commande liste les pods portant le label `app=campus-backend` ? Que renvoie-t-elle, et pourquoi ?

</div>

### Étape 2 : Lire le manifest généré

Ouvrez `deployment-backend.yaml` dans votre éditeur.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Où se trouve le nombre d'instances désirées ?
2. Vous n'avez écrit aucun label dans votre commande. Pourtant, le label `app: campus-backend` apparaît à **deux** endroits sous `spec`. Lesquels ? D'où vient ce label ?
3. Que décrit la section `spec.template` ? À quel autre manifest de l'Atelier 02 ressemble son contenu, et qu'est-ce qui y manque (nom, `kind`…) ?
4. Quel nom `kubectl` a-t-il donné au conteneur ? D'où vient ce nom ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : les trois sections clés d'un Deployment</strong></summary>

* `spec.replicas` : le nombre de pods désirés.
* `spec.selector.matchLabels` : le filtre qui dit au contrôleur « les pods qui portent ce label sont à moi ».
* `spec.template` : le **modèle** de pod. Le contrôleur en fabrique autant de copies que `replicas` le demande, et donne à chacune un nom unique (`campus-backend-<hash>-<suffixe>`).

`kubectl create deployment` déduit le label `app: <nom du deployment>` et le nom du conteneur (d'après l'image) tout seul. `kubectl explain deployment.spec.template` détaille la section.

</details>

### Étape 3 : Compléter le manifest

Modifiez `deployment-backend.yaml` :

* renommez le conteneur en `campus-backend` (ce nom sera utilisé à l'étape 13 par `kubectl set image … campus-backend=…`) ;
* supprimez les lignes vides `strategy: {}`, `resources: {}` et `status: {}` ;
* ajoutez sous le conteneur une section `env` avec les trois variables de connexion à PostgreSQL ci-dessous.

| Variable | Valeur |
| :--- | :--- |
| `SPRING_DATASOURCE_URL` | `jdbc:postgresql://postgres:5432/campus` |
| `SPRING_DATASOURCE_USERNAME` | `campus` |
| `SPRING_DATASOURCE_PASSWORD` | `campus` |

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Précision d'architecture</strong></p>

L'API Spring Boot initialise son contexte Hibernate/JPA dès le démarrage. Les variables `SPRING_DATASOURCE_*` lui indiquent où trouver la base de développement installée à l'étape 0. À l'Atelier 05, nous déplacerons ces paramètres dans un ConfigMap et un Secret dédiés.

</div>

<details class="tip" markdown>
<summary><strong>Indice : squelette de la partie <code>spec</code> à compléter</strong></summary>

Remplacez chaque `....` par la valeur attendue :

```yaml
spec:
  replicas: ...
  selector:
    matchLabels:
      app: ...............
  template:
    metadata:
      labels:
        app: ...............
    spec:
      containers:
      - name: ...............
        image: ...............
        ports:
        - containerPort: ....
        env:
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:postgresql://postgres:5432/campus"
        - name: SPRING_DATASOURCE_USERNAME
          value: "campus"
        - name: SPRING_DATASOURCE_PASSWORD
          value: "campus"
```

`env` est une **liste** : chaque variable commence par un tiret, avec `name` et `value`. Elle se place au même niveau que `image` et `ports`.

</details>

### Étape 4 : Appliquer le manifest

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande crée le Deployment à partir de votre fichier, de manière **déclarative** ?

</div>

### Étape 5 : Observer la chaîne Deployment → ReplicaSet → Pods

Les ReplicaSets s'abrègent `rs` dans `kubectl` (`kubectl get rs` équivaut à `kubectl get replicasets`).

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelles commandes listent les Deployments, les ReplicaSets, puis les pods du backend **avec leur nœud** ?
2. Comparez les noms : quel lien voyez-vous entre le nom du Deployment, celui du ReplicaSet et celui des pods ?
3. Combien de pods sont `Running` ? Sur quel(s) nœud(s) tournent-ils ?

</div>

<div class="admonition warning" markdown>
<p class="admonition-title"><strong>Un pod <code>Running</code> n'est pas forcément prêt</strong></p>

Kubernetes affiche `Running` dès que le conteneur est lancé, mais l'application Spring Boot met ensuite de 20 secondes à 2 minutes à démarrer (connexion à PostgreSQL, création des tables). Seuls les logs de l'application indiquent la fin de ce démarrage.

</div>

Affichez les 5 dernières lignes de logs de **tous** les pods portant le label `app=campus-backend` (`--prefix` indique devant chaque ligne le pod d'où elle vient) :

```bash
kubectl logs -l app=campus-backend --prefix --tail=5
```

Attendez que **chaque** pod affiche une ligne `Started CampusOpsApplication in … seconds` avant de continuer. Si un pod ne l'affiche pas encore, patientez quelques secondes et relancez la commande.

<details class="tip" markdown>
<summary><strong>Indice : les pods backend redémarrent en boucle (<code>CrashLoopBackOff</code>)</strong></summary>

Lisez la cause dans les logs du conteneur **précédent** (celui qui a planté) :

**Linux / macOS**

```bash
kubectl logs <nom-du-pod> --previous | grep -i -m 3 "error\|exception"
```

**Windows (PowerShell)**

```powershell
kubectl logs <nom-du-pod> --previous | Select-String "error|exception" | Select-Object -First 3
```

* `UnknownHostException: postgres` ou `Connection refused` : la base de développement n'est pas déployée ou pas encore prête (revoyez l'étape 0).
* `password authentication failed` : les valeurs `SPRING_DATASOURCE_*` ne correspondent pas à celles du manifest `postgres-dev.yaml`.

</details>

---

## Exercice 2 : Self-Healing et mise à l'échelle

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Kubernetes compare en permanence l'**état désiré** (ce que vous avez écrit) et l'**état réel** (ce qui tourne), et corrige l'écart tout seul.

</div>

### Étape 6 : Simuler une panne

Relevez le nom de l'un des deux pods `campus-backend-xxxx-yyyy`.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande supprime ce pod ?

</div>

### Étape 7 : Observer la réconciliation

Juste après la suppression, listez à nouveau les pods du backend.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Combien de pods voyez-vous ? Regardez la colonne `AGE` : que remarquez-vous ?
2. Quel composant a recréé le pod, et en se basant sur quelle valeur du manifest ?
3. À l'Atelier 02, que se passait-il quand vous supprimiez un pod créé seul, sans Deployment ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : la boucle de réconciliation (Control Loop)</strong></summary>

Un contrôleur Kubernetes répète sans fin trois actions : **observer** l'état réel, **comparer** à l'état désiré, **agir** pour combler l'écart. Demandez-vous quel objet de la chaîne Deployment → ReplicaSet → Pods porte le nombre de réplicas à maintenir.

</details>

### Étape 8 : Monter en charge de manière impérative

Un afflux d'étudiants est annoncé : passez à **4** réplicas, sans modifier votre fichier.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande change directement le nombre de réplicas du Deployment `campus-backend` ?
2. Combien de nouveaux pods apparaissent ? Le ReplicaSet a-t-il changé de nom ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : changer le nombre de réplicas</strong></summary>

Cherchez dans `kubectl --help` une commande dont le nom évoque la mise à l'échelle, puis consultez `kubectl <commande> --help` : elle prend le type et le nom de l'objet, et une option `--replicas`.

</details>

### Étape 9 : Redescendre de manière déclarative

Modifiez votre fichier `deployment-backend.yaml` pour fixer `replicas: 3`, puis appliquez-le.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Combien de pods restent ? Lequel a été supprimé ?
2. Juste avant d'appliquer, que contenait votre fichier, et que contenait le cluster ? Pourquoi, en équipe, préfère-t-on modifier le **fichier** plutôt que d'utiliser la commande de l'étape 8 ?

</div>

---

## Exercice 3 : Paramétrer et suivre un Rolling Update

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Une nouvelle version remplace les pods **progressivement**, et deux paramètres règlent le rythme de ce remplacement.

</div>

### Étape 10 : Paramétrer la stratégie de mise à jour

Par défaut, Kubernetes utilise la stratégie `RollingUpdate` : il remplace les pods progressivement. Deux paramètres en règlent le rythme :

| Paramètre | Rôle |
| :--- | :--- |
| `maxUnavailable` | Nombre (ou pourcentage) maximal de pods pouvant être **indisponibles** pendant la mise à jour |
| `maxSurge` | Nombre (ou pourcentage) maximal de pods **supplémentaires** pouvant être créés au-delà du nombre de réplicas demandé |

Ajoutez la stratégie suivante sous `spec` dans `deployment-backend.yaml` (au même niveau que `replicas`), puis appliquez le fichier :

```yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

Avec `replicas: 3` et ces réglages :

1. Combien de pods au **maximum** peuvent exister en même temps pendant une mise à jour ?
2. Combien de pods au **minimum** restent disponibles pendant toute la mise à jour ?
3. Dans quel ordre Kubernetes procède-t-il : il crée d'abord un nouveau pod, ou il supprime d'abord un ancien ?

</div>

### Étape 11 : Livrer une nouvelle version

Toute modification du **modèle de pod** (`spec.template` : image, variable, ressources…) déclenche un *rolling update*. Ajoutez une variable de version et documentez la raison du changement :

```bash
kubectl set env deployment/campus-backend CAMPUS_RELEASE=1.0.1
kubectl annotate deployment/campus-backend kubernetes.io/change-cause="Livraison 1.0.1 : variable CAMPUS_RELEASE"
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Si vous réappliquiez exactement la même image `backend-1.0.0` avec `kubectl set image`, une mise à jour serait-elle déclenchée ? Pourquoi ?

</div>

### Étape 12 : Suivre le rolling update

Suivez la progression en temps réel :

```bash
kubectl rollout status deployment/campus-backend
```

Listez ensuite les ReplicaSets du backend.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande liste uniquement les ReplicaSets portant le label `app=campus-backend` ?
2. Combien de ReplicaSets voyez-vous ? Combien de pods chacun gère-t-il (colonnes `DESIRED` / `CURRENT`) ?
3. Pourquoi Kubernetes conserve-t-il l'ancien ReplicaSet, alors qu'il ne gère plus aucun pod ?

</div>

---

## Exercice 4 : Gérer un incident de livraison et revenir en arrière

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Les réglages de l'exercice 3 évitent la coupure quand une livraison échoue, et l'historique des révisions permet de revenir en arrière en une commande.

</div>

### Étape 13 : Provoquer un incident

L'équipe déploie par erreur une image qui n'existe pas, `regaieg/campus:backend-invalid-tag`. Déclenchez ce déploiement erroné :

```bash
kubectl set image deployment/campus-backend campus-backend=regaieg/campus:backend-invalid-tag
kubectl annotate deployment/campus-backend kubernetes.io/change-cause="Livraison erronée : backend-invalid-tag" --overwrite
```

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Pourquoi <code>--overwrite</code> ?</strong></p>

L'annotation `change-cause` est recopiée telle quelle dans chaque nouvelle révision. Sans `--overwrite`, la révision fautive afficherait encore « Livraison 1.0.1 » dans l'historique, ce qui égarerait le diagnostic.

</div>

### Étape 14 : Observer l'incident

Suivez les pods du backend **en continu**, puis quittez avec `Ctrl + C`.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande affiche les pods du backend en continu ?
2. Quel statut prend le nouveau pod ? Vous l'avez déjà rencontré à l'Atelier 02 : que signifie-t-il ?
3. Combien de pods de l'ancienne version sont encore `Running` ? Les utilisateurs subissent-ils une coupure ?
4. Quel réglage de l'étape 10 explique ce comportement ? Que se serait-il passé avec `maxUnavailable: 1` ?

</div>

### Étape 15 : Consulter l'historique des révisions

Affichez l'historique complet, puis le détail de la révision 1 :

```bash
kubectl rollout history deployment/campus-backend
kubectl rollout history deployment/campus-backend --revision=1
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Combien de révisions voyez-vous ? Que contient la colonne `CHANGE-CAUSE` pour chacune ?
2. Pourquoi la révision 1 affiche-t-elle `<none>` ?
3. Quelle image et quelles variables d'environnement contient la révision 1 ?

</div>

### Étape 16 : Revenir en arrière (*Rollback*)

Annulez la livraison fautive :

```bash
kubectl rollout undo deployment/campus-backend
```

*Pour cibler une révision précise, on ajoute `--to-revision=<numéro>`.*

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Avertissement attendu</strong></p>

`kubectl` affiche `resource deployments/campus-backend was previously managed with 'kubectl apply'…` : le rollback ne met pas à jour l'annotation utilisée par `kubectl apply`. C'est attendu et sans conséquence pour la suite du lab.

</div>

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Sans option, vers quelle révision `undo` revient-il : la révision 1 ou la révision précédente ?
2. Quelle version tourne maintenant (image et variable `CAMPUS_RELEASE`) ?

</div>

### Étape 17 : Vérifier la résolution de l'incident

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelles commandes, déjà utilisées dans ce lab, confirment que la mise à jour est terminée et que 3 pods sains sont `Running` ?
2. Relancez `kubectl rollout history deployment/campus-backend` : quel numéro porte la révision restaurée ? Qu'est devenue l'ancienne révision 2 ?

</div>

---

## Critères de Validation (Checklist)

- [ ] `kubectl get deployment campus-backend` affiche `3/3` et votre fichier `deployment-backend.yaml` contient `replicas: 3` et la stratégie `RollingUpdate`.
- [ ] Vous savez expliquer la chaîne Deployment → ReplicaSet → Pods et le rôle de `spec.template`.
- [ ] Vous avez vérifié le self-healing en supprimant un pod, et vous savez dire quel composant le recrée.
- [ ] Vous savez changer le nombre de réplicas de façon impérative (`scale`) et déclarative (`apply`).
- [ ] Vous savez calculer, pour une valeur de `maxSurge` et de `maxUnavailable`, le nombre minimal et maximal de pods pendant une mise à jour.
- [ ] Vous maîtrisez les commandes d'urgence : `kubectl rollout status`, `kubectl rollout history` et `kubectl rollout undo`.
