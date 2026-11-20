# Atelier 02 : Les Pods : les Trois Briques du Campus Summer Portal

### Objectifs Pédagogiques :
* Écrire le manifest YAML d'un **Pod** (`apiVersion`, `kind`, `metadata`, `spec`) et le créer avec `kubectl apply`.
* Suivre le cycle de vie d'un Pod avec `kubectl get`, `describe` et `logs`.
* Accéder à l'application d'un Pod avec `kubectl port-forward`.
* Diagnostiquer un statut anormal (`ImagePullBackOff`, `CrashLoopBackOff`) et choisir entre `describe` et `logs`.
* Générer un manifest déclaratif avec `--dry-run=client -o yaml`.
* Inspecter l'intérieur du conteneur avec `kubectl exec`.
* Constater les limites de résilience d'un Pod isolé (*bare pod*).

> 📌 **Note Compatibilité OS :**  
> Les commandes `kubectl` (`kubectl apply`, `kubectl get`, `kubectl describe`, `kubectl exec`, `kubectl port-forward`) sont **rigoureusement identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)**.
>
> 💻 **Environnement : Minikube sur votre poste.** Cet atelier se déroule entièrement sur votre cluster **Minikube** local. Vous éditez vos YAML dans votre IDE et lancez les commandes depuis votre terminal. Vérifiez que Minikube tourne et que `kubectl` pointe dessus :
>
> ```bash
> minikube status                     # host, kubelet et apiserver : Running
> kubectl config use-context minikube
> kubectl get nodes                   # un nœud « minikube » à l'état Ready
> ```
>
> *Si Minikube est arrêté, démarrez-le avec `minikube start`.*
>
> 🗂️ **Namespace de travail : `campus-dev`.** Avant de commencer, créez-le et définissez-le comme namespace courant (les commandes sont sans effet s'il existe déjà) :
>
> ```bash
> kubectl create namespace campus-dev --dry-run=client -o yaml | kubectl apply -f -
> kubectl config set-context --current --namespace=campus-dev
> kubectl config view --minify -o jsonpath='{..namespace}'   # doit afficher campus-dev
> ```

---

## Contexte Métier
Le portail Horizon Stages doit démarrer par la mise en ligne d'une première version de son interface web statique. En tant qu'administrateur, vous devez déployer ce premier conteneur dans un Pod, y accéder, inspecter son fonctionnement interne et constater les limites d'un Pod isolé.

* Image Docker du frontend : `regaieg/campus:frontend-1.0.0`
* Port exposé par le conteneur : `8080` (Nginx unprivileged)

---

<details>
<summary>💡 <b>Indice : Sous Windows, quel terminal utiliser ?</b></summary>

Les commandes de ces ateliers sont écrites en syntaxe **Bash**. Trois pièges attendent Windows PowerShell 5.1 (le PowerShell installé par défaut) :

* La redirection `> fichier.yaml` écrit en **UTF-16** : `kubectl apply` échoue ensuite à lire le fichier. Utilisez `| Out-File -Encoding utf8 fichier.yaml`.
* Les commandes sur plusieurs lignes terminées par `\` et les blocs `<< 'EOF'` ne sont pas compris par PowerShell.
* Les guillemets et les `$(...)` ne s'interprètent pas de la même façon.

**Recommandation :** sous Windows, utilisez **Git Bash** (installé avec Git for Windows) ou **WSL**, ou bien PowerShell 7 (`winget install Microsoft.PowerShell`), qui écrit en UTF-8.

**Piège propre à Git Bash :** il convertit en chemin Windows tout argument qui commence par `/`. Ainsi `kubectl run … -- md5sum /dev/urandom` (Lab 06) transmet au conteneur un chemin transformé (`md5sum: can't open '/Device/Null'`), et la commande échoue. Les labs encapsulent donc ces commandes dans `sh -c "…"`. Si vous tapez vous-même une commande de ce type, désactivez la conversion pour cette seule commande :
```bash
MSYS_NO_PATHCONV=1 kubectl run test --image=busybox:1.36 --restart=Never -- ls /etc
```
Ne l'activez pas globalement : Git Bash ne convertirait plus non plus une variable comme `KUBECONFIG=/c/Users/...`, et `kubectl` ne trouverait plus votre cluster.
</details>

Avant de construire le pod définitif du frontend, l'équipe veut un **pod de test** pour vérifier que l'image `regaieg/campus:frontend-1.0.0` démarre bien sur le cluster. Vous allez écrire son manifest **à la main**, pour bien identifier les rubriques communes à tous les objets Kubernetes.

1. **Écrire la spécification.** Créez un fichier `pod-frontend-test.yaml` qui décrit un Pod avec les propriétés suivantes :
   * nom du Pod : `frontend-test`
   * labels : `app: frontend-test` et `tier: frontend`
   * nom du conteneur : `frontend`
   * image du conteneur : `regaieg/campus:frontend-1.0.0`
   * port exposé par le conteneur : `8080`
   * alias d'hôte (`hostAliases`) : le nom `campus-backend` associé à l'adresse `192.0.2.1`

   > ⚠️ **Pourquoi `hostAliases` ?** Le Nginx du frontend relaie les appels `/api/` vers l'hôte `campus-backend:8080` et vérifie ce nom **dès son démarrage** : s'il est introuvable, il s'arrête (`host not found in upstream "campus-backend"`) et le pod part en `CrashLoopBackOff`. Or le backend n'existe pas encore. `hostAliases` ajoute une ligne au fichier `/etc/hosts` du conteneur : le nom existe, Nginx démarre. L'adresse `192.0.2.1` est réservée à la documentation et ne répond jamais. Cette astuce ne sert qu'à ce lab de test : plus tard, un vrai **Service** Kubernetes portera ce nom.

   > 💡 Ne précisez pas de namespace : le pod sera créé dans votre namespace courant `campus-dev` (défini en début d'atelier). Indentez **uniquement avec des espaces**, jamais avec des tabulations.

<details>
<summary>💡 <b>Indice 1 : squelette à compléter</b></summary>

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

<details>
<summary>💡 <b>Indice 2 : manifest complet</b></summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: frontend-test
  labels:
    app: frontend-test
    tier: frontend
spec:
  hostAliases:
  - ip: "192.0.2.1"
    hostnames:
    - campus-backend
  containers:
  - name: frontend
    image: regaieg/campus:frontend-1.0.0
    ports:
    - containerPort: 8080
```
</details>

2. **Créer le Pod** à partir du fichier :
   ```bash
   kubectl apply -f pod-frontend-test.yaml
   ```

3. **Suivre son démarrage** jusqu'au statut `Running` :
   ```bash
   kubectl get pods -w
   ```
   *L'option `-w` (*watch*) garde la commande ouverte et affiche chaque changement d'état : `ContainerCreating` (le kubelet télécharge l'image et prépare le conteneur), puis `Running`. Quittez avec `Ctrl + C`.*

   Affichez ensuite la vue détaillée :
   ```bash
   kubectl get pods -o wide
   ```
   *Repérez la colonne `NODE` (le nœud choisi par le scheduler : sur Minikube, il n'y en a qu'un, `minikube`) et la colonne `IP` : chaque pod reçoit sa propre adresse IP.*

<details>
<summary>💡 <b>Indice : le pod passe en <code>CrashLoopBackOff</code></b></summary>

Lisez la raison : `kubectl logs frontend-test`. Si vous voyez `host not found in upstream "campus-backend"`, le bloc `hostAliases` manque ou est mal indenté (il doit être dans `spec`, au même niveau que `containers`). Un pod ne se modifie pas après sa création : corrigez le fichier, puis supprimez et recréez le pod avec `kubectl delete -f pod-frontend-test.yaml` et `kubectl apply -f pod-frontend-test.yaml`.
</details>

4. **Observer les détails du Pod.** Affichez sa description et retrouvez l'**image** utilisée par le conteneur `frontend`, le **nœud** qui l'héberge et son **adresse IP** :
   ```bash
   kubectl describe pod frontend-test
   ```
   *Lisez la section `Events` en bas de la sortie : `Scheduled` (le scheduler a choisi un nœud), `Pulling` / `Pulled` (le kubelet a téléchargé l'image), `Created` / `Started` (le conteneur a démarré). C'est le premier réflexe en cas de problème.*

   Comparez votre fichier avec le manifest stocké par le cluster :
   ```bash
   kubectl get pod frontend-test -o yaml
   kubectl get pod frontend-test -o jsonpath='{.status.phase}'
   ```
   *Kubernetes a complété votre manifest avec des valeurs par défaut et a ajouté la rubrique `status`, qui contient l'état réel (ici la phase `Running`).*

5. **Accéder à l'application via un port-forward.** Ouvrez un tunnel du port `8888` local vers le port `8080` du pod. La commande reste au premier plan tant que le tunnel est ouvert :
   ```bash
   kubectl port-forward pod/frontend-test 8888:8080
   ```

   Ouvrez `http://localhost:8888` dans votre navigateur.

   *La page **Campus Summer Portal** s'affiche : c'est le contenu servi par le pod. Les blocs de données, eux, restent vides puis affichent une erreur (`502 Bad Gateway`) au bout de quelques secondes à une minute selon le réseau : les appels `/api/` partent vers l'adresse fictive `192.0.2.1`. Le vrai backend sera branché dans les labs suivants.*

   Arrêtez le tunnel avec `Ctrl + C`, puis **lisez les logs du conteneur** :
   ```bash
   kubectl logs frontend-test --tail=5
   ```
   *Vous y voyez vos requêtes (`"GET / HTTP/1.1" 200`) et l'erreur de Nginx quand la page appelle `/api/` (`connect() failed … upstream: "http://192.0.2.1:8080/…"`). Les logs montrent **ce que fait l'application**, alors que `describe` montre ce que fait Kubernetes.*

6. **Provoquer une erreur classique.** Lancez un pod de manière **impérative** (sans fichier) avec une version d'image qui n'existe pas :
   ```bash
   kubectl run frontend-typo --image=regaieg/campus:frontend-9.9.9
   kubectl get pods
   ```
   *Le statut passe à `ErrImagePull`, puis à `ImagePullBackOff`.* Trouvez la cause avec `describe`, dans la section `Events` :
   ```bash
   kubectl describe pod frontend-typo
   ```

   > 💡 **La colonne STATUS, en résumé :** problème de **placement** ou d'**image** (`Pending` qui dure, `ImagePullBackOff`) → `kubectl describe`, section `Events`. Problème dans l'**application** (`CrashLoopBackOff`) → `kubectl logs`.

7. **Supprimer les Pods.** Le pod déclaratif se supprime avec son fichier, le pod impératif avec son nom :
   ```bash
   kubectl delete -f pod-frontend-test.yaml
   kubectl delete pod frontend-typo
   kubectl get pods
   ```

8. **Rejouer le manifest.** Les deux pods ont disparu. Recréez `frontend-test` en relançant simplement son fichier :
   ```bash
   kubectl apply -f pod-frontend-test.yaml
   kubectl get pods
   ```
   *Le pod revient à l'identique : même nom, mêmes labels, même image, même port, même `hostAliases`.*

   *Question de réflexion :* que vous faudrait-il pour recréer `frontend-typo` ?  
   *Réponse :* retrouver la commande exacte dans l'historique de votre terminal : rien d'autre ne l'a enregistrée.

   > 💡 `kubectl run` est une commande qui sera oubliée. `pod-frontend-test.yaml` est un fichier que vous pouvez rejouer et versionner dans Git : c'est l'approche **déclarative** utilisée dans la suite de la formation.

   Supprimez à nouveau le pod de test :
   ```bash
   kubectl delete -f pod-frontend-test.yaml
   ```

9. **Générer un manifest avec `--dry-run`.** Écrire un manifest à la main, comme à l'étape 1, permet de comprendre sa structure mais prend du temps et favorise les fautes d'indentation. En pratique, **on ne part pas d'une page blanche** : on génère un squelette propre et valide avec `kubectl run` combiné avec `--dry-run=client -o yaml`, puis on le complète. Générez le manifest `pod-frontend.yaml` sans rien créer sur le cluster :
   * Sous Windows (PowerShell) :
     ```powershell
     kubectl run campus-frontend --image=regaieg/campus:frontend-1.0.0 --port=8080 --dry-run=client -o yaml | Out-File -Encoding utf8 pod-frontend.yaml
     ```
   * Sous Linux (Ubuntu) / macOS (Bash) :
     ```bash
     kubectl run campus-frontend --image=regaieg/campus:frontend-1.0.0 --port=8080 --dry-run=client -o yaml > pod-frontend.yaml
     ```

10. **Compléter le manifest généré.** Ouvrez `pod-frontend.yaml` dans votre éditeur et comparez-le avec celui de l'étape 1. Repérez ce que `kubectl` a généré pour vous : le label `run: campus-frontend`, `resources: {}`, `dnsPolicy`, `restartPolicy` et `status: {}`. Puis :
    * supprimez la ligne `status: {}` : cette rubrique est remplie par Kubernetes, vous ne l'écrivez jamais ;
    * ajoutez dans `spec` le bloc `hostAliases` de l'étape 1 : `kubectl run` ne sait pas le générer, et sans lui Nginx ne démarre pas.

<details>
<summary>💡 <b>Indice 3 : manifest attendu</b></summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: campus-frontend
  name: campus-frontend
spec:
  hostAliases:
  - ip: "192.0.2.1"
    hostnames:
    - campus-backend
  containers:
  - image: regaieg/campus:frontend-1.0.0
    name: campus-frontend
    ports:
    - containerPort: 8080
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
```
</details>

11. **Appliquer le manifest** de manière **déclarative** :
    ```bash
    kubectl apply -f pod-frontend.yaml
    ```

12. **Exécuter une commande à l'intérieur du conteneur (`kubectl exec`)** et tester la réponse HTTP du serveur web :
    ```bash
    kubectl exec campus-frontend -- wget -qO- http://127.0.0.1:8080 | head -n 15
    ```
    Affichez aussi le fichier `/etc/hosts` du conteneur : la dernière ligne est celle ajoutée par `hostAliases`.
    ```bash
    kubectl exec campus-frontend -- sh -c "cat /etc/hosts"
    ```
    *La commande est encapsulée dans `sh -c "…"` pour que Git Bash ne transforme pas `/etc/hosts` en chemin Windows (voir l'indice sur le terminal Windows en début d'atelier).*

    > 💡 **Précision réseau :** Nous ciblons `127.0.0.1:8080` plutôt que `localhost:8080` car sous les distributions légères comme Alpine Linux, `localhost` résout par défaut sur IPv6 (`::1`), alors que le serveur Nginx écoute sur le socket IPv4 `0.0.0.0:8080`.

13. **Le crash-test du Pod isolé.** Supprimez le pod `campus-frontend` :
    ```bash
    kubectl delete pod campus-frontend
    kubectl get pods
    ```
    *Question de réflexion :* Le pod est-il réapparu tout seul ?  
    *Réponse :* **Non !** Un Pod isolé (*bare pod*) n'est rattaché à aucun contrôleur. S'il plante, meurt ou est supprimé, il est définitivement perdu.  
    👉 C'est la raison d'être des **Deployments**, étudiés dans le Lab 03 !

---

## Critères de Validation (Checklist)

- [ ] Votre namespace courant est `campus-dev` et tous vos objets y sont créés (aucun objet applicatif dans `default`).
- [ ] Vous savez écrire le manifest d'un Pod et retrouver son image, son nœud et son IP avec `kubectl describe pod`.
- [ ] Vous avez affiché le frontend via `kubectl port-forward` et savez choisir entre `describe` (placement, image) et `logs` (application) face à un statut anormal.
- [ ] Vous maîtrisez la génération rapide de manifest avec `--dry-run=client -o yaml`.
- [ ] Vous savez exécuter une commande à l'intérieur du conteneur avec `kubectl exec` et expliquer le rôle de `hostAliases` dans ce lab.
- [ ] Vous avez constaté par vous-même l'absence de haute disponibilité d'un pod nu.
