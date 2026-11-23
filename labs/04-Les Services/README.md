# Atelier 04 : Réseau, Services & Découverte DNS

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

🛟 **Secours : Minikube sur votre poste** (session AWS indisponible), piloté forcément depuis votre poste comme en Option A. Tout fonctionne à l'identique, sauf l'accès navigateur de l'étape 3 de l'exercice 3, pour lequel un encadré dédié est fourni.

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

Inutile d'attendre la fin du démarrage de l'API pour commencer l'exercice 1 : vous vérifierez qu'elle répond juste avant l'exercice 2.

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Un redémarrage au premier lancement est normal</strong></p>

Les pods créent en même temps les tables de la base neuve : l'un d'eux peut échouer (`relation ... already exists`) avant de repartir.

</div>

---

## Exercice 1 : Du pod instable au Service stable

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Chaque pod reçoit sa propre adresse IP, mais cette adresse disparaît avec lui. Un **Service** offre une adresse et un nom **stables** devant un groupe de pods, qu'il retrouve grâce à leurs **labels**.

</div>

### Étape 1 : Repérer les adresses IP des pods backend

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande liste les pods portant le label `app=campus-backend`, **avec leur adresse IP et leur nœud** ? Notez les adresses affichées.

</div>

<details class="tip" markdown>
<summary><strong>Indice : qui attribue ces adresses ?</strong></summary>

L'option qui ajoute les colonnes `IP` et `NODE` a déjà servi à l'Atelier 02 et à l'Atelier 03.

Chaque pod reçoit son adresse à sa création (plage `192.168.x.x`), attribuée par le plugin réseau (**CNI**) : Calico sur votre cluster. Les pods répartis sur les deux workers se joignent directement, d'un nœud à l'autre, sans traduction d'adresse (NAT).

</details>

### Étape 2 : Générer et créer le Service

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
| `--port=8080` | Port exposé par le Service (`spec.ports.port`) |
| `--target-port=8080` | Port sur lequel écoute le conteneur (`spec.ports.targetPort`) |
| `--type=ClusterIP` | Service interne, joignable uniquement depuis le cluster (type par défaut, `spec.type`) |
| `--dry-run=client -o yaml` | Construit l'objet sans l'envoyer au cluster et l'affiche en YAML |

Ouvrez `service-backend.yaml` dans votre éditeur.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande crée le Service à partir de votre fichier, de manière **déclarative** ?
2. Vous n'avez écrit aucun label dans votre commande. Pourtant, la section `spec.selector` contient `app: campus-backend`. D'où vient-elle ? À quoi sert-elle ?
3. Si le sélecteur contenait par erreur `app: campus-backnd`, le Service serait-il créé ? Recevrait-il du trafic ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : pas d'étiquette, pas de trafic</strong></summary>

Un Service et ses pods sont découplés : seul le sélecteur de labels les relie. Si aucun pod ne correspond au sélecteur, le Service existe bien, mais il ne transmet rien. `kubectl explain service.spec` détaille chaque champ.

</details>

### Étape 3 : Vérifier l'adresse du Service et ses Endpoints

Les Services s'abrègent `svc` dans `kubectl`. La liste des adresses de pods vers lesquelles le Service envoie le trafic s'appelle ses **Endpoints**. Affichez les deux d'un coup :

