# Lab 02 : Premiers Pods, Labels & Sélecteurs

### Objectifs Pédagogiques :
* Situer son travail dans un **namespace** dédié (`campus-dev`) et distinguer les objets propres à un namespace des objets globaux au cluster.
* Comprendre la structure atomique d'un **Pod** Kubernetes et son cycle de vie.
* Maîtriser la génération de manifests déclaratifs YAML grâce à `--dry-run=client -o yaml`.
* Injecter des variables d'environnement (`env`) et inspecter l'intérieur du conteneur (`kubectl exec`, `logs`).
* Dimensionner les ressources système avec les **Requests** et **Limits** (CPU et mémoire vive).
* Mettre en œuvre le pattern d'initialisation avec les **InitContainers**.
* Exploiter les **Labels** et **Selectors** pour organiser et filtrer les composants applicatifs.
* Constater les limites de résilience d'un Pod isolé (*bare pod*).

> 📌 **Note Compatibilité OS :**  
> Les commandes `kubectl` (`kubectl apply`, `kubectl get`, `kubectl describe`, `kubectl exec`, `kubectl label`) sont **rigoureusement identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)**.
>
> 💡 **Modalités d'exécution (Au choix) :**  
> * **Option A (Recommandée - Confort DevOps Local) :** Exécutez les commandes directement depuis votre terminal local avec votre `kubectl` et le `kubeconfig` configuré au Lab 00. Vous modifiez vos YAML directement dans votre IDE sans transfert !  
> * **Option B (Secours - PC d'entreprise verrouillé) :** Connectez-vous en SSH sur `k8s-control` (via MobaXterm ou terminal) : `kubectl` et tous les dossiers de TP sont déjà pré-déployés dans `~/labs/`.
>
> 🗂️ **Namespace de travail : `campus-dev`.** Vous le créez et le définissez comme namespace courant à l'**Exercice 0** ci-dessous.

---

## Contexte Métier
Le portail Horizon Stages doit démarrer par la mise en ligne d'une première version de son interface web statique. En tant qu'administrateur, vous devez déployer ce premier conteneur dans un Pod, encadrer ses besoins en ressources CPU/RAM, lui injecter ses paramètres d'exécution et l'étiqueter correctement pour que les équipes d'exploitation puissent l'identifier sans ambiguïté.

* Image Docker du frontend : `regaieg/campus:frontend-1.0.0`
* Port exposé par le conteneur : `8080` (Nginx unprivileged)

---

## Exercice 0 : Le Namespace, Votre Périmètre de Travail

Un **namespace** est une cloison logique qui regroupe les objets d'un projet : il délimite les noms, les quotas, les règles réseau et les droits (Lab 07). **Bonne pratique : on ne déploie jamais une application dans `default`.**

| Namespace | Contenu | Labs |
| :--- | :--- | :---: |
| `campus-dev` | L'application fil rouge en construction | 01 à 07 |
| `campus-prod` | La plateforme finale durcie | 08 |
| `monitoring` | La pile d'observabilité (Prometheus, Loki, Grafana) | 06 |
| `kube-system` | Les composants du cluster : **on n'y déploie rien** | 01, 06 |

1. **Créez votre namespace de travail `campus-dev`.** Créez le fichier `namespace-campus-dev.yaml` :
   ```yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: campus-dev
     labels:
       app.kubernetes.io/part-of: campus-summer-portal
       environment: dev
   ```

   Appliquez-le (sans effet s'il existe déjà, par exemple créé au Lab 01) :
   ```bash
   kubectl apply -f namespace-campus-dev.yaml
   kubectl get namespaces --show-labels
   ```

2. **Faites-en le namespace courant**, pour ne plus avoir à taper `-n campus-dev`. Un kubeconfig contient des **contextes** : chacun associe un cluster, un utilisateur et un namespace par défaut. Enregistrez `campus-dev` dans le contexte courant, puis vérifiez :
   ```bash
   kubectl config set-context --current --namespace=campus-dev
   kubectl config view --minify -o jsonpath='{..namespace}'
   ```
   *Sortie attendue : `campus-dev`.*

   > ⚠️ Le namespace courant est enregistré **dans chaque fichier kubeconfig**. Si vous travaillez à la fois depuis votre poste (Option A) et en SSH sur `k8s-control` (Option B), lancez la commande `set-context` dans les deux.

   <details>
   <summary>💡 <b>Indice : j'ai oublié de changer de namespace, où sont mes objets ?</b></summary>

   Ils sont dans `default` : `kubectl get all -n default`. Supprimez-les (`kubectl delete -f <fichier>.yaml -n default`), refaites le point 2, puis réappliquez vos manifests.
   </details>

3. Listez les namespaces du cluster et repérez les namespaces système créés par Kubeadm (`default`, `kube-system`, `kube-public`, `kube-node-lease`) :
   ```bash
   kubectl get namespaces
   ```

4. Observez la portée des commandes :
   ```bash
   kubectl get pods                 # namespace courant : campus-dev (vide pour l'instant)
   kubectl get pods -n kube-system  # un namespace précis
   kubectl get pods -A              # tous les namespaces
   ```

5. Tous les objets n'appartiennent pas à un namespace. Listez ceux qui sont globaux au cluster :
   ```bash
   kubectl api-resources --namespaced=false
   ```
   *Vous y trouvez notamment `nodes`, `namespaces`, `persistentvolumes`, `storageclasses` et `clusterroles` : un nœud ou un disque n'appartient à aucun projet en particulier.*

6. **Préparer le nom réseau attendu par le frontend.** Le serveur Nginx du frontend relaie les appels `/api/` et `/actuator/` vers l'hôte `campus-backend:8080`. Or Nginx vérifie ce nom DNS **dès son démarrage** : s'il est introuvable, il s'arrête aussitôt (`host not found in upstream "campus-backend"`) et le Pod part en `CrashLoopBackOff`.

   Créez donc dès maintenant le **Service** `campus-backend`, qui portera ce nom dans le namespace. Créez le fichier `service-backend.yaml` :
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: campus-backend
   spec:
     type: ClusterIP
     selector:
       app: campus-backend
     ports:
     - port: 8080
       targetPort: 8080
   ```

   Appliquez-le et observez :
   ```bash
   kubectl apply -f service-backend.yaml
   kubectl get service campus-backend
   kubectl get endpoints campus-backend
   ```
   *Le Service reçoit immédiatement une adresse IP virtuelle et un nom DNS, mais ses `ENDPOINTS` sont vides (`<none>`) : aucun Pod ne porte encore le label `app=campus-backend`. Il se remplira tout seul au Lab 03, dès que les pods du backend existeront. Vous étudierez ce mécanisme en détail au Lab 04.*

<details>
<summary>💡 <b>Indice : Sous Windows, quel terminal utiliser ?</b></summary>

Les commandes de ces ateliers sont écrites en syntaxe **Bash**. Trois pièges attendent Windows PowerShell 5.1 (le PowerShell installé par défaut) :

* La redirection `> fichier.yaml` écrit en **UTF-16** : `kubectl apply` échoue ensuite à lire le fichier. Utilisez `| Out-File -Encoding utf8 fichier.yaml`.
* Les commandes sur plusieurs lignes terminées par `\` et les blocs `<< 'EOF'` ne sont pas compris par PowerShell.
* Les guillemets et les `$(...)` ne s'interprètent pas de la même façon.

**Recommandation :** pour l'Option A sous Windows, utilisez **Git Bash** (installé avec Git for Windows) ou **WSL**, ou bien PowerShell 7 (`winget install Microsoft.PowerShell`), qui écrit en UTF-8. À défaut, utilisez l'Option B (SSH sur `k8s-control`), qui est un vrai terminal Bash.

**Piège propre à Git Bash :** il convertit en chemin Windows tout argument qui commence par `/`. Ainsi `kubectl run … -- md5sum /dev/urandom` (Lab 06) transmet au conteneur un chemin transformé (`md5sum: can't open '/Device/Null'`), et la commande échoue. Les labs encapsulent donc ces commandes dans `sh -c "…"`. Si vous tapez vous-même une commande de ce type, désactivez la conversion pour cette seule commande :
```bash
MSYS_NO_PATHCONV=1 kubectl run test --image=busybox:1.36 --restart=Never -- ls /etc
```
Ne l'activez pas globalement : Git Bash ne convertirait plus non plus une variable comme `KUBECONFIG=/c/Users/...`, et `kubectl` ne trouverait plus votre cluster.
</details>

<details>
<summary>💡 <b>Indice : Faut-il écrire le namespace dans les manifests YAML ?</b></summary>

Deux écoles coexistent :

* **Namespace porté par le contexte** (labs 02 à 07) : les manifests ne contiennent pas de `metadata.namespace`. Le même fichier peut être appliqué en dev ou en prod avec `kubectl apply -f fichier.yaml -n <namespace>`. C'est l'approche des outils comme Kustomize et Helm.
* **Namespace écrit dans le manifest** (Lab 08) : `metadata.namespace: campus-prod`. Le fichier est explicite et ne peut pas être appliqué par erreur au mauvais endroit.

En revanche, ne laissez jamais le hasard décider : vérifiez toujours votre namespace courant avant un `kubectl apply` ou un `kubectl delete`.
</details>

---

## Exercice 1 : Déploiement Impératif vs Déclaratif

1. Lancez un premier pod nommé `frontend-test` de manière **impérative** avec l'image `regaieg/campus:frontend-1.0.0` sur le port `8080` :
   ```bash
   kubectl run frontend-test --image=regaieg/campus:frontend-1.0.0 --port=8080
   ```
2. Observez l'état du pod jusqu'à ce qu'il passe au statut `Running` :
   ```bash
   kubectl get pods -w
   ```
   *L'option `-w` (*watch*) garde la commande ouverte et affiche chaque changement d'état. Quittez avec `Ctrl + C`.*

<details>
<summary>💡 <b>Indice : le pod passe en <code>CrashLoopBackOff</code></b></summary>

Lisez la raison : `kubectl logs frontend-test`. Si vous voyez `host not found in upstream "campus-backend"`, le Service `campus-backend` de l'exercice 0 (étape 6) n'existe pas dans votre namespace courant. Vérifiez avec `kubectl get svc campus-backend`, créez-le, puis supprimez et recréez le pod.
</details>

3. Supprimez ce pod de test :
   ```bash
   kubectl delete pod frontend-test
   ```

---

## Exercice 2 : La Technique DevOps du `--dry-run` & Manifeste Déclaratif

En production, **on n'écrit jamais de YAML à partir d'une page blanche**. On utilise la commande `kubectl run` combinée avec `--dry-run=client -o yaml` pour générer un squelette propre et valide.

1. Générez un manifest nommé `pod-frontend.yaml` sans exécuter la création sur le cluster :

#### Sous Windows (PowerShell) :
```powershell
kubectl run campus-frontend --image=regaieg/campus:frontend-1.0.0 --port=8080 --dry-run=client -o yaml | Out-File -Encoding utf8 pod-frontend.yaml
```

#### Sous Linux (Ubuntu) / macOS (Bash) :
```bash
kubectl run campus-frontend --image=regaieg/campus:frontend-1.0.0 --port=8080 --dry-run=client -o yaml > pod-frontend.yaml
```

2. Enrichissez la section `metadata.labels` de votre fichier YAML pour y inclure les labels d'entreprise :
   * `app: campus`
   * `tier: frontend`
   * `environment: dev`
   * `version: "1.0.0"`

<details>
<summary>💡 <b>Indice 1 : Structure YAML attendue</b></summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: campus-frontend
  labels:
    app: campus
    tier: frontend
    environment: dev
    version: "1.0.0"
spec:
  containers:
  - name: campus-frontend
    image: regaieg/campus:frontend-1.0.0
    ports:
    - containerPort: 8080
```
</details>

3. Appliquez le manifest de manière **déclarative** :
   ```bash
   kubectl apply -f pod-frontend.yaml
   ```

---

## Exercice 3 : Variables d'Environnement & Inspection Interne

Un Pod ne doit pas être une boîte noire. Vous devez savoir lui injecter des paramètres dynamiques et inspecter son fonctionnement interne.

1. Modifiez votre fichier `pod-frontend.yaml` pour injecter deux variables d'environnement dans le conteneur via la section `env` :
   * `CAMPUS_APP_NAME` : `"Horizon Stages"`
   * `CAMPUS_ENV` : `"development"`

<details>
<summary>💡 <b>Indice 2 : Exemple d'ajout de variables d'environnement</b></summary>

```yaml
spec:
  containers:
  - name: campus-frontend
    image: regaieg/campus:frontend-1.0.0
    ports:
    - containerPort: 8080
    env:
    - name: CAMPUS_APP_NAME
      value: "Horizon Stages"
    - name: CAMPUS_ENV
      value: "development"
```
</details>

2. Réappliquez le manifest :
   ```bash
   kubectl replace --force -f pod-frontend.yaml
   ```
   *(Un Pod existant ne peut pas modifier ses variables à chaud : l'option `--force` détruit et recrée le pod avec la nouvelle définition).*

3. **Exécuter une commande à l'intérieur du conteneur (`kubectl exec`)** :
   Vérifiez que la variable est bien présente dans le système Linux du conteneur :
   ```bash
   kubectl exec campus-frontend -- env | grep CAMPUS
   ```
   *Outre vos deux variables, vous voyez des variables `CAMPUS_BACKEND_SERVICE_HOST`, `CAMPUS_BACKEND_PORT`… : Kubernetes injecte automatiquement dans chaque conteneur l'adresse des Services existant dans le namespace au moment de sa création (ici le Service `campus-backend` de l'exercice 0). Le DNS (Lab 04) reste la méthode recommandée.*

4. **Tester la réponse HTTP locale du serveur web** :
   ```bash
   kubectl exec campus-frontend -- wget -qO- http://127.0.0.1:8080 | head -n 15
   ```
   > 💡 **Précision réseau :** Nous ciblons `127.0.0.1:8080` plutôt que `localhost:8080` car sous les distributions légères comme Alpine Linux, `localhost` résout par défaut sur IPv6 (`::1`), alors que le serveur Nginx écoute sur le socket IPv4 `0.0.0.0:8080`.

5. **Consulter les journaux d'accès (logs)** :
   ```bash
   kubectl logs campus-frontend
   ```

---

## Exercice 4 : Allocation & Gouvernance des Ressources (Requests & Limits)

En environnement d'entreprise partagé, ne pas borner la mémoire et le CPU d'un conteneur expose le serveur physique à la saturation (phénomène du *Noisy Neighbor*).

* **`requests` (demande garantie)** : Quantité minimale de CPU et de RAM réservée par le Scheduler sur le nœud worker pour accepter de placer le Pod.
* **`limits` (plafond absolu)** : Plafond maximal autorisé. Si le conteneur dépasse la limite mémoire, le noyau Linux le tue immédiatement (**OOMKilled**). S'il dépasse la limite CPU, il subit du bridage temporel (*CPU Throttling*).

1. Complétez la définition du conteneur dans `pod-frontend.yaml` avec les ressources suivantes :
   * Requests : `100m` de CPU (10% d'un cœur vCPU) et `128Mi` de RAM.
   * Limits : `250m` de CPU (25% d'un cœur vCPU) et `256Mi` de RAM.

<details>
<summary>💡 <b>Indice 3 : Bloc resources dans le manifest</b></summary>

```yaml
spec:
  containers:
  - name: campus-frontend
    image: regaieg/campus:frontend-1.0.0
    ports:
    - containerPort: 8080
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "250m"
        memory: "256Mi"
```
</details>

2. Appliquez la mise à jour :
   ```bash
   kubectl replace --force -f pod-frontend.yaml
   ```

3. Vérifiez la prise en compte des quotas dans la description officielle de Kubernetes :
   ```bash
   kubectl describe pod campus-frontend | grep -A 8 "Limits:"
   ```

---

## Exercice 5 : Pattern Avancé d'Initialisation (InitContainers)

Un **InitContainer** s'exécute et se termine **avant** que le conteneur applicatif principal ne démarre. C'est le pattern recommandé par la CNCF pour télécharger des dépendances, attendre qu'une base de données réponde ou valider des prérequis réseau.

1. Ajoutez un bloc `initContainers` dans votre fichier `pod-frontend.yaml`, **au-dessus** du bloc `containers`, sans supprimer les sections `env` et `resources` ajoutées précédemment (elles sont masquées ci-dessous pour la lisibilité) :
   ```yaml
   spec:
     initContainers:
     - name: init-check-env
       image: busybox:1.36
       command: ['sh', '-c', 'echo "[Init] Verification des prérequis Campus..." && sleep 5 && echo "[Init] Pret!"']
     containers:
     - name: campus-frontend
       image: regaieg/campus:frontend-1.0.0
       ports:
       - containerPort: 8080
       # ... env et resources des exercices 3 et 4 ...
   ```

2. Appliquez le manifest et observez la transition d'état en direct :
   ```bash
   kubectl replace --force -f pod-frontend.yaml
   kubectl get pods -w
   ```
   *Observez la progression des statuts : `Init:0/1` → `PodInitializing` → `Running` !*

3. Affichez les logs spécifiques du conteneur d'initialisation :
   ```bash
   kubectl logs campus-frontend -c init-check-env
   ```

---

## Exercice 6 : Maîtrise des Labels, Annotations & Limites du Pod Isolé

1. **Filtrer avec des sélecteurs stricts** :
   * Filtrer par composant frontend :
     ```bash
     kubectl get pods -l tier=frontend
     ```
   * Filtrer par application et environnement :
     ```bash
     kubectl get pods -l app=campus,environment=dev
     ```
   * Filtrer par négation (tous les pods qui ne sont pas backend) :
     ```bash
     kubectl get pods -l 'tier!=backend'
     ```

2. **Labels vs Annotations (Différence Fondamentale)** :
   * Les **Labels** sont indexés par le Control Plane pour l'ordonnancement, les Services et les sélecteurs (`kubectl get -l`). Ils obéissent à une syntaxe stricte (alphanumérique, pas d'arobase ni d'espaces).
   * Les **Annotations** servent aux métadonnées non sélectionnables (adresses e-mail, numéros de commit Git, payloads JSON, timestamps) :
     ```bash
     kubectl annotate pod campus-frontend contact="devops-team" release-note="initial-deployment-summer-2026" email="equipe-devops@horizon.univ"
     ```
   * Tentez de filtrer les pods par le contact annoté :
     ```bash
     kubectl get pods -l contact=devops-team
     ```
     *Constat : Aucune ressource trouvée (`No resources found`) ! Même avec une syntaxe valide, les annotations ne sont pas indexées par le sélecteur d'etcd.*

3. **Le crash-test du Pod isolé** :
   Supprimez le pod `campus-frontend` :
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
- [ ] Le Service `campus-backend` existe (sans endpoints pour l'instant) et vous savez pourquoi le frontend en a besoin.
- [ ] Vous maîtrisez la génération rapide de manifest avec `--dry-run=client -o yaml`.
- [ ] Vous savez injecter des variables d'environnement (`env`) et inspecter l'intérieur du conteneur avec `kubectl exec`.
- [ ] Vous savez encadrer la consommation mémoire et processeur avec `resources.requests` et `resources.limits`.
- [ ] Vous avez vu tourner un `initContainer` et compris son rôle dans le cycle de vie du Pod.
- [ ] Vous savez filtrer les ressources avec le paramètre `-l / --selector` et faites la distinction entre Label et Annotation.
- [ ] Vous avez constaté par vous-même l'absence de haute disponibilité d'un pod nu.
