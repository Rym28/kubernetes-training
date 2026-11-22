# Atelier 02 : Les Pods : les Trois Briques du Campus Summer Portal

### Objectifs Pédagogiques :
* Écrire le manifest YAML d'un **Pod** (`apiVersion`, `kind`, `metadata`, `spec`) et le créer avec `kubectl apply`.
* Suivre le cycle de vie d'un Pod avec `kubectl get`, `describe` et `logs`.
* Accéder à l'application d'un Pod avec `kubectl port-forward`.
* Diagnostiquer un statut anormal (`ImagePullBackOff`, `CrashLoopBackOff`) et choisir entre `describe` et `logs`.
* Générer un manifest déclaratif avec `--dry-run=client -o yaml`.
* Inspecter l'intérieur du conteneur avec `kubectl exec`.
* Constater les limites de résilience d'un Pod isolé (*bare pod*).

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Compatibilité OS</strong></p>

Les commandes `kubectl` (`kubectl apply`, `kubectl get`, `kubectl describe`, `kubectl exec`, `kubectl port-forward`) sont **rigoureusement identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)**. Quand une commande diffère, des onglets vous proposent les deux variantes.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Environnement : Minikube sur votre poste</strong></p>

Cet atelier se déroule entièrement sur votre cluster **Minikube** local. Vous éditez vos YAML dans votre IDE et lancez les commandes depuis votre terminal. Vérifiez que Minikube tourne et que `kubectl` pointe dessus :

```bash
minikube status                     # host, kubelet et apiserver : Running
kubectl config use-context minikube
kubectl get nodes                   # un nœud « minikube » à l'état Ready
```

*Si Minikube est arrêté, démarrez-le avec `minikube start`.*

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Namespace de travail : <code>campus-dev</code></strong></p>

