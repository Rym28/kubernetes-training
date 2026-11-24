# Atelier 04 — Version longue (énoncé + corrigé)

> 🔒 **Confidentiel formateur.** Version longue de l'Atelier 04 (4 exercices, 15 étapes), conservée comme **variante** de l'énoncé publié `labs/04-Les Services/README.md` (version courte : 3 exercices, 10 étapes). Corrigé de la version courte : `CORRIGE.md` du même dossier.

## Quand utiliser la version longue ?

| | Version courte (publiée) | Version longue (ce fichier) |
| :--- | :--- | :--- |
| Structure | 3 exercices, 10 étapes | 4 exercices, 15 étapes |
| Suppression d'un pod | Une fois, **après** création du Service (comparaison pod / Service d'un coup) | Deux fois : **avant** le Service (constat du problème), puis **après** (constat de la solution) |
| Lecture du manifest du Service | Intégrée à l'étape de création (champs annotés dans le tableau) | Étape dédiée (type, ports, sélecteur) |
| Deployment frontend | Commande donnée | À retrouver par le stagiaire (réinvestissement Atelier 03) |
| Les 3 ports NodePort | Regroupés dans les questions de l'étape NodePort | Étape dédiée |
| Test des deux workers | Même étape | Deux étapes distinctes |
| Vérification du démarrage Spring Boot | Début de l'exercice DNS | Fin de l'étape 0 (bloquante) |

À privilégier avec un groupe **en avance** ou plus **débutant** qui a besoin de constater le problème avant de recevoir la solution (démarche inductive). Compter **15 à 20 min de plus** que la version courte : à reprendre sur le temps tampon du déroulé (`corrections/README.md`). Pour la diffuser, copier la partie « Énoncé » ci-dessous à la place de `labs/04-Les Services/README.md` et `docs/labs/04-reseau-services-dns.md` (les deux doivent rester identiques).

---

# Partie 1 — Énoncé (version longue)

## Atelier 04 : Réseau, Services & Découverte DNS

### Objectifs Pédagogiques :
* Observer le réseau des Pods (une IP par pod, attribuée par le CNI) et constater que ces adresses changent à chaque recréation, d'où le besoin d'un **Service**.
* Créer de façon déclarative le Service **ClusterIP** `campus-backend` et vérifier qu'il sélectionne ses pods par leur label.
* Joindre un Service par son nom court et par son nom complet `<service>.<namespace>.svc.cluster.local` (DNS du cluster).
* Exposer le frontend hors du cluster avec un Service **NodePort** et distinguer `targetPort`, `port` et `nodePort`.

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Compatibilité OS</strong></p>

Les commandes de cet atelier (`kubectl expose`, `kubectl get svc`, `kubectl run`) sont **rigoureusement identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)**. Quand une commande diffère, des onglets vous proposent les deux variantes.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Environnement : le cluster 3 nœuds (1 control plane + 2 workers) de l'Atelier 01</strong></p>

Ce lab exploite le fait qu'un NodePort est ouvert sur **chaque** nœud : réalisez-le sur ce cluster, piloté au choix :

* **Option A (Recommandée - Confort DevOps Local) :** depuis votre machine locale, avec votre `kubectl` et votre `kubeconfig`. Dans **chaque nouveau terminal**, placé à la racine du dépôt, pointez d'abord `kubectl` vers le fichier `kubeconfig.yaml` récupéré à l'étape 1 de l'exercice 4 de l'Atelier 01 :
    * Windows (PowerShell) : `$env:KUBECONFIG = "$PWD\labs\01-Installation-Cluster\terraform\kubeconfig.yaml"`
    * Linux / macOS (Bash) : `export KUBECONFIG=$PWD/labs/01-Installation-Cluster/terraform/kubeconfig.yaml`
    * Vérification : `kubectl get nodes` doit afficher les 3 nœuds à l'état `Ready`.
