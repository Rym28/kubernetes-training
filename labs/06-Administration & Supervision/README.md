# Atelier 06 : Exploitation, Observabilité & Reverse Debugging

### Objectifs Pédagogiques :
* Lire les logs d'une application (`kubectl logs` en direct, multi-pods, conteneur précédent) et la chronologie des événements du cluster.
* Exécuter une commande dans un conteneur avec `kubectl exec` pour vérifier la configuration qu'il a reçue.
* Appliquer une méthode de dépannage, du général au détail, sur 2 incidents classiques : `CrashLoopBackOff` et `OOMKilled`.
* Détecter une panne du système d'un nœud avec **Node Problem Detector** et retirer ce nœud du service (`kubectl cordon`).
* Mesurer la consommation avec **Metrics Server** (`kubectl top`), collecter métriques et logs avec **Prometheus**, **Fluent Bit** et **Loki**, et les consulter dans **Grafana**.
* *(Optionnel)* Superviser et dépanner le cluster depuis votre poste avec l'IDE graphique **FreeLens**, connecté par votre kubeconfig.
* Situer cette pile par rapport aux services managés des clouds, dont **StackDriver** (aujourd'hui Google Cloud Observability).

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Compatibilité OS</strong></p>

Les commandes de cet atelier sont **rigoureusement identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)** : les manifests sont fournis en fichiers dans `manifests/`, `npd/` et `monitoring/`. Quand une commande diffère, les deux variantes sont fournies.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Environnement : le cluster 3 nœuds (1 control plane + 2 workers) de l'Atelier 01</strong></p>

Node Problem Detector surveille les **workers**, et l'étape 3 de l'exercice 3 en retire un du service : réalisez ce lab sur ce cluster, piloté au choix :

* **Option A (Recommandée - Confort DevOps Local) :** depuis votre machine locale, avec votre `kubectl` et votre `kubeconfig`. Dans **chaque nouveau terminal**, placé à la racine du dépôt, pointez d'abord `kubectl` vers le fichier `kubeconfig.yaml` récupéré à l'étape 1 de l'exercice 4 de l'Atelier 01 :
    * Windows (PowerShell) : `$env:KUBECONFIG = "$PWD\labs\01-Installation-Cluster\terraform\kubeconfig.yaml"`
    * Linux / macOS (Bash) : `export KUBECONFIG=$PWD/labs/01-Installation-Cluster/terraform/kubeconfig.yaml`
    * Vérification : `kubectl get nodes` doit afficher les 3 nœuds à l'état `Ready`.