```bash
kubectl get svc,endpoints campus-backend
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Notez l'adresse IP virtuelle du Service (colonne `CLUSTER-IP`). Comparez les Endpoints avec les adresses de vos pods (étape 1) : que constatez-vous ?
2. L'adresse `CLUSTER-IP` fait-elle partie de la liste des Endpoints ? Pourquoi ?

</div>

### Étape 4 : Supprimer un pod et comparer

Supprimez l'un des pods backend, puis relancez la commande de l'étape 1 et celle de l'étape 3.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande supprime l'un des pods ?
2. Le pod recréé a-t-il repris le **nom** et l'**adresse IP** du pod supprimé ?
3. La `CLUSTER-IP` du Service a-t-elle changé ? Et la liste des Endpoints ?
4. Conclusion : pourquoi le frontend doit-il appeler le Service plutôt que l'adresse IP d'un pod ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : Service stable, Endpoints vivants</strong></summary>

Le ReplicaSet recrée le pod manquant (Atelier 03), avec un nouveau nom et une nouvelle adresse. Kubernetes surveille en permanence les pods qui correspondent au sélecteur du Service et met à jour la liste des Endpoints. L'adresse du Service, elle, reste fixe pendant toute sa vie : c'est elle que les clients utilisent.

</details>

---

## Exercice 2 : Joindre un Service par son nom (DNS)

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Kubernetes donne un **nom** à chaque Service. Les applications s'appellent par ce nom, jamais par une adresse IP.

</div>

### Étape 1 : Vérifier que l'API a démarré

L'API n'a pas de sonde de santé : un pod `Running` n'est pas forcément prêt, car Spring Boot met 20 secondes à 2 minutes à démarrer. Vérifiez que chaque pod backend a bien démarré :

**Linux / macOS**

```bash
kubectl logs -l app=campus-backend --prefix --tail=-1 | grep "Started CampusOpsApplication"
```

**Windows (PowerShell)**

```powershell
kubectl logs -l app=campus-backend --prefix --tail=-1 | Select-String "Started CampusOpsApplication"
```

Relancez la commande jusqu'à obtenir **3 lignes**, une par pod backend.

### Étape 2 : Appeler le backend par son nom

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

1. Le nom court et le nom complet donnent-ils la même réponse ? Avez-vous eu besoin d'une adresse IP ?
2. Le backend se connecte à sa base avec l'adresse `jdbc:postgresql://postgres:5432/campus`. À quoi correspond le nom `postgres` ?

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
* **`Connection refused` de temps en temps :** un pod backend n'a pas fini de démarrer. Refaites l'étape 1, puis relancez la commande.

</details>

---

## Exercice 3 : Exposer le frontend hors du cluster (NodePort)

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un Service `ClusterIP` n'est joignable que depuis le cluster. Pour ouvrir l'application à un navigateur, on utilise un Service `NodePort`, qui ouvre un port sur **chaque** nœud.

</div>

### Étape 1 : Déployer le frontend

Générez le manifest du Deployment frontend (2 réplicas), puis appliquez-le :

**Linux / macOS, Git Bash, PowerShell 7**

```bash
kubectl create deployment campus-frontend --image=regaieg/campus:frontend-1.0.0 --replicas=2 --port=8080 --dry-run=client -o yaml > deployment-frontend.yaml
kubectl apply -f deployment-frontend.yaml
```

**Windows PowerShell 5.1**

```powershell
kubectl create deployment campus-frontend --image=regaieg/campus:frontend-1.0.0 --replicas=2 --port=8080 --dry-run=client -o yaml | Out-File -Encoding utf8 deployment-frontend.yaml
kubectl apply -f deployment-frontend.yaml
```

<details class="tip" markdown>
<summary><strong>Indice : et le <code>hostAliases</code> de l'Atelier 02 ?</strong></summary>

Le Nginx du frontend relaie les appels `/api/` vers l'hôte `campus-backend:8080` et vérifie ce nom au démarrage. À l'Atelier 02, ce nom n'existait pas : `hostAliases` le simulait. Il désigne maintenant le Service créé à l'exercice 1, que le DNS du cluster résout.

</details>

### Étape 2 : Créer le Service NodePort

Créez un fichier `service-frontend.yaml`, puis appliquez-le :

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
2. Que signifie la valeur `80:30088/TCP` affichée pour `campus-frontend-svc` ? Ce Service possède-t-il lui aussi une `CLUSTER-IP` ?
3. Parmi ①, ② et ③ : lequel est le port d'écoute du conteneur ? Lequel utilisent les autres pods ? Lequel est joignable depuis l'extérieur, et dans quelle plage doit-il se trouver ?
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
<p class="admonition-title"><strong>Quel type de Service choisir ?</strong></p>

| Besoin | Type de Service |
| :--- | :--- |
| Trafic interne au cluster | `ClusterIP` |
| Accès externe sur notre cluster | `NodePort` |
| Production dans le cloud (EKS, AKS, GKE) | `LoadBalancer` (resterait en `EXTERNAL-IP <pending>` sur notre cluster kubeadm) |

</div>

