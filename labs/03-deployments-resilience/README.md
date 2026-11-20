# Atelier 03 : Déploiements — Résilience, Rollback & Scheduling

### Objectifs Pédagogiques :
* Comprendre le rôle du contrôleur **Deployment** et de la boucle de réconciliation du **ReplicaSet**.
* Expérimenter la résilience automatique (*Self-Healing*) de Kubernetes lors de la perte brutale d'un pod.
* Déployer l'API `campus-backend` en haute disponibilité (plusieurs réplicas).
* Configurer finement la stratégie de mise à jour progressive (*Rolling Update*) avec `maxSurge` et `maxUnavailable`.
* Réagir à une livraison défectueuse : vérifier que `maxUnavailable: 0` préserve le service, puis revenir à une révision saine (*Rollback* ciblé).
* Maîtriser l'affectation des pods aux nœuds : `nodeSelector`, *taints* / *tolerations* et répartition haute disponibilité par `podAntiAffinity`.

> 📌 **Note Compatibilité OS :**  
> Toutes les commandes de cet atelier (`kubectl create deployment`, `kubectl scale`, `kubectl set image`, `kubectl rollout`) sont **rigoureusement identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)**. Seul le filtrage des logs de l'indice *CrashLoopBackOff* diffère (`grep` sous Linux/macOS, `Select-String` sous PowerShell) : les deux variantes sont fournies.
>
> 🖥️ **Environnement : le cluster 3 nœuds (1 control plane + 2 workers) du Lab 00.** La partie *Scheduling* (`nodeSelector`, taints, `podAntiAffinity`) répartit les pods entre plusieurs workers : réalisez ce lab sur ce cluster, piloté au choix :
> * **Option A (Recommandée - Confort DevOps Local) :** depuis votre machine locale, avec votre `kubectl` et votre `kubeconfig`.  
> * **Option B (PC d'entreprise verrouillé) :** en SSH sur `k8s-control` : l'outillage et les manifests sont pré-installés dans `~/labs/`.
>
> 🛟 **Secours : Minikube sur votre poste** (session AWS indisponible), piloté forcément depuis votre poste comme en Option A. Les Deployments, le *Rolling Update* et le *Rollback* fonctionnent à l'identique. Pour la partie *Scheduling*, Minikube n'a qu'un seul nœud : l'encadré « Noms des nœuds selon votre environnement » indique les écarts attendus.
>
> 🗂️ **Namespace de travail : `campus-dev`.** Ce lab est **indépendant des autres** : son étape 0 recrée `campus-dev` à neuf et y installe tout ce dont il a besoin. Vous pouvez le réaliser sans avoir fait les labs précédents, ou le recommencer à tout moment.

---

## Contexte Métier
L'API métier du campus (`campus-backend`) traite les offres de stages et les candidatures pour 25 000 étudiants. Elle ne peut souffrir d'aucune interruption de service. Vous devez la déployer sous forme d'un **Deployment** avec au moins 2 réplicas, vérifier sa résistance aux pannes, tester une montée de version applicative, ajuster les garde-fous de disponibilité et maîtriser la procédure d'urgence de retour en arrière.

* Image Backend v1 : `regaieg/campus:backend-1.0.0`
* Port d'écoute : `8080`

---

## Étape 0 : Préparer l'environnement (base de données de développement)

L'API Spring Boot se connecte à PostgreSQL **dès son démarrage** : sans base joignable, elle s'arrête en erreur et ses pods tournent en `CrashLoopBackOff`. Avant de déployer le backend, installez donc une base PostgreSQL de **développement**, fournie clé en main dans le dossier `starter/` du lab.

Repartez d'un namespace `campus-dev` vide, puis appliquez le starter. Depuis la racine du dépôt (Option A) ou depuis `~` sur `k8s-control` (Option B : mettez d'abord le dépôt à jour avec `git -C ~/formation pull`, puis remplacez `labs/` par `~/labs/`) :

```bash
kubectl delete namespace campus-dev --ignore-not-found   # ⚠️ supprime tout le contenu de campus-dev
kubectl create namespace campus-dev
kubectl config set-context --current --namespace=campus-dev
kubectl apply -f labs/03-deployments-resilience/starter/
kubectl get deployment,pods,service -l app=campus-postgres
```