* **Option B (PC d'entreprise verrouillé) :** en SSH sur `k8s-control` : l'outillage et les manifests sont pré-installés dans `~/labs/`.

🛟 **Secours : Minikube sur votre poste** (session AWS indisponible), piloté forcément depuis votre poste comme en Option A. Remplacez `k8s-worker-1` par `minikube`, y compris dans `manifests/inject-kernel-err.yaml`. Pour ouvrir Grafana (étape 3 de l'exercice 4), utilisez `minikube service grafana -n monitoring --url`.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Namespace de travail : <code>campus-dev</code></strong></p>

Ce lab est **indépendant des autres** : son étape 0 crée `campus-dev` s'il n'existe pas encore, puis y installe ou met à jour tout ce dont il a besoin. Vous pouvez le réaliser sans avoir fait les labs précédents ; pour le recommencer à zéro, utilisez l'encadré « Repartir de zéro » de l'étape 0.

</div>

---

## Contexte Métier
Le Campus Summer Portal est en production. L'administrateur doit trouver la cause d'une panne de pod ou de nœud, puis suivre en continu la consommation et les logs de tout le cluster. Il se pose trois questions ; on commence toujours par `kubectl`, puis on outille : historique, alertes, tableaux de bord.

| Question | Outils de base | Outils de supervision |
| :--- | :--- | :--- |
| **Logs** : que raconte l'application ? | `kubectl logs`, `kubectl exec` | Fluent Bit + Loki |
| **État** : le nœud est-il sain ? | `kubectl describe node`, événements | Node Problem Detector |
| **Métriques** : combien consomme-t-elle ? | `kubectl top` (Metrics Server) | Prometheus + Grafana |

<div class="admonition tip" markdown>
<p class="admonition-title"><strong>Mode d'emploi</strong></p>

* Les encadrés rouges **« À vous de répondre »** contiennent les questions. Pour les commandes déjà vues dans les labs précédents, on vous demande la commande au lieu de vous la donner : cherchez avec `kubectl --help`, `kubectl <commande> --help` ou `kubectl explain`.
* Les commandes nouvelles sont données.
* Les encadrés **« Indice »** sont repliés : cliquez dessus seulement si vous bloquez.

</div>

---

## Étape 0 : Préparer l'environnement

Le dossier `starter/` du lab installe l'application complète, dans l'état de fin de l'Atelier 07 (réalisé avant celui-ci) :

| Fichier | Contenu |
| :--- | :--- |
| `01-config.yaml` | Le ConfigMap `campus-config` (paramètres non sensibles de l'API). |
| `02-postgres.yaml` | Le PV `pv-postgres`, le PVC `pvc-postgres`, la base PostgreSQL persistante et son Service `postgres`. |
| `03-backend.yaml` | L'API `campus-backend` (2 réplicas, configuration lue dans le ConfigMap et le Secret, sondes de santé, conteneur non-root et ressources déclarées) et son Service `campus-backend`. |
| `04-frontend.yaml` | Le frontend et son Service NodePort `campus-frontend-svc` (port `30088`). |

Les identifiants de la base ne sont **pas** versionnés dans le starter : vous créez le Secret `campus-db-credentials` par une commande, comme à l'Atelier 05.

Créez le namespace `campus-dev` s'il n'existe pas encore, sélectionnez-le, puis appliquez le starter. Si vous sortez du lab précédent, vos objets sont conservés et simplement mis à jour. Depuis la racine du dépôt (Option A) ou depuis `~` sur `k8s-control` (Option B : mettez d'abord le dépôt à jour avec `git -C ~/formation pull`, puis remplacez `labs/` par `~/labs/`) :

```bash
kubectl create namespace campus-dev --dry-run=client -o yaml | kubectl apply -f -   # sans effet s'il existe déjà
kubectl config set-context --current --namespace=campus-dev
kubectl create secret generic campus-db-credentials --from-literal=POSTGRES_DB=campus --from-literal=POSTGRES_USER=campus --from-literal='POSTGRES_PASSWORD=CampusSecret2026!' --dry-run=client -o yaml | kubectl apply -f -
kubectl delete networkpolicy,resourcequota,limitrange --all   # contraintes de l'Atelier 07 : elles bloqueraient les incidents simulés
kubectl apply -f "labs/06-Administration & Supervision/starter/"
kubectl rollout status deployment/campus-postgres --timeout=180s
kubectl rollout status deployment/campus-backend --timeout=300s
```

<details class="warning" markdown>
<summary><strong>Environnement incohérent ou lab à recommencer ? Repartez de zéro</strong></summary>

Supprimez le namespace et tout son contenu, puis relancez les commandes ci-dessus :

```bash
kubectl delete namespace campus-dev   # ⚠️ supprime tout le contenu de campus-dev
kubectl delete pv pv-postgres --ignore-not-found   # le PV n'appartient à aucun namespace
```

*La suppression peut prendre jusqu'à une minute : `kubectl` rend la main quand elle est terminée.*

</details>

`kubectl delete` affiche `No resources found` si vous n'avez pas fait l'Atelier 07 : c'est attendu. Le backend a des sondes de santé : `rollout status` rend la main quand Spring Boot a fini de démarrer (20 secondes à 2 minutes).

Placez-vous ensuite dans le dossier du lab, qui contient les fichiers `manifests/`, `npd/` et `monitoring/` utilisés plus loin : `cd "labs/06-Administration & Supervision"` (Option A) ou `cd ~/"labs/06-Administration & Supervision"` (Option B).

Lancez enfin **dès maintenant** la pile de supervision de l'exercice 4. Elle télécharge ses images et démarre pendant que vous faites les exercices 1 à 3 ; elle enregistrera aussi les logs des incidents de l'exercice 2. Inutile d'attendre : passez directement à l'exercice 1.

```bash
kubectl apply -f monitoring/00-namespace.yaml -f monitoring/01-metrics-server.yaml -f monitoring/02-loki.yaml -f monitoring/03-fluentbit.yaml -f monitoring/04-prometheus.yaml -f monitoring/05-grafana.yaml
```

---

## Exercice 1 : Lire les logs et les événements, entrer dans un conteneur

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Les **logs** sont les messages qu'une application écrit sur sa sortie standard ; Kubernetes les conserve pour chaque conteneur. Les **événements** retracent ce que le cluster a fait : placement d'un pod, téléchargement d'image, redémarrage, erreur. Quand ils ne suffisent pas, `kubectl exec` lance une commande **dans** le conteneur pour vérifier ce qu'il voit.

</div>

### Étape 1 : Lire les logs du backend

La première commande affiche les 20 dernières lignes (`--tail=20`), puis suit les nouvelles en direct (`-f`, *follow*) : quittez avec `Ctrl + C`. La seconde lit les logs de **tous** les pods portant l'étiquette `app=campus-backend` ; `--prefix` indique devant chaque ligne le pod d'où elle vient :

```bash
kubectl logs -f deployment/campus-backend --tail=20
kubectl logs -l app=campus-backend --tail=5 --prefix
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle ligne indique que Spring Boot a fini de démarrer ? En combien de secondes ?
2. Le Deployment a 2 pods : de combien de pods viennent les lignes de la première commande ? Et celles de la seconde ?

</div>

### Étape 2 : Lire la chronologie des événements

Les événements du namespace, triés par date de création :

```bash
kubectl get events --sort-by=.metadata.creationTimestamp
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelles raisons (colonne `REASON`) retrouvez-vous pour la création d'un pod, dans l'ordre ?
2. Les logs d'un pod supprimé sont-ils encore lisibles avec `kubectl logs` ? Que faut-il pour les conserver ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : des logs qui meurent avec le pod</strong></summary>

Un pod crée successivement les événements `Scheduled` (placé sur un nœud), `Pulled` (image disponible), `Created` puis `Started` (conteneur lancé).

Les logs d'un pod **meurent avec lui**. En production, on les centralise hors du cluster : c'est le rôle de Fluent Bit et Loki (exercice 4).

</details>

### Étape 3 : Vérifier la configuration reçue par le backend

Vous avez utilisé `kubectl exec` à l'Atelier 02. Vous voulez exécuter `env | grep SPRING` dans un pod du Deployment `campus-backend`.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande exécute `env | grep SPRING` dans le backend ?
2. Quelle URL de base de données l'application a-t-elle reçue ?
3. La variable `SPRING_DATASOURCE_PASSWORD` s'affiche-t-elle en clair ? Qu'en concluez-vous sur les droits `exec` ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : une commande avec un « | » dans le conteneur</strong></summary>

Tout ce qui suit `--` s'exécute dans le conteneur. Le `|` serait interprété par **votre** terminal : encapsulez la commande dans `sh -c "…"`, comme pour `cat /etc/hosts` à l'Atelier 02. On peut viser le Deployment directement (`deployment/campus-backend`) : `kubectl` choisit l'un de ses pods.

</details>

<div class="admonition warning" markdown>
<p class="admonition-title"><strong><code>exec</code> sert à observer, pas à corriger</strong></p>

Toute modification faite dans le conteneur disparaît au prochain redémarrage du pod : on corrige le manifest, jamais le conteneur en direct. Pour un terminal interactif : `kubectl exec -it deployment/campus-backend -- sh` (quittez avec `exit`).

</div>

---

## Exercice 2 : Dépanner avec méthode

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Face à un incident, on suit toujours le même ordre, du général au détail. Le statut du pod oriente vers le bon outil.

</div>

| Étape | Commande | Ce que vous cherchez |
| :--- | :--- | :--- |
| 1. Voir | `kubectl get pods -o wide` | `STATUS`, `RESTARTS`, `NODE` |
| 2. Comprendre | `kubectl describe pod <pod>` | Les `Events` (placement, image) et le `Last State` du conteneur |
| 3. Lire | `kubectl logs <pod> --previous` | L'erreur écrite par l'application |
| 4. Entrer | `kubectl exec <pod> -- …` | La configuration et le réseau vus du pod |
| 5. Élargir | `kubectl describe node`, `kubectl top` | Le nœud, les ressources |

### Étape 1 : Deux pods qui redémarrent en boucle

Vous lancez deux pods défaillants **en même temps** et les observez ensemble (`Ctrl + C` pour quitter) :

* **Incident A**, `crash-app` : l'image `busybox` exécute un script qui affiche deux messages puis s'arrête avec le code d'erreur 42 ;
* **Incident B**, `oom-victim` (`manifests/oom-victim.yaml`) : un conteneur limité à 50 Mi de mémoire (`limits.memory`) tente d'en allouer 150 Mo.

```bash
kubectl run crash-app --image=busybox:1.36 -- sh -c "echo Demarrage; sleep 3; echo Erreur fatale; exit 42"
kubectl apply -f manifests/oom-victim.yaml
kubectl get pods crash-app oom-victim -w
```

Au bout d'une minute environ, les deux pods affichent `CrashLoopBackOff` : ils redémarrent en boucle, mais pas pour la même raison.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Par quels statuts passe chaque pod ? Que fait la colonne `RESTARTS` ?
2. Quelle commande affiche la section `Last State` du conteneur d'un pod ? Pour chacun des deux pods, quels `Reason` et `Exit Code` y lisez-vous ?
3. Que signifie un `Exit Code` différent de 0 ? Qui a tué le processus de `oom-victim` ?
4. Quelle commande affiche le message écrit par le conteneur de `crash-app` **qui a planté** ? Quel est ce message ?
5. Proposez deux corrections possibles pour `oom-victim`.
6. Supprimez les deux pods. Vous retrouverez les logs de `crash-app` à l'exercice 4, après sa suppression.

</div>

<details class="tip" markdown>
<summary><strong>Indice : <code>logs --previous</code> ne répond pas</strong></summary>

Si la commande répond `unable to retrieve container logs`, le pod est dans le court état `Error`, entre deux redémarrages : relancez-la quand il affiche `CrashLoopBackOff`. Le délai entre deux redémarrages double à chaque échec (10 s, 20 s, 40 s… jusqu'à 5 minutes).

</details>

---

## Exercice 3 : Détecter une panne de nœud

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Le `kubelet` ne surveille que la mémoire, le disque et le nombre de processus du nœud. Un blocage du noyau Linux ne rend pas le nœud `NotReady` : le scheduler continue d'y envoyer des pods. **Node Problem Detector** (NPD) lit les journaux système de chaque nœud et signale ces pannes dans les **conditions** du nœud. NPD détecte ; c'est l'administrateur qui retire le nœud du service.

</div>

### Étape 1 : Déployer Node Problem Detector

NPD tourne en **DaemonSet** : un controller qui place un pod sur chaque nœud.

```bash
kubectl apply -f npd/npd.yaml
kubectl rollout status daemonset/node-problem-detector -n kube-system
kubectl get pods -n kube-system -l app=node-problem-detector -o wide
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Combien de pods NPD voyez-vous, et sur quels nœuds ? Pourquoi aucun sur `k8s-control` ?
2. Quelle commande affiche la description du nœud `k8s-worker-1` ? Dans sa section `Conditions`, quelles conditions NPD a-t-il ajoutées, et avec quelle valeur ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : les nouvelles conditions n'apparaissent pas</strong></summary>

NPD publie ses conditions quelques secondes après son démarrage : relancez la commande. Le control plane porte une *taint* (`node-role.kubernetes.io/control-plane`) qui refuse les pods ordinaires.

</details>

### Étape 2 : Simuler une erreur du noyau sur `k8s-worker-1`

`manifests/inject-kernel-err.yaml` lance un pod **privilégié** (accès complet au nœud, réservé à cette simulation) qui écrit une fausse erreur dans le journal du noyau. NPD classe cette erreur en `KernelDeadlock`. `kubectl wait` attend que le pod ait terminé son écriture (statut `Succeeded`) avant de lire les événements :

```bash
kubectl apply -f manifests/inject-kernel-err.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/inject-kernel-err --timeout=60s
kubectl get events -A --field-selector reason=KernelDeadlock
kubectl delete pod inject-kernel-err
```

*Si `get events` ne renvoie rien, attendez quelques secondes et relancez-la : NPD lit le journal du noyau en continu.*

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Relisez les conditions de `k8s-worker-1` : quelle condition est passée à `True` ?
2. Le nœud est-il toujours `Ready` ? Pourquoi est-ce dangereux pour les prochains pods ?

</div>

### Étape 3 : Retirer le nœud du service

`kubectl cordon` marque un nœud comme non planifiable, sans toucher aux pods qui y tournent ; `kubectl uncordon` le remet en service :

```bash
kubectl cordon k8s-worker-1
kubectl get nodes
kubectl uncordon k8s-worker-1
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quel statut affiche `k8s-worker-1` après `cordon` ? Les pods qui y tournaient déjà ont-ils été déplacés ?

</div>

<div class="admonition info" markdown>
<p class="admonition-title"><strong><code>cordon</code> ou <code>drain</code> ?</strong></p>

`cordon` bloque l'arrivée de nouveaux pods. `kubectl drain k8s-worker-1 --ignore-daemonsets` fait un `cordon`, puis déplace les pods du nœud vers les autres nœuds : c'est la commande d'une maintenance. Nous ne la lançons pas ici pour ne pas déplacer la base de données, dont le volume est sur le disque du nœud (Atelier 05).

</div>

---

## Exercice 4 : Mesurer la consommation et centraliser les logs

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Pour suivre un cluster en continu, il faut collecter régulièrement les **métriques** (mémoire, CPU…) et les **logs** de tous les conteneurs, les conserver, et pouvoir les consulter après coup. C'est le rôle d'une pile de supervision.

</div>

| | Collecte | Stockage dans le temps | Consultation |
| :--- | :--- | :--- | :--- |
| **Métriques** | **Metrics Server** : consommation actuelle, affichée par `kubectl top` (pas installé par défaut avec kubeadm) | **Prometheus** | **Grafana** |
| **Logs** | **Fluent Bit** : un agent par nœud (DaemonSet) | **Loki** | **Grafana** |

### Étape 1 : Vérifier la pile de supervision

Vous avez lancé la pile à l'étape 0 : elle tourne depuis le début du lab. Tous les outils sont placés dans le namespace `monitoring`, sauf Metrics Server, qui rejoint les composants système dans `kube-system` :

```bash
kubectl get pods -n monitoring -o wide
kubectl get pods -n kube-system -l k8s-app=metrics-server
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Tous les pods sont-ils `Running` ? Quel objet Kubernetes a créé les pods `fluent-bit` ?
2. Combien de pods `fluent-bit` voyez-vous ? NPD (exercice 3) n'en a que 2 : pourquoi Fluent Bit en a-t-il un de plus ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : aucun pod dans <code>monitoring</code></strong></summary>

Vous avez sauté la dernière commande de l'étape 0 : lancez-la maintenant et attendez que les pods soient `Running` (1 à 2 minutes). Fluent Bit ne collecte que les lignes écrites **après** son démarrage : rejouez `crash-app` (étape 1 de l'exercice 2) pour avoir des logs à retrouver à l'étape 3.

</details>

### Étape 2 : Mesurer la consommation

Metrics Server relève les mesures toutes les 15 à 60 secondes : s'il vient de démarrer, `kubectl top` répond `metrics not available yet`. Attendez une minute et relancez.

```bash
kubectl top nodes
kubectl top pods
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Dans quelles unités s'affichent le CPU et la mémoire ? Que vaut `250m` ?
2. Quel pod de `campus-dev` consomme le plus de mémoire ?
3. Ces valeurs sont-elles celles déclarées dans les manifests, ou la consommation réelle ?

</div>

### Étape 3 : Consulter métriques et logs dans Grafana

Ouvrez **`http://<IP_PUBLIQUE_D_UN_WORKER>:30300`** et connectez-vous avec `admin` / `admin2026`. Grafana est déjà relié à Prometheus et à Loki. Ouvrez le menu **Explore**, puis :

* choisissez la source **Prometheus** et exécutez cette requête, qui additionne la mémoire utilisée par les conteneurs de `campus-dev`, pod par pod :

    ```promql
    sum(container_memory_working_set_bytes{namespace="campus-dev", container!=""}) by (pod)
    ```

* choisissez ensuite la source **Loki** et exécutez cette requête, qui sélectionne les logs du pod `crash-app` de l'exercice 2 (`kubectl run` lui a posé le label `run=crash-app`) :

    ```logql
    {run="crash-app"}
    ```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Combien de courbes affiche la requête Prometheus ? Retrouvez-vous l'ordre de grandeur de `kubectl top pods` ?
2. Dans Loki, retrouvez-vous les messages `Demarrage` et `Erreur fatale` de `crash-app` ? Ce pod a été supprimé à l'exercice 2 : pourquoi `kubectl logs crash-app` ne peut-il plus les afficher ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : Grafana ne s'affiche pas</strong></summary>

* Utilisez l'IP **publique** d'un worker ; elle change à chaque redémarrage de la session AWS.
* Si le port 30300 est filtré par votre réseau d'entreprise (Option A) : `kubectl port-forward svc/grafana 3000:3000 -n monitoring`, puis `http://localhost:3000`.
* Loki vide : Fluent Bit ne collecte que les logs écrits après son démarrage (étape 0). Élargissez la période en haut à droite (*Last 15 minutes* → *Last 1 hour*).

</details>

<div class="admonition info" markdown>
<p class="admonition-title"><strong>StackDriver et les clouds</strong></p>

Sur un cluster managé, cette pile est fournie par le cloud. Chez Google, ce service s'appelait **StackDriver** ; il se nomme aujourd'hui **Google Cloud Observability** (Cloud Logging pour les logs, Cloud Monitoring pour les métriques) et il est activé par défaut sur GKE. Les équivalents sont **CloudWatch** chez AWS et **Azure Monitor** chez Microsoft. Les principes sont les mêmes : un agent par nœud collecte logs et métriques, une interface les interroge.

</div>

---

## Exercice 5 (optionnel, ~10 min) : Superviser le cluster avec FreeLens

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

[**FreeLens**](https://freelensapp.github.io/) est une interface graphique installée sur **votre poste**. Comme `kubectl`, elle se connecte à l'API Server avec votre **kubeconfig** : elle affiche en clics ce que vous avez fait en ligne de commande.

</div>

### Étape 1 : Installer FreeLens et le connecter au cluster

1. Installez FreeLens depuis [freelensapp.github.io](https://freelensapp.github.io/), puis lancez-le.
2. Donnez-lui votre kubeconfig, `labs/01-Installation-Cluster/terraform/kubeconfig.yaml` (Atelier 01), au choix :
    * **File → Preferences → Kubernetes → Kubeconfig Syncs → Sync file(s)**, puis sélectionnez le fichier (recommandé : FreeLens suit le fichier quand vous le régénérez avec `get-kubeconfig`) ;
    * ou **Catalog → + → Add from kubeconfig**, puis collez le contenu du fichier.
3. Ouvrez le cluster dans **Catalog → Clusters** et choisissez le namespace `campus-dev`.

![Cluster connecté dans FreeLens](img/freelens-cluster.png)

<details class="tip" markdown>
<summary><strong>Indice : FreeLens ne se connecte pas</strong></summary>

* Testez le même fichier avec `kubectl get nodes`. S'il échoue aussi, l'IP publique a changé : régénérez le kubeconfig avec `get-kubeconfig`.
* Sinon, votre réseau bloque le port 6443 (fréquent en Option B) : contentez-vous de Grafana.

</details>

### Étape 2 : Retrouver les commandes du lab

| Dans FreeLens | Équivalent `kubectl` |
| :--- | :--- |
| **Workloads → Pods**, clic sur un pod : état, **Events**, icônes **Logs** et **Shell** | `get pods`, `describe pod`, `logs`, `exec -it` |
| **Nodes**, clic sur un nœud : **Conditions** ; menu **⋮** → **Cordon** / **Uncordon** | `describe node`, `cordon` / `uncordon` |

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Rejouez `crash-app` (étape 1 de l'exercice 2) : où lisez-vous dans FreeLens qu'il redémarre en boucle, et son message `Erreur fatale` ?
2. Faites **Cordon** sur `k8s-worker-1` depuis FreeLens : que renvoie `kubectl get nodes` ? Remettez le nœud en service avec **Uncordon**.

</div>

---

## Critères de Validation (Checklist)

- [ ] Vous savez lire les logs d'un pod en direct, ceux de tous les pods d'une étiquette (`--prefix`) et ceux du conteneur précédent (`--previous`).
- [ ] Vous avez vérifié avec `kubectl exec` la configuration reçue par le backend (`env`).
- [ ] Vous avez diagnostiqué `CrashLoopBackOff` (`Exit Code`) et `OOMKilled` (`Reason`), en suivant la méthode get → describe → logs → exec → nœud.
- [ ] Vous avez déployé Node Problem Detector, constaté la condition `KernelDeadlock=True` et retiré le nœud du service avec `kubectl cordon`, puis l'avez remis en service.
- [ ] `kubectl top nodes` et `kubectl top pods` affichent la consommation (Metrics Server).
- [ ] Vous avez retrouvé dans Grafana la mémoire des pods (Prometheus) et les logs du pod supprimé `crash-app` (Loki).
- [ ] Vous savez citer l'équivalent managé de cette pile chez Google (StackDriver, aujourd'hui Google Cloud Observability), AWS et Azure.
- [ ] *(Optionnel)* FreeLens est connecté au cluster par votre kubeconfig ; vous y avez suivi `crash-app` et fait `Cordon` / `Uncordon` sur un nœud.