### Étape 3 : Accéder à l'application depuis votre navigateur

Récupérez les adresses IP publiques de vos deux workers (affichées par `start-session` ou dans la console AWS), puis ouvrez successivement **`http://<IP_PUBLIQUE_k8s-worker-1>:30088`** et **`http://<IP_PUBLIQUE_k8s-worker-2>:30088`**.

<div class="admonition warning" markdown>
<p class="admonition-title"><strong>Les IP publiques changent à chaque redémarrage de la session AWS</strong></p>

Relevez-les à nouveau dans la console AWS au début de chaque séance : une ancienne adresse ne répond plus.

</div>

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Le portail affiche-t-il les offres de stage sur les deux adresses ? D'où viennent ces données ?
2. Citez, dans l'ordre, les objets traversés par une requête, du navigateur jusqu'à la base de données.
3. Un nœud qui n'héberge **aucun** pod frontend répondrait-il quand même ? Pourquoi ?

</div>

<details class="example" markdown>
<summary><strong>Vous êtes sur Minikube (secours) ?</strong></summary>

Avec le pilote Docker sous Windows ou macOS, l'adresse du nœud Minikube n'est pas joignable depuis votre poste. Remplacez cette étape par un tunnel vers le Service :

```bash
minikube service campus-frontend-svc -n campus-dev --url
```

La commande affiche une adresse `http://127.0.0.1:<port>` : ouvrez-la dans votre navigateur et **laissez le terminal ouvert** tant que vous l'utilisez (`Ctrl + C` pour fermer le tunnel). Minikube n'a qu'un seul nœud : une seule adresse à tester.

</details>

<details class="tip" markdown>
<summary><strong>Indice : le chemin complet d'une requête</strong></summary>

**navigateur → NodePort `30088` d'un nœud → Service `campus-frontend-svc` → pod frontend (Nginx) → Service `campus-backend` → pod API → Service `postgres` → base**.

Le port `30088` est ouvert sur **tous** les nœuds, qu'ils hébergent ou non un pod frontend : le nœud qui reçoit la requête la transmet à l'un des pods sélectionnés par le Service, où qu'il se trouve.

</details>

<details class="tip" markdown>
<summary><strong>Indice : la page ne s'affiche pas ou le tableau de bord reste vide</strong></summary>

* **Le navigateur n'obtient aucune réponse :** utilisez l'IP **publique** d'un worker (pas l'IP privée `172.31.x.x`) et le port `30088`. Les IP publiques changent à chaque redémarrage de la session AWS.
* **Le port est bloqué par le pare-feu de votre entreprise (Option A) :** passez par un tunnel, comme à l'[Atelier 02](../02-Les%20Pods/README.md) : `kubectl port-forward svc/campus-frontend-svc 8081:80` lancé **depuis votre poste**, puis ouvrez `http://localhost:8081`. En Option B, ce tunnel s'ouvrirait sur `k8s-control` et non sur votre poste : il ne vous aiderait pas.
* **La page s'affiche mais les données sont absentes :** testez l'API à travers le frontend avec `curl http://<IP_PUBLIQUE_WORKER>:30088/actuator/health`. Une erreur `502 Bad Gateway` signifie que le Service `campus-backend` ne transmet rien : appliquez le réflexe **« Service muet ? `kubectl get endpoints` »**. Une liste vide signifie que le sélecteur du Service et les labels des pods ne correspondent pas.

</details>

---

## Critères de Validation (Checklist)

- [ ] Vous avez constaté qu'un pod recréé change d'adresse IP (`kubectl get pods -o wide`).
- [ ] `campus-backend` est un Service `ClusterIP` dont les Endpoints listent les pods backend, et vous savez qu'une liste vide signale un sélecteur qui ne correspond à aucun label (`kubectl get endpoints campus-backend`).
- [ ] `campus-backend` répond par son nom court et par son nom complet `campus-backend.campus-dev.svc.cluster.local`.
- [ ] `campus-frontend-svc` est exposé en `NodePort` sur le port `30088` et le portail s'affiche dans le navigateur via l'IP de chacun des deux workers.
- [ ] Vous distinguez `targetPort` (8080), `port` (80) et `nodePort` (30088).