* **Option B (PC d'entreprise verrouillé) :** en SSH sur `k8s-control` : l'outillage et les manifests sont pré-installés dans `~/labs/`.

🛟 **Secours : Minikube sur votre poste** (session AWS indisponible), piloté forcément depuis votre poste comme en Option A. Tout fonctionne à l'identique, sauf l'accès navigateur des étapes 4 et 5 de l'exercice 4, pour lequel un encadré dédié est fourni.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Namespace de travail : <code>campus-dev</code></strong></p>

Ce lab est **indépendant des autres** : son étape 0 crée `campus-dev` s'il n'existe pas encore, puis y installe ou met à jour tout ce dont il a besoin. Vous pouvez le réaliser sans avoir fait les labs précédents ; pour le recommencer à zéro, utilisez l'encadré « Repartir de zéro » de l'étape 0.

</div>

---

## Contexte Métier
Dans une architecture Kubernetes, les pods naissent, meurent et changent d'adresse IP à chaque mise à jour, incident ou redémarrage. Si le frontend contactait le backend par l'adresse IP d'un pod, la communication casserait dès la première mise à jour. Nous mettons en place des **Services** : une adresse IP virtuelle stable, un nom DNS pérenne et une répartition automatique du trafic entre les pods.

* Image Frontend : `regaieg/campus:frontend-1.0.0` (port `8080`)
* Image Backend : `regaieg/campus:backend-1.0.0` (port `8080`), fournie par le starter

<div class="admonition tip" markdown>
<p class="admonition-title"><strong>Mode d'emploi</strong></p>

* Les encadrés rouges **« À vous de répondre »** contiennent les questions. Pour les commandes déjà vues dans les labs précédents, on vous demande la commande au lieu de vous la donner : cherchez avec `kubectl --help`, `kubectl <commande> --help` ou `kubectl explain`.
* Les commandes nouvelles sont données.
* Les encadrés **« Indice »** sont repliés : cliquez dessus seulement si vous bloquez.

</div>

---

## Étape 0 : Préparer l'environnement

Le dossier `starter/` du lab installe l'état de départ : la base PostgreSQL de développement (avec son Service `postgres`) et l'API `campus-backend` en 3 réplicas, **sans** Service : c'est vous qui allez le créer.

Créez le namespace `campus-dev` s'il n'existe pas encore, sélectionnez-le, puis appliquez le starter. Si vous sortez du lab précédent, vos objets sont conservés et simplement mis à jour. Depuis la racine du dépôt (Option A) ou depuis `~` sur `k8s-control` (Option B : mettez d'abord le dépôt à jour avec `git -C ~/formation pull`, puis remplacez `labs/` par `~/labs/`) :

```bash
kubectl create namespace campus-dev --dry-run=client -o yaml | kubectl apply -f -   # sans effet s'il existe déjà
kubectl config set-context --current --namespace=campus-dev
kubectl apply -f "labs/04-Les Services/starter/"
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

## Exercice 1 : Constater que l'adresse IP d'un pod n'est pas fiable

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Chaque pod reçoit sa propre adresse IP, mais cette adresse disparaît avec lui. Aucun client ne peut donc s'y fier.

</div>

### Étape 1 : Repérer les adresses IP des pods backend

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande liste les pods portant le label `app=campus-backend`, **avec leur adresse IP et leur nœud** ? Notez les adresses affichées.
2. Dans quelle plage se trouvent ces adresses ? Sur quel(s) nœud(s) tournent les pods ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : qui attribue ces adresses ?</strong></summary>

L'option qui ajoute les colonnes `IP` et `NODE` a déjà servi à l'Atelier 02 et à l'Atelier 03.

Chaque pod reçoit son adresse à sa création (plage `192.168.x.x`), attribuée par le plugin réseau (**CNI**) : Calico sur votre cluster. Les pods répartis sur les deux workers se joignent directement, d'un nœud à l'autre, sans traduction d'adresse (NAT).

</details>

### Étape 2 : Supprimer un pod backend

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande supprime l'un des pods de la liste ?

</div>

### Étape 3 : Constater le changement d'adresse

Relancez la commande de l'étape 1.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Combien de pods voyez-vous ? Lequel est nouveau (colonne `AGE`) ?
2. Le nouveau pod a-t-il repris le **nom** et l'**adresse IP** du pod supprimé ?
3. Quel composant l'a recréé (revoyez l'Atelier 03) ?
4. Conclusion : pourquoi le frontend ne peut-il pas appeler le backend par l'adresse IP d'un pod ?

</div>

---

## Exercice 2 : Créer le Service ClusterIP du backend

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un Service offre une adresse et un nom **stables** devant un groupe de pods. Il ne connaît pas ses pods par leur nom : il les retrouve grâce à leurs **labels**.

</div>

### Étape 1 : Générer le manifest du Service

Plutôt que d'écrire le Service à la main, générez-le à partir du Deployment qu'il doit servir, **sans rien créer dans le cluster**, et enregistrez-le dans `service-backend.yaml` :

**Linux / macOS, Git Bash, PowerShell 7**

```bash
kubectl expose deployment campus-backend --name=campus-backend --port=8080 --target-port=8080 --type=ClusterIP --dry-run=client -o yaml > service-backend.yaml
```

**Windows PowerShell 5.1**

```powershell
kubectl expose deployment campus-backend --name=campus-backend --port=8080 --target-port=8080 --type=ClusterIP --dry-run=client -o yaml | Out-File -Encoding utf8 service-backend.yaml
```

| Élément | Rôle |
| :--- | :--- |
| `expose deployment campus-backend` | Crée un Service devant les pods de ce Deployment |
| `--name=campus-backend` | Nom du Service : c'est le nom DNS attendu par le Nginx du frontend, il ne doit pas changer |
| `--port=8080` | Port exposé par le Service |
| `--target-port=8080` | Port sur lequel écoute le conteneur |
| `--type=ClusterIP` | Service interne, joignable uniquement depuis le cluster (type par défaut) |
| `--dry-run=client -o yaml` | Construit l'objet sans l'envoyer au cluster et l'affiche en YAML |

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande crée le Service à partir de votre fichier, de manière **déclarative** ?

</div>

### Étape 2 : Lire le manifest

Ouvrez `service-backend.yaml` dans votre éditeur.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quel champ indique le **type** du Service ?
2. Où se trouvent le port du Service et le port du conteneur ?
3. Vous n'avez écrit aucun label dans votre commande. Pourtant, la section `spec.selector` contient `app: campus-backend`. D'où vient-elle ? À quoi sert-elle ?
4. Si le sélecteur contenait par erreur `app: campus-backnd`, le Service serait-il créé ? Recevrait-il du trafic ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : les trois éléments d'un Service</strong></summary>

| Champ | Valeur | Rôle |
| :--- | :--- | :--- |
| `spec.type` | `ClusterIP` | Service interne au cluster |
| `spec.ports` | `port: 8080`, `targetPort: 8080` | Port du Service → port du conteneur |
| `spec.selector` | `app: campus-backend` | Les pods qui recevront le trafic (recopié depuis le Deployment par `kubectl expose`) |

**Pas d'étiquette, pas de trafic :** un Service et ses pods sont découplés, seul le sélecteur de labels les relie. Si aucun pod ne correspond au sélecteur, le Service existe bien, mais il ne transmet rien. `kubectl explain service.spec` détaille chaque champ.

</details>

### Étape 3 : Vérifier l'adresse du Service et ses Endpoints

Les Services s'abrègent `svc` dans `kubectl` (`kubectl get svc` équivaut à `kubectl get services`).

La liste des adresses de pods vers lesquelles le Service envoie le trafic s'appelle ses **Endpoints**. Affichez-la :

```bash
kubectl get endpoints campus-backend
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande affiche le Service `campus-backend` ? Notez son adresse IP virtuelle (colonne `CLUSTER-IP`).
2. Comparez les Endpoints avec les adresses de vos pods backend (étape 1 de l'exercice 1) : que constatez-vous ?
3. L'adresse `CLUSTER-IP` du Service fait-elle partie de la liste des Endpoints ? Pourquoi ?

</div>

### Étape 4 : Vérifier la stabilité du Service

Supprimez de nouveau un pod backend, attendez que son remplaçant soit `Running`, puis relancez les deux commandes de l'étape 3.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. La `CLUSTER-IP` du Service a-t-elle changé ?
2. La liste des Endpoints a-t-elle changé ? Qui l'a mise à jour ?
3. Un client qui appelle le Service a-t-il dû modifier quelque chose ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : Service stable, Endpoints vivants</strong></summary>

Kubernetes surveille en permanence les pods qui correspondent au sélecteur du Service. Dès qu'un pod apparaît ou disparaît, il met à jour la liste des Endpoints. L'adresse du Service, elle, reste fixe pendant toute sa vie : c'est elle que les clients utilisent.

</details>

---

## Exercice 3 : Joindre un Service par son nom (DNS)

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Kubernetes donne un **nom** à chaque Service. Les applications s'appellent par ce nom, jamais par une adresse IP.

</div>

### Étape 1 : Appeler le backend par son nom

Démarrez un pod de test équipé de `curl` (il est supprimé automatiquement quand vous le quittez) :

```bash
kubectl run test-dns --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- sh
```

Dans le terminal de ce pod, appelez le backend par le **nom de son Service**, puis par son **nom complet**, de la forme `<service>.<namespace>.svc.cluster.local` :

```sh
curl http://campus-backend:8080/actuator/health
curl http://campus-backend.campus-dev.svc.cluster.local:8080/actuator/health
```

Tapez `exit` pour quitter le pod de test.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Que répond le backend ?
2. Avez-vous eu besoin de connaître l'adresse IP d'un pod ou du Service ?
3. Le nom court et le nom complet donnent-ils la même réponse ?
4. Le backend se connecte à sa base avec l'adresse `jdbc:postgresql://postgres:5432/campus`. À quoi correspond le nom `postgres` ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : nom court ou nom complet ?</strong></summary>

* Depuis un pod du **même namespace**, le nom court suffit : `campus-backend`, `postgres`.
* Depuis un **autre namespace**, on ajoute le namespace : `campus-backend.campus-dev`, ou le nom complet `campus-backend.campus-dev.svc.cluster.local`.

</details>

<details class="tip" markdown>
<summary><strong>Indice : <code>curl</code> échoue</strong></summary>

* **Le nom est introuvable :** vérifiez que le Service existe, avec `kubectl get svc campus-backend`.
* **Le nom est trouvé mais rien ne répond :** vérifiez ses Endpoints, avec `kubectl get endpoints campus-backend`.
* **`Connection refused` de temps en temps :** le pod recréé à l'étape 4 de l'exercice 2 n'a pas fini de démarrer (20 secondes à 2 minutes). Attendez un peu et relancez la commande.

</details>

---

## Exercice 4 : Exposer le frontend hors du cluster (NodePort)

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un Service `ClusterIP` n'est joignable que depuis le cluster. Pour ouvrir l'application à un navigateur, on utilise un Service `NodePort`, qui ouvre un port sur **chaque** nœud.

</div>

### Étape 1 : Déployer le frontend

Créez un Deployment avec les caractéristiques suivantes, en générant d'abord son manifest dans un fichier `deployment-frontend.yaml`, puis en l'appliquant :

| Paramètre | Valeur |
| :--- | :--- |
| Nom | `campus-frontend` |
| Image | `regaieg/campus:frontend-1.0.0` |
| Réplicas | `2` |
| Port du conteneur | `8080` |

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande génère ce manifest **sans rien créer dans le cluster** (revoyez l'exercice 1 de l'Atelier 03) ?
2. Quelle commande l'applique ?
3. À l'Atelier 02, le pod frontend ne démarrait que grâce à un `hostAliases`. Pourquoi démarre-t-il maintenant sans cette astuce ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : générer un Deployment</strong></summary>

`kubectl create deployment <nom> --help` liste les options `--image`, `--replicas` et `--port`. Ajoutez `--dry-run=client -o yaml` et redirigez la sortie vers le fichier (`> fichier.yaml`, ou `| Out-File -Encoding utf8 fichier.yaml` sous Windows PowerShell 5.1).

Le Nginx du frontend relaie les appels `/api/` vers l'hôte `campus-backend:8080` et vérifie ce nom au démarrage : demandez-vous ce que vous avez créé à l'étape 1 de l'exercice 2.

</details>

### Étape 2 : Créer le Service NodePort

Créez un fichier `service-frontend.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: campus-frontend-svc
spec:
  type: NodePort
  selector:
    app: campus-frontend
  ports:
  - targetPort: 8080   # ① port du conteneur
    port: 80           # ② port du Service
    nodePort: 30088    # ③ port ouvert sur chaque nœud
```

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Pourquoi 30088 ?</strong></p>

Le port `30080` est réservé au contrôleur Ingress NGINX du cluster.

</div>

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande applique ce fichier ? Quelle commande liste ensuite **tous** les Services du namespace ?
2. Combien de Services voyez-vous ? De quel type est chacun ?
3. Que signifie la valeur `80:30088/TCP` affichée pour `campus-frontend-svc` ?
4. Le Service `NodePort` possède-t-il lui aussi une `CLUSTER-IP` ? Qu'en déduisez-vous sur le lien entre `NodePort` et `ClusterIP` ?

</div>

### Étape 3 : Distinguer les 3 ports d'un Service NodePort

Reprenez les repères ①, ② et ③ du manifest de l'étape 2.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Lequel de ces ports est celui sur lequel le conteneur écoute réellement ?
2. Lequel est utilisé par les **autres pods** du cluster pour joindre le Service ?
3. Lequel est ouvert sur les nœuds et joignable depuis l'extérieur ? Dans quelle plage doit-il se trouver ?
4. Dans quel ordre une requête venue de votre navigateur traverse-t-elle ces trois ports ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : les 3 ports, de l'intérieur vers l'extérieur</strong></summary>

| Paramètre | Valeur dans notre lab | Rôle |
| :--- | :--- | :--- |
| ① `targetPort` | `8080` | Port sur lequel le conteneur écoute réellement dans le pod. |
| ② `port` | `80` | Port de l'adresse IP virtuelle du Service, utilisé par les autres pods du cluster. |
| ③ `nodePort` | `30088` | Port ouvert sur **chaque nœud** du cluster (plage 30000-32767), accessible de l'extérieur. |

`kubectl explain service.spec.ports` décrit chacun de ces champs.

</details>

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Et le type LoadBalancer ?</strong></p>

Dans le cloud (EKS, AKS, GKE), il ajoute devant les NodePorts un répartiteur de charge avec une vraie IP publique. Notre cluster kubeadm n'a pas de fournisseur cloud : un tel Service resterait en `EXTERNAL-IP <pending>`.

| Besoin | Type de Service |
| :--- | :--- |
| Trafic interne au cluster | `ClusterIP` |
| Accès externe sur notre cluster | `NodePort` |
| Production dans le cloud | `LoadBalancer` |

</div>

### Étape 4 : Accéder à l'application depuis votre navigateur

Récupérez l'adresse IP publique de votre nœud worker `k8s-worker-1` (affichée par `start-session` ou dans la console AWS), puis ouvrez **`http://<IP_PUBLIQUE_WORKER>:30088`**.

<div class="admonition warning" markdown>
<p class="admonition-title"><strong>Les IP publiques changent à chaque redémarrage de la session AWS</strong></p>

Relevez-les à nouveau dans la console AWS au début de chaque séance : une ancienne adresse ne répond plus.

</div>

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Le portail affiche-t-il les offres de stage ? D'où viennent ces données ?
2. Citez, dans l'ordre, les objets traversés par une requête, du navigateur jusqu'à la base de données.

</div>

<details class="example" markdown>
<summary><strong>Vous êtes sur Minikube (secours) ?</strong></summary>

Avec le pilote Docker sous Windows ou macOS, l'adresse du nœud Minikube n'est pas joignable depuis votre poste. Remplacez cette étape par un tunnel vers le Service :

```bash
minikube service campus-frontend-svc -n campus-dev --url
```

La commande affiche une adresse `http://127.0.0.1:<port>` : ouvrez-la dans votre navigateur et **laissez le terminal ouvert** tant que vous l'utilisez (`Ctrl + C` pour fermer le tunnel). L'étape 5 n'a pas d'équivalent : Minikube n'a qu'un seul nœud.

</details>

### Étape 5 : Constater que le NodePort est ouvert sur chaque nœud

Ouvrez maintenant **`http://<IP_PUBLIQUE_k8s-worker-2>:30088`**.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Le portail répond-il aussi ?
2. Quelle commande indique sur quel(s) nœud(s) tournent les pods frontend ?
3. Un nœud qui n'héberge **aucun** pod frontend répondrait-il quand même ? Pourquoi ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : le chemin complet d'une requête</strong></summary>

**navigateur → NodePort `30088` d'un nœud → Service `campus-frontend-svc` → pod frontend (Nginx) → Service `campus-backend` → pod API → Service `postgres` → base**.

Le port `30088` est ouvert sur **tous** les nœuds, qu'ils hébergent ou non un pod frontend : le nœud qui reçoit la requête la transmet à l'un des pods sélectionnés par le Service, où qu'il se trouve.

</details>

<details class="tip" markdown>
<summary><strong>Indice : la page ne s'affiche pas ou le tableau de bord reste vide</strong></summary>

* **Le navigateur n'obtient aucune réponse :** utilisez l'IP **publique** d'un worker (pas l'IP privée `172.31.x.x`) et le port `30088`. Les IP publiques changent à chaque redémarrage de la session AWS.
* **Le port est bloqué par le pare-feu de votre entreprise (Option A) :** passez par un tunnel, comme à l'[Atelier 02](../../labs/02-Les%20Pods/README.md) : `kubectl port-forward svc/campus-frontend-svc 8081:80` lancé **depuis votre poste**, puis ouvrez `http://localhost:8081`. En Option B, ce tunnel s'ouvrirait sur `k8s-control` et non sur votre poste : il ne vous aiderait pas.
* **La page s'affiche mais les données sont absentes :** testez l'API à travers le frontend avec `curl http://<IP_PUBLIQUE_WORKER>:30088/actuator/health`. Une erreur `502 Bad Gateway` signifie que le Service `campus-backend` ne transmet rien : appliquez le réflexe **« Service muet ? `kubectl get endpoints` »**. Une liste vide signifie que le sélecteur du Service et les labels des pods ne correspondent pas.

</details>

---

## Critères de Validation (Checklist)

- [ ] Vous avez constaté qu'un pod recréé change d'adresse IP (`kubectl get pods -o wide`).
- [ ] `campus-backend` est un Service `ClusterIP` dont les Endpoints listent les pods backend, et vous savez qu'une liste vide signale un sélecteur qui ne correspond à aucun label (`kubectl get endpoints campus-backend`).
- [ ] `campus-backend` répond par son nom court et par son nom complet `campus-backend.campus-dev.svc.cluster.local`.
- [ ] `campus-frontend-svc` est exposé en `NodePort` sur le port `30088` et le portail s'affiche dans le navigateur via l'IP de chacun des deux workers.
- [ ] Vous distinguez `targetPort` (8080), `port` (80) et `nodePort` (30088).

---

# Partie 2 — Corrigé (version longue)

> Sorties relevées sur le cluster de formation (kubeadm v1.30, Calico, 1 control plane + 2 workers) : les noms de pods, adresses IP et `CLUSTER-IP` changent d'une session à l'autre.

## Étape 0 — Préparer l'environnement

Commandes données dans l'énoncé. Attendu : `deployment.apps/campus-postgres`, `service/postgres` et `deployment.apps/campus-backend` créés (ou `configured` / `unchanged` si l'on sort de l'Atelier 03), puis `deployment "campus-backend" successfully rolled out`, puis **3 lignes** `Started CampusOpsApplication in … seconds`.

Dans cette version, la vérification des logs est bloquante dès l'étape 0 : prévoir 20 secondes à 2 minutes d'attente. Les stagiaires rapides peuvent commencer l'exercice 1 pendant ce temps (il n'a pas besoin que l'API réponde).

Erreur fréquente : oublier les guillemets autour du chemin `"labs/04-Les Services/starter/"`, qui contient une espace (`error: the path "labs/04-Les" does not exist`).

---

## Exercice 1 — Constater que l'adresse IP d'un pod n'est pas fiable

### Étape 1 — Repérer les adresses IP des pods backend

**1.**

```bash
kubectl get pods -l app=campus-backend -o wide
```

```
NAME                             READY   STATUS    RESTARTS   AGE   IP               NODE
campus-backend-c9c4d5fdf-4ld8z   1/1     Running   0          38s   192.168.230.19   k8s-worker-1
campus-backend-c9c4d5fdf-sbgk9   1/1     Running   0          38s   192.168.140.12   k8s-worker-2
campus-backend-c9c4d5fdf-vzpgh   1/1     Running   0          38s   192.168.230.17   k8s-worker-1
```

**2.** Plage `192.168.x.x` : plage des pods configurée pour Calico ; chaque worker reçoit son propre sous-bloc (`192.168.230.x` sur `k8s-worker-1`, `192.168.140.x` sur `k8s-worker-2`). Les pods sont répartis sur les deux workers (anti-affinité du starter), jamais sur `k8s-control`.

### Étape 2 — Supprimer un pod backend

**1.**

```bash
kubectl delete pod campus-backend-c9c4d5fdf-4ld8z
```
Attendu : `pod "campus-backend-c9c4d5fdf-4ld8z" deleted`.

### Étape 3 — Constater le changement d'adresse

```
NAME                             READY   STATUS    RESTARTS   AGE   IP               NODE
campus-backend-c9c4d5fdf-cg9zd   1/1     Running   0          3s    192.168.140.15   k8s-worker-2
campus-backend-c9c4d5fdf-sbgk9   1/1     Running   0          60s   192.168.140.12   k8s-worker-2
campus-backend-c9c4d5fdf-vzpgh   1/1     Running   0          60s   192.168.230.17   k8s-worker-1
```

**1.** Toujours **3 pods**. Le nouveau est celui dont l'`AGE` est de quelques secondes (`cg9zd`).

**2.** Non : **nouveau nom** (nouveau suffixe aléatoire) et **nouvelle adresse IP**, parfois sur un autre nœud.

**3.** Le **ReplicaSet** du Deployment `campus-backend` : il constate 2 pods au lieu des 3 demandés et en recrée un (boucle de réconciliation vue à l'Atelier 03).

**4.** L'adresse d'un pod change à chaque recréation (mise à jour, panne, rollback, mise à l'échelle). Un frontend configuré avec une IP de pod tomberait en erreur à la première recréation et ne saurait pas répartir le trafic entre 3 pods. Il faut une adresse **stable** devant le groupe de pods : c'est le rôle du Service (exercice 2).

---

## Exercice 2 — Créer le Service ClusterIP du backend

### Étape 1 — Générer le manifest du Service

Commande de génération donnée dans l'énoncé.

**1.**

```bash
kubectl apply -f service-backend.yaml
```
Attendu : `service/campus-backend created`.

Erreur fréquente sous Windows PowerShell 5.1 : utiliser `>` au lieu de `| Out-File -Encoding utf8`. Le fichier est écrit en UTF-16 et `kubectl apply` échoue (`error converting YAML to JSON` ou caractères illisibles).

### Étape 2 — Lire le manifest

```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: campus-backend
  name: campus-backend
spec:
  ports:
  - port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    app: campus-backend
  type: ClusterIP
status:
  loadBalancer: {}
```

**1.** `spec.type: ClusterIP`.

**2.** Dans `spec.ports` : `port: 8080` est le port du Service, `targetPort: 8080` le port du conteneur.

**3.** `kubectl expose deployment` a **recopié le sélecteur du Deployment** (`spec.selector.matchLabels`). Il désigne les pods qui recevront le trafic : tous ceux qui portent le label `app: campus-backend`, quel que soit leur nom.

**4.** Oui, le Service serait créé : l'API Server ne vérifie pas qu'un pod correspond au sélecteur. Mais il ne recevrait **aucun trafic** utile : aucun pod ne porte `app: campus-backnd`, sa liste d'Endpoints serait vide et les connexions échoueraient (`Connection refused` ou délai dépassé).

> **Pourquoi ?** L'API Server ne valide que la syntaxe du manifeste. Un Service peut légitimement exister avant ses pods, ou entre deux rollouts. Le contrôleur d'Endpoints compare ensuite en continu le sélecteur aux labels des pods. Sans correspondance, la liste reste vide : le DNS résout bien la ClusterIP, mais aucun pod n'est derrière.
>
> **Diagnostic :** `kubectl get endpoints campus-backend` affiche `<none>`. Comparez alors le sélecteur (`kubectl describe svc campus-backend`) aux labels des pods (`kubectl get pods --show-labels`). Corrigez le sélecteur et refaites `kubectl apply` : les Endpoints se remplissent aussitôt, sans redémarrer les pods.

### Étape 3 — Vérifier l'adresse du Service et ses Endpoints

```bash
kubectl get endpoints campus-backend
```
```
NAME             ENDPOINTS                                                     AGE
campus-backend   192.168.140.12:8080,192.168.140.15:8080,192.168.230.17:8080   1s
```

**1.**

```bash
kubectl get svc campus-backend
```
```
NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
campus-backend   ClusterIP   10.109.242.31   <none>        8080/TCP   5s
```
La `CLUSTER-IP` est dans la plage des Services (`10.96.0.0/12` par défaut avec kubeadm), distincte de celle des pods.

**2.** Les Endpoints sont **exactement** les adresses IP des 3 pods backend **actuels** (y compris le pod recréé à l'exercice 1, pas celui supprimé), suivies du `targetPort` `8080`.

**3.** Non : la `CLUSTER-IP` est une adresse **virtuelle**, portée par aucun pod ni aucune interface. `kube-proxy` programme chaque nœud pour que le trafic envoyé à `CLUSTER-IP:8080` soit redirigé vers l'un des Endpoints. La liste des Endpoints, elle, ne contient que des adresses de pods réels.

### Étape 4 — Vérifier la stabilité du Service

```bash
kubectl delete pod campus-backend-c9c4d5fdf-sbgk9
kubectl get pods -l app=campus-backend -w        # attendre le remplaçant Running, puis Ctrl + C
kubectl get svc campus-backend
kubectl get endpoints campus-backend
```
```
NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
campus-backend   ClusterIP   10.109.242.31   <none>        8080/TCP   2m

NAME             ENDPOINTS                                                     AGE
campus-backend   192.168.140.15:8080,192.168.140.21:8080,192.168.230.17:8080   2m
```

**1.** Non : la `CLUSTER-IP` (`10.109.242.31`) reste fixe pendant toute la vie du Service.

**2.** Oui : l'adresse du pod supprimé (`192.168.140.12`) a disparu, celle du nouveau pod (`192.168.140.21`) est apparue. C'est le **contrôleur Endpoints** (dans le `kube-controller-manager`) qui la met à jour.

**3.** Non : le client appelle toujours la même adresse (et, à l'exercice 3, le même nom). La recréation du pod lui est invisible.

---

## Exercice 3 — Joindre un Service par son nom (DNS)

### Étape 1 — Appeler le backend par son nom

Commandes données dans l'énoncé. Réponse des deux `curl` :

```json
{"status":"UP","components":{"db":{"status":"UP","details":{"database":"PostgreSQL","validationQuery":"isValid()"}},"diskSpace":{"status":"UP",...},"livenessState":{"status":"UP"},"ping":{"status":"UP"},"readinessState":{"status":"UP"}},"groups":["liveness","readiness"]}
```

**1.** `"status":"UP"`, avec `"db":{"status":"UP"}` : l'API répond et joint aussi sa base.

**2.** Non : le DNS du cluster (CoreDNS) traduit le nom en `CLUSTER-IP`, puis `kube-proxy` redirige vers un pod.

**3.** Oui. Le nom court `campus-backend` est complété automatiquement avec le namespace du pod de test (`campus-dev`) ; le nom complet `campus-backend.campus-dev.svc.cluster.local` désigne le même Service.

**4.** `postgres` est le **nom du Service** de la base, dans le même namespace `campus-dev` (créé par le starter). Le backend n'utilise jamais l'adresse IP du pod PostgreSQL.

Erreurs fréquentes :
* `curl: (6) Could not resolve host` : faute de frappe dans le nom, ou pod de test créé dans un autre namespace (namespace courant non défini à l'étape 0).
* `curl: (7) Failed to connect … Connection refused` de temps en temps : le pod recréé à l'étape 4 de l'exercice 2 figure déjà dans les Endpoints mais Spring Boot n'a pas fini de démarrer (pas de sonde de disponibilité avant l'Atelier 07). Attendre et relancer.
* Message `warning: couldn't attach to pod/test-dns, falling back to streaming logs` : sans conséquence.

---

## Exercice 4 — Exposer le frontend hors du cluster (NodePort)

### Étape 1 — Déployer le frontend

**1.**

Linux / macOS, Git Bash, PowerShell 7 :

```bash
kubectl create deployment campus-frontend --image=regaieg/campus:frontend-1.0.0 --replicas=2 --port=8080 --dry-run=client -o yaml > deployment-frontend.yaml
```

Windows PowerShell 5.1 :

```powershell
kubectl create deployment campus-frontend --image=regaieg/campus:frontend-1.0.0 --replicas=2 --port=8080 --dry-run=client -o yaml | Out-File -Encoding utf8 deployment-frontend.yaml
```

**2.**

```bash
kubectl apply -f deployment-frontend.yaml
```
Attendu : `deployment.apps/campus-frontend created`, puis 2 pods `Running`. `kubectl create deployment` pose automatiquement le label `app: campus-frontend`, attendu par le sélecteur du Service de l'étape 2.

**3.** Le Nginx du frontend relaie `/api/` vers l'hôte `campus-backend:8080` et vérifie ce nom au démarrage. À l'Atelier 02, ce nom n'existait pas : `hostAliases` le simulait. Il désigne maintenant le **Service** `campus-backend` (exercice 2), que CoreDNS résout.

Erreur fréquente : déployer le frontend **avant** de créer le Service `campus-backend`. Les pods partent en `CrashLoopBackOff` (`host not found in upstream "campus-backend"`). Il suffit de créer le Service : les pods redémarrent seuls et finissent `Running`.

### Étape 2 — Créer le Service NodePort

**1.**

```bash
kubectl apply -f service-frontend.yaml
kubectl get services
```
```
NAME                  TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
campus-backend        ClusterIP   10.109.242.31   <none>        8080/TCP       5m
campus-frontend-svc   NodePort    10.101.5.60     <none>        80:30088/TCP   1s
postgres              ClusterIP   10.107.175.83   <none>        5432/TCP       7m
```

**2.** **3 Services** : `campus-backend` (`ClusterIP`), `postgres` (`ClusterIP`, créé par le starter) et `campus-frontend-svc` (`NodePort`).

**3.** `80:30088/TCP` : le Service écoute sur le port `80` de sa `CLUSTER-IP` (`port`) et sur le port `30088` de **chaque nœud** (`nodePort`), en TCP. Le `targetPort` (8080) n'apparaît pas dans cette colonne.

**4.** Oui (`10.101.5.60`) : un Service `NodePort` **est** un `ClusterIP` auquel Kubernetes ajoute un port ouvert sur chaque nœud. Les autres pods peuvent donc toujours le joindre par son nom (`http://campus-frontend-svc/`).

Erreur fréquente : `nodePort: 30080` → `provided port is already allocated` (port réservé à l'Ingress NGINX). Une valeur hors de la plage 30000-32767 est refusée (`provided port is not in the valid range`).

### Étape 3 — Distinguer les 3 ports d'un Service NodePort

**1.** ① `targetPort: 8080` : le port sur lequel Nginx écoute dans le conteneur.

**2.** ② `port: 80` : le port de la `CLUSTER-IP`, utilisé par les autres pods.

**3.** ③ `nodePort: 30088` : ouvert sur chaque nœud, joignable de l'extérieur, dans la plage **30000-32767**.

**4.** **`nodePort` (30088, sur le nœud) → `port` (80, sur le Service) → `targetPort` (8080, dans le pod).**

### Étape 4 — Accéder à l'application depuis votre navigateur

**1.** Oui : le tableau de bord, les offres de stage, les départements et les candidatures s'affichent. Ces données viennent de **PostgreSQL** : la page appelle `/api/…`, que Nginx relaie au backend, qui interroge la base (données de démonstration insérées au démarrage du backend).

**2.** **navigateur → `nodePort` 30088 de `k8s-worker-1` → Service `campus-frontend-svc` → pod frontend (Nginx) → Service `campus-backend` → pod API → Service `postgres` → pod PostgreSQL.**

Erreur fréquente (constatée en préparation) : utiliser les IP publiques notées lors d'une session précédente, ou celles affichées par un `terraform output` non rafraîchi. Les IP publiques des workers changent à chaque redémarrage de la session AWS : la page ne répond pas (délai dépassé). Relever les IP actuelles dans la console AWS.

### Étape 5 — Constater que le NodePort est ouvert sur chaque nœud

**1.** Oui, le portail répond aussi via `k8s-worker-2`.

**2.**

```bash
kubectl get pods -l app=campus-frontend -o wide
```

**3.** Oui : `kube-proxy` ouvre le port `30088` sur **tous** les nœuds, y compris ceux qui n'hébergent aucun pod frontend, et même sur `k8s-control` (vérifié en préparation : réponse `200` sur `http://<IP_control_plane>:30088`). Le nœud qui reçoit la requête la transmet à l'un des pods du Service, où qu'il se trouve.

---

## Critères de validation — commandes de contrôle

```bash
kubectl get pods -l app=campus-backend -o wide           # 3 pods, IP 192.168.x.x
kubectl get svc                                          # campus-backend (ClusterIP), postgres (ClusterIP), campus-frontend-svc (NodePort 80:30088)
kubectl get endpoints campus-backend                     # 3 adresses de pods en :8080
kubectl run test-dns --image=curlimages/curl:8.11.1 --rm -i --restart=Never -- curl -s http://campus-backend.campus-dev.svc.cluster.local:8080/actuator/health   # "status":"UP"
curl -s -o /dev/null -w "%{http_code}\n" http://<IP_PUBLIQUE_WORKER>:30088/   # 200 sur chacun des deux workers
```

## État de fin de lab

Identique à la version courte : `service-backend.yaml`, `deployment-frontend.yaml`, `service-frontend.yaml` ; PostgreSQL de développement, backend en 3 réplicas, frontend en 2 réplicas, Services `campus-backend`, `postgres` et `campus-frontend-svc` (NodePort 30088). Le starter de l'Atelier 05 repart de cet état.