*La suppression du namespace peut prendre jusqu'à une minute : `kubectl` rend la main quand elle est terminée.*

*Attendez que le pod `campus-postgres-…` soit `1/1 Running`. Le Service `postgres` rend la base joignable sous le nom DNS `postgres`, sur le port `5432`.*

<details>
<summary>💡 <b>Contenu du manifest <code>postgres-dev.yaml</code> (à lire, pas à recopier)</b></summary>

```yaml
# ==============================================================================
# Lab 03 - Base PostgreSQL de DÉVELOPPEMENT (éphémère)
# ------------------------------------------------------------------------------
# L'API campus-backend (Spring Boot + JPA) se connecte à PostgreSQL dès son
# démarrage : sans base joignable, elle s'arrête en erreur.
# Cette base de développement stocke ses données dans un volume emptyDir :
# elles DISPARAISSENT à chaque recréation du pod.
# Le Lab 05 la transformera en base persistante et sécurisée (Secret + PVC).
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
          value: "campus"          # Mot de passe en clair : acceptable en dev, corrigé au Lab 05
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

Deux choix à remarquer, que vous retravaillerez au Lab 05 :

* les données sont dans un volume **`emptyDir`** : elles sont perdues à chaque recréation du pod ;
* le mot de passe est écrit **en clair** dans le manifest.
</details>

---

1. **Générer le manifest du Deployment.** Créez un manifest de type `Deployment` nommé `deployment-backend.yaml` à l'aide de la commande `kubectl create deployment` en mode `--dry-run=client -o yaml` :
   * Nom du déploiement : `campus-backend`
   * Image : `regaieg/campus:backend-1.0.0`
   * Réplicas souhaités : `2`
   * Port : `8080`

   ```bash
   kubectl create deployment campus-backend --image=regaieg/campus:backend-1.0.0 --replicas=2 --port=8080 --dry-run=client -o yaml > deployment-backend.yaml
   ```

2. **Compléter le manifest.** Ouvrez le fichier généré `deployment-backend.yaml`. Repérez les 3 sections majeures :
   * `spec.replicas` : Le nombre d'instances désirées.
   * `spec.selector.matchLabels` : Le sélecteur qui relie le contrôleur à ses pods.
   * `spec.template` : Le modèle de pod cloné par le contrôleur.

   Renommez le conteneur en `campus-backend` : `kubectl create deployment` l'a nommé `campus`, d'après le nom de l'image. Ce nom est utilisé à l'étape 12 par `kubectl set image … campus-backend=…`.

   Supprimez les lignes `strategy: {}`, `resources: {}` et `status: {}`, puis complétez la section `env` sous `containers` pour fournir les paramètres de connexion à PostgreSQL :
   ```yaml
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: campus-backend
     template:
       metadata:
         labels:
           app: campus-backend
       spec:
         containers:
         - name: campus-backend
           image: regaieg/campus:backend-1.0.0
           ports:
           - containerPort: 8080
           env:
           - name: SPRING_DATASOURCE_URL
             value: "jdbc:postgresql://postgres:5432/campus"
           - name: SPRING_DATASOURCE_USERNAME
             value: "campus"
           - name: SPRING_DATASOURCE_PASSWORD
             value: "campus"
   ```
   > 💡 **Précision d'architecture :** L'API Spring Boot initialise son contexte Hibernate/JPA dès le démarrage. Les variables `SPRING_DATASOURCE_*` lui permettent de joindre la base de développement via le Service `postgres`. Au Lab 05, nous déplacerons ces paramètres dans un ConfigMap et un Secret dédiés.

3. **Appliquer le manifest :**
   ```bash
   kubectl apply -f deployment-backend.yaml
   ```

4. **Observer les objets créés.** Listez les déploiements, les ReplicaSets et les pods :
   ```bash
   kubectl get deployments
   kubectl get rs
   kubectl get pods -l app=campus-backend -o wide
   ```
   *Spring Boot met de 20 secondes à 2 minutes à démarrer, selon les ressources du nœud. Vérifiez la fin du démarrage dans les logs : `kubectl logs -l app=campus-backend --tail=5` doit afficher `Started CampusOpsApplication`.*

<details>
<summary>💡 <b>Indice : les pods backend redémarrent en boucle (<code>CrashLoopBackOff</code>)</b></summary>

Lisez la cause :

```bash
# Linux / macOS
kubectl logs <nom-du-pod> --previous | grep -i -m 3 "error\|exception"
```
```powershell
# Windows (PowerShell)
kubectl logs <nom-du-pod> --previous | Select-String "error|exception" | Select-Object -First 3
```

* `UnknownHostException: postgres` ou `Connection refused` : la base de développement n'est pas déployée ou pas encore prête (voir le prérequis en haut du lab).
* `password authentication failed` : les valeurs `SPRING_DATASOURCE_*` ne correspondent pas à celles du manifest `postgres-dev.yaml`.
</details>

5. **Tester la résilience (*Self-Healing*).** Identifiez le nom de l'un des deux pods `campus-backend-xxxx-yyyy`, puis supprimez-le manuellement :
   ```bash
   kubectl delete pod <nom-du-pod>
   ```

6. **Observer la réconciliation.** Exécutez immédiatement `kubectl get pods -l app=campus-backend` :
   * Que constatez-vous ?
   * Pourquoi un nouveau pod a-t-il été créé avec un âge de quelques secondes ?

<details>
<summary>💡 <b>Indice 1 : La boucle de réconciliation (Control Loop)</b></summary>

Le contrôleur `ReplicaSet` surveille en continu l'état réel du cluster par rapport à l'état désiré (`replicas: 2`). Dès qu'un pod disparaît, il en instancie immédiatement un nouveau pour combler l'écart. C'est le principe fondamental du **Self-Healing**.
</details>

7. **Monter en charge de manière impérative.** Augmentez le nombre de réplicas à 4, puis observez la création instantanée des 2 pods supplémentaires :
   ```bash
   kubectl scale deployment campus-backend --replicas=4
   kubectl get pods -l app=campus-backend
   ```

8. **Redescendre de manière déclarative.** Modifiez votre fichier `deployment-backend.yaml` pour fixer `replicas: 3`, appliquez-le, puis vérifiez que Kubernetes a proprement détruit l'instance excédentaire :
   ```bash
   kubectl apply -f deployment-backend.yaml
   kubectl get pods -l app=campus-backend
   ```

9. **Paramétrer la stratégie de Rolling Update.** Par défaut, Kubernetes utilise la stratégie `RollingUpdate` avec un remplacement progressif. En production, vous devez contrôler précisément le rythme de mise à jour pour ne jamais saturer le cluster ni dégrader la qualité de service :
   * **`maxUnavailable`** : Nombre (ou pourcentage) maximal de pods pouvant être indisponibles pendant la mise à jour (ex: `1` ou `25%`).
   * **`maxSurge`** : Nombre (ou pourcentage) maximal de pods supplémentaires pouvant être créés au-delà du nombre de réplicas souhaité (ex: `1` ou `25%`).

   Modifiez votre fichier `deployment-backend.yaml` pour expliciter la stratégie sous `spec` :
   ```yaml
   spec:
     replicas: 3
     strategy:
       type: RollingUpdate
       rollingUpdate:
         maxSurge: 1
         maxUnavailable: 0
   ```
   *(Avec `maxUnavailable: 0`, Kubernetes garantit qu'il y aura TOUJOURS au minimum 3 pods en service pendant toute la durée de la mise à jour !)*

   Appliquez le manifest :
   ```bash
   kubectl apply -f deployment-backend.yaml
   ```

10. **Livrer une nouvelle version.** Toute modification du gabarit de pod (image, variable, ressources…) déclenche un *rolling update*. Ajoutez une variable de version et documentez la raison du changement :
    ```bash
    kubectl set env deployment/campus-backend CAMPUS_RELEASE=1.0.1
    kubectl annotate deployment/campus-backend kubernetes.io/change-cause="Livraison 1.0.1 : variable CAMPUS_RELEASE"
    ```
    > 💡 Réappliquer exactement la même image (`kubectl set image … backend-1.0.0`) ne déclencherait **rien** : Kubernetes ne compare que l'état désiré et l'état réel, et ils seraient identiques.

11. **Suivre le rolling update.** Suivez en temps réel la progression, puis observez les deux ReplicaSets (l'ancien est conservé à 0 réplica pour permettre un retour arrière) :
    ```bash
    kubectl rollout status deployment/campus-backend
    kubectl get rs -l app=campus-backend
    ```

12. **Provoquer un incident en production.** Imaginons qu'une erreur de saisie ou un bug critique survienne lors d'un déploiement : l'équipe déploie par erreur une image taguée `regaieg/campus:backend-invalid-tag`. Déclenchez ce déploiement erroné :
    ```bash
    kubectl set image deployment/campus-backend campus-backend=regaieg/campus:backend-invalid-tag
    kubectl annotate deployment/campus-backend kubernetes.io/change-cause="Livraison erronée : backend-invalid-tag" --overwrite
    ```
    > 💡 L'annotation `change-cause` est recopiée telle quelle dans chaque nouvelle révision : sans ce `--overwrite`, la révision fautive afficherait encore « Livraison 1.0.1 » dans l'historique, ce qui égarerait le diagnostic.

13. **Observer l'incident** avec `kubectl get pods -l app=campus-backend -w` :
    * Vous reconnaissez sur le nouveau pod le statut `ErrImagePull` / `ImagePullBackOff` rencontré au Lab 02. Pourquoi le service n'est-il pas coupé ?
    * Les 3 anciens pods v1.0.0 continuent-ils de servir les utilisateurs ?  
    * **Explication :** Comme nous avons configuré `maxUnavailable: 0`, Kubernetes refuse de tuer les anciens pods tant que le nouveau pod n'est pas devenu opérationnel. **Le service ne subit aucune coupure !**

14. **Consulter l'historique des révisions.** Affichez l'historique complet, puis le détail d'une révision spécifique (ex: révision 1) :
    ```bash
    kubectl rollout history deployment/campus-backend
    kubectl rollout history deployment/campus-backend --revision=1
    ```
    *La colonne `CHANGE-CAUSE` affiche le texte de l'annotation `kubernetes.io/change-cause` : c'est ce qui rend un historique lisible en situation d'incident. La révision 1, créée avant toute annotation, affiche `<none>` ; la révision fautive affiche « Livraison erronée ».*

15. **Revenir en arrière (*Rollback*).** Déclenchez immédiatement le retour à la version saine précédente :
    ```bash
    kubectl rollout undo deployment/campus-backend
    ```
    *Ou pour cibler précisément une révision :* `kubectl rollout undo deployment/campus-backend --to-revision=1`.

    > 💡 `kubectl` affiche un avertissement `resource deployments/campus-backend was previously managed with 'kubectl apply'…` : le rollback ne met pas à jour l'annotation utilisée par `kubectl apply`. C'est attendu, et l'étape 17 corrige cet écart.

16. **Vérifier la résolution de l'incident :**
    ```bash
    kubectl rollout status deployment/campus-backend
    kubectl get pods -l app=campus-backend
    ```

17. **Réaligner le cluster sur le fichier versionné.** Les commandes `kubectl set …` et `kubectl annotate` des étapes 10 et 12 ont modifié directement l'objet dans le cluster, **pas** votre fichier `deployment-backend.yaml`. Après le rollback, la variable `CAMPUS_RELEASE` est toujours présente dans le cluster, mais pas dans le fichier. Un simple `kubectl apply -f` ne l'effacerait pas : `apply` ne retire que les champs qu'il a lui-même posés. Remplacez l'objet entier par le contenu du fichier, puis vérifiez :
    ```bash
    kubectl replace --save-config -f deployment-backend.yaml
    kubectl rollout status deployment/campus-backend
    kubectl get deployment campus-backend -o jsonpath='{.spec.template.spec.containers[0].env[*].name}'
    ```
    *Seules les trois variables `SPRING_DATASOURCE_*` du fichier subsistent. `--save-config` conserve l'annotation dont `kubectl apply` a besoin pour la suite. C'est pourquoi, en équipe, on modifie toujours le fichier versionné plutôt que l'objet en direct.*

18. **Provoquer un pod `Pending` (`nodeSelector`).** Par défaut, le **kube-scheduler** choisit librement le nœud de chaque pod en fonction des ressources disponibles. En production, on doit pourtant souvent **contraindre** ce placement : réserver des nœuds à une équipe, éloigner les charges critiques des nœuds de supervision, ou répartir les réplicas sur des machines différentes pour survivre à la perte d'un nœud. Kubernetes propose 3 mécanismes complémentaires :

    | Mécanisme | Qui décide ? | Question posée | Usage typique |
    | :--- | :--- | :--- | :--- |
    | `nodeSelector` / `nodeAffinity` | Le **pod** | « Sur quels nœuds ai-je le droit d'aller ? » | Nœuds GPU, SSD, zone de disponibilité |
    | `taints` / `tolerations` | Le **nœud** | « Quels pods ai-je le droit de refuser ? » | Nœuds dédiés (monitoring, plan de contrôle) |
    | `podAntiAffinity` | Le **pod** | « Loin de quels autres pods dois-je être ? » | Haute disponibilité : 1 réplica par nœud |

    > 📌 **Noms des nœuds selon votre environnement :** `k8s-worker-1` / `k8s-worker-2` sur AWS (Lab 00), `node01` sur KillerCoda, `minikube` sur Minikube. Vérifiez avec `kubectl get nodes`. Minikube n'a qu'un seul nœud : utilisez `minikube` à la place des deux workers. À l'étape 21, le nouveau pod reste alors `Pending` jusqu'au retrait de la taint à l'étape 22 (comportement attendu), et la répartition entre nœuds n'est pas observable.

    Ajoutez un `nodeSelector` dans le gabarit de pod de `deployment-backend.yaml` (au même niveau que `containers`). **Aucun nœud ne porte encore ce label :**
    ```yaml
        spec:
          nodeSelector:
            campus/tier: api
          containers:
          - name: campus-backend
    ```

    Appliquez, puis lisez le diagnostic du Scheduler :
    ```bash
    kubectl apply -f deployment-backend.yaml
    kubectl get events --field-selector reason=FailedScheduling
    ```
    *Le nouveau pod reste `Pending` : aucun nœud ne lui convient. Les 3 anciens pods continuent de servir grâce à `maxUnavailable: 0`.*

<details>
<summary>💡 <b>Indice 2 : Lire le message du Scheduler</b></summary>

L'événement `FailedScheduling` contient un message du type :
`0/3 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }, 2 node(s) didn't match Pod's node affinity/selector.`

Lisez-le de droite à gauche : 2 workers refusés car le label ne correspond pas, 1 nœud refusé à cause d'une **taint**. C'est exactement le diagnostic à faire face à un pod `Pending` en production. Le même message apparaît dans la section `Events` de `kubectl describe pod <nom-du-pod>`.
</details>

19. **Étiqueter un nœud : le Scheduler réessaie tout seul.** Posez le label sur le premier worker, puis observez :
    ```bash
    kubectl label node k8s-worker-1 campus/tier=api
    kubectl rollout status deployment/campus-backend
    kubectl get pods -l app=campus-backend -o wide
    ```
    *Sans nouvel `apply`, le pod `Pending` est placé dès que le label apparaît : le Scheduler réévalue en continu les pods en attente. Les 3 réplicas sont désormais regroupés sur `k8s-worker-1`.*

20. **Réserver un nœud avec une taint.** Réservez le second worker à la future pile de supervision (Lab 06), puis affichez les taints de tous les nœuds :
    ```bash
    kubectl taint node k8s-worker-2 dedicated=monitoring:NoSchedule
    kubectl get nodes -o custom-columns=NOM:.metadata.name,TAINTS:.spec.taints
    ```
    *Deux nœuds refusent désormais les pods ordinaires : `k8s-worker-2`, avec votre taint `dedicated=monitoring`, et `k8s-control`, avec la taint `node-role.kubernetes.io/control-plane:NoSchedule` posée par Kubeadm. C'est elle qui protège `etcd` et l'API Server de vos charges applicatives : voilà pourquoi aucun pod applicatif ne tourne sur le plan de contrôle.*

<details>
<summary>💡 <b>Indice 3 : Et si un pod doit malgré tout aller sur ce nœud ?</b></summary>

Il doit déclarer une **toleration** correspondante dans son `spec` :

```yaml
tolerations:
- key: "dedicated"
  operator: "Equal"
  value: "monitoring"
  effect: "NoSchedule"