Avant de commencer, créez-le et définissez-le comme namespace courant (les commandes sont sans effet s'il existe déjà) :

```bash
kubectl create namespace campus-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace=campus-dev
kubectl config view --minify -o jsonpath='{..namespace}'   # doit afficher campus-dev
```

</div>

<details class="tip" markdown>
<summary><strong>Sous Windows, quel terminal utiliser ?</strong></summary>

Les commandes de ces ateliers sont écrites en syntaxe **Bash**. Trois pièges attendent Windows PowerShell 5.1 (le PowerShell installé par défaut) :

* La redirection `> fichier.yaml` écrit en **UTF-16** : `kubectl apply` échoue ensuite à lire le fichier. Utilisez `| Out-File -Encoding utf8 fichier.yaml`.
* Les commandes sur plusieurs lignes terminées par `\` et les blocs `<< 'EOF'` ne sont pas compris par PowerShell.
* Les guillemets et les `$(...)` ne s'interprètent pas de la même façon.

**Recommandation :** sous Windows, utilisez **Git Bash** (installé avec Git for Windows) ou **WSL**, ou bien PowerShell 7 (`winget install Microsoft.PowerShell`), qui écrit en UTF-8.

**Piège propre à Git Bash :** il convertit en chemin Windows tout argument qui commence par `/`. Ainsi `kubectl run … -- md5sum /dev/urandom` (Atelier 06) transmet au conteneur un chemin transformé (`md5sum: can't open '/Device/Null'`), et la commande échoue. Les labs encapsulent donc ces commandes dans `sh -c "…"`. Si vous tapez vous-même une commande de ce type, désactivez la conversion pour cette seule commande :

```bash
MSYS_NO_PATHCONV=1 kubectl run test --image=busybox:1.36 --restart=Never -- ls /etc
```

Ne l'activez pas globalement : Git Bash ne convertirait plus non plus une variable comme `KUBECONFIG=/c/Users/...`, et `kubectl` ne trouverait plus votre cluster.

</details>

---

## Contexte Métier
Le portail Horizon Stages doit démarrer par la mise en ligne d'une première version de son interface web statique. En tant qu'administrateur, vous devez déployer ce premier conteneur dans un Pod, y accéder, inspecter son fonctionnement interne et constater les limites d'un Pod isolé.

* Image Docker du frontend : `regaieg/campus:frontend-1.0.0`
* Port exposé par le conteneur : `8080` (Nginx unprivileged)

<div class="admonition tip" markdown>
<p class="admonition-title"><strong>Mode d'emploi</strong></p>

* Les encadrés rouges **« À vous de répondre »** contiennent les questions. Pour les commandes déjà vues en cours, on vous demande la commande au lieu de vous la donner : cherchez avec `kubectl --help`, `kubectl <commande> --help` ou `kubectl explain`.
* Les commandes nouvelles sont données.
* Les encadrés **« Indice »** sont repliés : cliquez dessus seulement si vous bloquez.
* Le formateur corrige en fin d'atelier.

</div>

---

## Exercice 1 : Écrire et créer un Pod

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Avant de construire le pod définitif du frontend, l'équipe veut un **pod de test** pour vérifier que l'image `regaieg/campus:frontend-1.0.0` démarre bien sur le cluster. Vous allez écrire son manifest **à la main**, pour bien identifier les rubriques communes à tous les objets Kubernetes.

</div>

### Étape 1 : Écrire la spécification

Créez un fichier `pod-frontend-test.yaml` qui décrit un Pod avec les propriétés suivantes :

| Propriété | Valeur |
| :--- | :--- |
| Nom du Pod | `frontend-test` |
| Labels | `app: frontend-test` et `tier: frontend` |
| Nom du conteneur | `frontend` |
| Image du conteneur | `regaieg/campus:frontend-1.0.0` |
| Port exposé par le conteneur | `8080` |
| Alias d'hôte (`hostAliases`) | le nom `campus-backend` associé à l'adresse `192.0.2.1` |

<div class="admonition warning" markdown>
<p class="admonition-title"><strong>Pourquoi <code>hostAliases</code> ?</strong></p>

Le Nginx du frontend relaie les appels `/api/` vers l'hôte `campus-backend:8080` et vérifie ce nom **dès son démarrage** : s'il est introuvable, il s'arrête (`host not found in upstream "campus-backend"`) et le pod part en `CrashLoopBackOff`. Or le backend n'existe pas encore.

`hostAliases` ajoute une ligne au fichier `/etc/hosts` du conteneur : le nom existe, Nginx démarre. L'adresse `192.0.2.1` est réservée à la documentation et ne répond jamais. Cette astuce ne sert qu'à ce lab de test : plus tard, un vrai **Service** Kubernetes portera ce nom.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>À savoir</strong></p>

Ne précisez pas de namespace : le pod sera créé dans votre namespace courant `campus-dev` (défini en début d'atelier). Indentez **uniquement avec des espaces**, jamais avec des tabulations.

</div>

<details class="tip" markdown>
<summary><strong>Indice : squelette à compléter</strong></summary>

Remplacez chaque `....` par la valeur demandée :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ...............
  labels:
    app: ...............
    tier: ...............
spec:
  hostAliases:
  - ip: "..........."
    hostnames:
    - ...............
  containers:
  - name: ...............
    image: ...............
    ports:
    - containerPort: ....
```

Tout objet Kubernetes suit le même plan :

* `apiVersion` + `kind` : le type d'objet (`v1` et `Pod`).
* `metadata` : son identité (`name`, `labels`).
* `spec` : l'état désiré. Pour un Pod, `containers` est une **liste de dictionnaires** : chaque conteneur commence par un tiret `-` et contient `name`, `image`, `ports`. `hostAliases` se place dans `spec`, au même niveau que `containers`.
* `status` : l'état réel. Il est ajouté par Kubernetes : **vous ne l'écrivez jamais**.

Pour connaître les champs disponibles : `kubectl explain pod.spec.containers`. Dans VS Code, l'extension *YAML* (Red Hat) propose l'autocomplétion et souligne les erreurs d'indentation.

</details>

### Étape 2 : Créer le Pod

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande crée le pod à partir de votre fichier, de manière **déclarative** ?

</div>

### Étape 3 : Suivre son démarrage

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande liste les pods **en continu**, pour voir chaque changement d'état en direct ? Quittez-la avec `Ctrl + C`.
2. Par quels statuts le pod passe-t-il avant `Running` ? Que fait le kubelet pendant ce temps ?
3. Quelle option de `kubectl get pods` ajoute les colonnes `NODE` et `IP` ? Sur quel nœud tourne votre pod, et quelle est son adresse IP ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : le pod passe en <code>CrashLoopBackOff</code></strong></summary>

Lisez la raison : `kubectl logs frontend-test`. Si vous voyez `host not found in upstream "campus-backend"`, le bloc `hostAliases` manque ou est mal indenté (il doit être dans `spec`, au même niveau que `containers`). Un pod ne se modifie pas après sa création : corrigez le fichier, supprimez le pod, puis recréez-le.

</details>

---

## Exercice 2 : Inspecter le Pod et accéder à l'application

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

`describe` raconte ce que Kubernetes a fait du pod (placement, image, événements) ; les **logs** racontent ce que fait l'application à l'intérieur.

</div>

### Étape 4 : Observer les détails du Pod

Affichez d'abord la description complète du pod `frontend-test` (questions 1 et 2), puis comparez votre fichier avec le manifest stocké par le cluster (questions 3 et 4) :

```bash
kubectl get pod frontend-test -o yaml
kubectl get pod frontend-test -o jsonpath='{.status.phase}'
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande affiche la description complète du pod `frontend-test` ? Retrouvez-y l'**image** du conteneur `frontend`, le **nœud** qui l'héberge et l'**adresse IP** du pod.
2. Dans la section `Events`, en bas de la sortie, quelles étapes du démarrage apparaissent, et dans quel ordre ? Quel composant a produit chacune d'elles ?
3. La sortie de `kubectl get pod frontend-test -o yaml` est bien plus longue que votre fichier. Citez deux champs ajoutés dans `metadata` et deux valeurs par défaut ajoutées dans `spec`.
4. Quelle rubrique n'existait pas dans votre fichier ? Qui la remplit, et quelle différence y a-t-il entre `spec` et cette rubrique ?

</div>

### Étape 5 : Accéder à l'application via un port-forward

Ouvrez un tunnel du port `8888` local vers le port `8080` du pod. La commande reste au premier plan tant que le tunnel est ouvert :

```bash
kubectl port-forward pod/frontend-test 8888:8080
```

Ouvrez `http://localhost:8888` dans votre navigateur, puis arrêtez le tunnel avec `Ctrl + C`.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle partie de la page s'affiche correctement ? Quelle partie reste vide puis affiche une erreur, et pourquoi ? (Relisez l'encadré sur `hostAliases`.)
2. Quelle commande affiche les **5 dernières lignes** des logs du pod ?
3. Retrouvez-y vos requêtes et l'erreur de Nginx. Quelle différence faites-vous entre ce que montre `describe` et ce que montrent les logs ?

</div>

---

## Exercice 3 : Diagnostiquer une erreur classique

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Face à un pod en erreur, le statut affiché oriente vers le bon outil : `describe` ou `logs`.

</div>

### Étape 6 : Provoquer une erreur

Lancez un pod de manière **impérative** (sans fichier) avec une version d'image qui n'existe pas, puis listez les pods :

```bash
kubectl run frontend-typo --image=regaieg/campus:frontend-9.9.9
kubectl get pods
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Par quels statuts passe `frontend-typo` ?
2. Trouvez la cause exacte de l'erreur. Quelle commande utilisez-vous, et dans quelle section de sa sortie lisez-vous la cause ?
3. Pourquoi `kubectl logs frontend-typo` ne vous aiderait-il pas ici ?
4. D'une manière générale : face à un pod en `ImagePullBackOff` ou en `Pending` qui dure, quelle commande utilisez-vous ? Et face à un pod en `CrashLoopBackOff` ?

</div>

---

## Exercice 4 : Supprimer et rejouer un manifest

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un fichier YAML se rejoue à l'identique ; une commande impérative, elle, est perdue une fois tapée.

</div>

### Étape 7 : Supprimer les Pods

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Supprimez `frontend-test` **à l'aide de son fichier**, et `frontend-typo` **à l'aide de son nom**. Quelles commandes utilisez-vous ?
2. Quelle commande vérifie qu'il ne reste aucun pod ?

</div>

### Étape 8 : Rejouer le manifest

Les deux pods ont disparu.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Recréez `frontend-test` sans réécrire quoi que ce soit. Le pod est-il identique au premier ?
2. Que vous faudrait-il pour recréer `frontend-typo` ?
3. Laquelle des deux approches, impérative ou déclarative, peut-on versionner dans Git et rejouer à l'identique ?

</div>

Supprimez à nouveau le pod de test.

---

## Exercice 5 : Générer un manifest avec `--dry-run`

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Écrire un manifest à la main, comme à l'étape 1, permet de comprendre sa structure mais prend du temps et favorise les fautes d'indentation. En pratique, **on ne part pas d'une page blanche** : on génère un squelette propre et valide, puis on le complète.

</div>

### Étape 9 : Générer le manifest

Générez le manifest `pod-frontend.yaml` avec `kubectl run` combiné avec `--dry-run=client -o yaml`, sans rien créer sur le cluster :

**Linux / macOS (Bash)**

```bash
kubectl run campus-frontend --image=regaieg/campus:frontend-1.0.0 --port=8080 --dry-run=client -o yaml > pod-frontend.yaml
```

**Windows (PowerShell)**

```powershell
kubectl run campus-frontend --image=regaieg/campus:frontend-1.0.0 --port=8080 --dry-run=client -o yaml | Out-File -Encoding utf8 pod-frontend.yaml
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Comment vérifiez-vous qu'aucun pod n'a été créé sur le cluster ?

</div>

### Étape 10 : Compléter le manifest généré

Ouvrez `pod-frontend.yaml` dans votre éditeur et comparez-le avec celui de l'étape 1.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quel label `kubectl` a-t-il généré à la place de vos labels ? Quels champs supplémentaires a-t-il ajoutés ?

</div>

Puis modifiez le fichier :

* supprimez la ligne `status: {}` : cette rubrique est remplie par Kubernetes, vous ne l'écrivez jamais ;
* ajoutez dans `spec` le bloc `hostAliases` de l'étape 1 : `kubectl run` ne sait pas le générer, et sans lui Nginx ne démarre pas.

### Étape 11 : Appliquer le manifest

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande crée le pod `campus-frontend` à partir de `pod-frontend.yaml` ? Vérifiez qu'il est `Running`.

</div>

---

## Exercice 6 : Entrer dans le conteneur et tester la résilience

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

`kubectl exec` lance une commande à l'intérieur du conteneur. Et un pod créé seul n'est protégé par personne.

</div>

### Étape 12 : Exécuter une commande dans le conteneur (`kubectl exec`)

Testez la réponse HTTP du serveur web depuis l'intérieur du conteneur :

**Linux / macOS**

```bash
kubectl exec campus-frontend -- wget -qO- http://127.0.0.1:8080 | head -n 15
```

**Windows (PowerShell)**

```powershell
kubectl exec campus-frontend -- wget -qO- http://127.0.0.1:8080 | Select-Object -First 15
```

Affichez aussi le fichier `/etc/hosts` du conteneur :

```bash
kubectl exec campus-frontend -- sh -c "cat /etc/hosts"
```

*La commande est encapsulée dans `sh -c "…"` pour que Git Bash ne transforme pas `/etc/hosts` en chemin Windows (voir l'indice sur le terminal Windows en début d'atelier).*

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Pourquoi <code>127.0.0.1</code> plutôt que <code>localhost</code> ?</strong></p>

Sous les distributions légères comme Alpine Linux, `localhost` résout par défaut sur IPv6 (`::1`), alors que le serveur Nginx écoute sur le socket IPv4 `0.0.0.0:8080`.

</div>

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle ligne de `/etc/hosts` a été ajoutée par `hostAliases` ? Pourquoi Nginx en a-t-il besoin pour démarrer ?

</div>

### Étape 13 : Le crash-test du Pod isolé

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande supprime le pod `campus-frontend` ? Listez ensuite les pods.
2. Le pod est-il réapparu tout seul ? Pourquoi ?

</div>

<div class="admonition success" markdown>
<p class="admonition-title"><strong>Et ensuite ?</strong></p>

Pour qu'un pod supprimé soit recréé automatiquement, il faut le confier à un contrôleur : c'est le rôle des **Deployments**, étudiés à l'Atelier 03.

</div>

---

## Critères de Validation (Checklist)

- [ ] Votre namespace courant est `campus-dev` et tous vos objets y sont créés (aucun objet applicatif dans `default`).
- [ ] Vous savez écrire le manifest d'un Pod et retrouver son image, son nœud et son IP avec `kubectl describe pod`.
- [ ] Vous avez affiché le frontend via `kubectl port-forward` et savez choisir entre `describe` (placement, image) et `logs` (application) face à un statut anormal.
- [ ] Vous maîtrisez la génération rapide de manifest avec `--dry-run=client -o yaml`.
- [ ] Vous savez exécuter une commande à l'intérieur du conteneur avec `kubectl exec` et expliquer le rôle de `hostAliases` dans ce lab.
- [ ] Vous avez constaté par vous-même l'absence de haute disponibilité d'un pod nu.