```

Attention : une toleration **autorise** le pod à aller sur le nœud, elle ne l'y **oblige** pas. Pour réserver réellement un nœud, on combine taint (côté nœud) et `nodeSelector`/`nodeAffinity` (côté pod).
</details>

21. **Haute disponibilité : un réplica par nœud (`podAntiAffinity`).** Si vos 3 réplicas tournent sur le même worker, la perte de ce nœud coupe l'API. Dans `deployment-backend.yaml`, **remplacez** le bloc `nodeSelector` par une règle qui demande au Scheduler de **préférer** des nœuds différents :
    ```yaml
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
    ```

    Appliquez, puis observez la colonne `NODE` :
    ```bash
    kubectl apply -f deployment-backend.yaml
    kubectl rollout status deployment/campus-backend
    kubectl get pods -l app=campus-backend -o wide
    ```
    *Les 3 pods démarrent tous sur `k8s-worker-1` : `k8s-worker-2` et `k8s-control` les refusent à cause de leurs taints. Une taint est une **interdiction**, l'anti-affinité `preferred…` n'est qu'un **souhait** : faute de mieux, le Scheduler place quand même les pods au lieu de les laisser en `Pending`. Une règle `required…` (obligation) aurait, elle, bloqué les 2e et 3e pods en `Pending`.*

22. **Libérer le nœud et répartir les réplicas.** Retirez la taint et le label (le `-` final retire l'élément) :
    ```bash
    kubectl taint node k8s-worker-2 dedicated=monitoring:NoSchedule-
    kubectl label node k8s-worker-1 campus/tier-
    ```
    Les pods ne bougent pas : la règle est `…IgnoredDuringExecution`, le Scheduler ne l'applique qu'à la **création** d'un pod et ne déplace jamais un pod déjà en place. Supprimez donc l'un des pods (nom relevé à l'étape 21), puis observez où part son remplaçant :
    ```bash
    kubectl delete pod <nom-d-un-pod-backend>
    kubectl get pods -l app=campus-backend -o wide
    ```
    *Le remplaçant part sur `k8s-worker-2`, le nœud qui n'a aucun pod `campus-backend` : les réplicas sont répartis (2 + 1). Avec 3 réplicas et 2 workers, deux pods partagent forcément un nœud. Pendant quelques secondes, il ne reste que 2 réplicas : `maxUnavailable` ne protège que les mises à jour, pas une suppression manuelle.*

    > 💡 **Pourquoi pas `kubectl rollout restart` ?** Pendant une mise à jour progressive, les anciens pods (même en cours d'arrêt, `Terminating`) occupent encore `k8s-worker-1` : le Scheduler l'évite et envoie les 3 nouveaux pods… tous sur `k8s-worker-2`. Il faudrait un second redémarrage pour obtenir la répartition.

    Conservez le bloc `podAntiAffinity` : c'est une bonne pratique de production. Le label et la taint étant retirés, le cluster repart d'un état neutre au Lab 04.

<details>
<summary>💡 <b>État attendu de <code>deployment-backend.yaml</code> en fin de Lab 03 (point de départ des labs suivants)</b></summary>

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: campus-backend
spec:
  replicas: 3
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
        env:
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:postgresql://postgres:5432/campus"
        - name: SPRING_DATASOURCE_USERNAME
          value: "campus"
        - name: SPRING_DATASOURCE_PASSWORD
          value: "campus"
```
</details>

---

## Critères de Validation (Checklist)

- [ ] `campus-backend` est déployé avec un fichier `deployment-backend.yaml` versionné.
- [ ] Vous avez vérifié le self-healing en détruisant un pod en direct.
- [ ] Vous maîtrisez le dimensionnement dynamique (`scale`).
- [ ] Vous comprenez le rôle de `maxSurge` et `maxUnavailable` pour garantir zéro coupure.
- [ ] Vous maîtrisez les commandes d'urgence SRE : `kubectl rollout status`, `kubectl rollout history` et `kubectl rollout undo`.
- [ ] Vous savez épingler des pods sur un nœud (`nodeSelector`) et diagnostiquer un pod `Pending` à partir de l'événement `FailedScheduling`.
- [ ] Vous expliquez pourquoi aucun pod applicatif ne tourne sur `k8s-control` (taint `control-plane:NoSchedule`).
- [ ] Les réplicas de `campus-backend` sont répartis sur plusieurs workers grâce à `podAntiAffinity`.
