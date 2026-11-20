# Lab 03 :  Déploiements, Résilience,  Rollback & Scheduling

### Objectifs Pédagogiques :
* Comprendre le rôle du contrôleur **Deployment** et de la boucle de réconciliation du **ReplicaSet**.
* Expérimenter la résilience automatique (*Self-Healing*) de Kubernetes lors de la perte brutale d'un pod.
* Déployer l'API `campus-backend` en haute disponibilité (plusieurs réplicas).
* Configurer finement la stratégie de mise à jour progressive (*Rolling Update*) avec `maxSurge` et `maxUnavailable`.
* Réagir à une livraison défectueuse : vérifier que `maxUnavailable: 0` préserve le service, puis revenir à une révision saine (*Rollback* ciblé).
* Maîtriser l'affectation des pods aux nœuds : `nodeSelector`, *taints* / *tolerations* et répartition haute disponibilité par `podAntiAffinity`.

> 📌 **Note Compatibilité OS :**  
> Toutes les commandes de cet atelier (`kubectl create deployment`, `kubectl scale`, `kubectl set image`, `kubectl rollout`) sont **rigoureusement identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)**.
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

---

## Contexte Métier
L'API métier du campus (`campus-backend`) traite les offres de stages et les candidatures pour 25 000 étudiants. Elle ne peut souffrir d'aucune interruption de service. Vous devez la déployer sous forme d'un **Deployment** avec au moins 2 réplicas, vérifier sa résistance aux pannes, tester une montée de version applicative, ajuster les garde-fous de disponibilité et maîtriser la procédure d'urgence de retour en arrière.

* Image Backend v1 : `regaieg/campus:backend-1.0.0`
* Port d'écoute : `8080`

---

## Prérequis : La Base de Données de Développement

L'API Spring Boot se connecte à PostgreSQL **dès son démarrage** : sans base joignable, elle s'arrête en erreur et ses pods tournent en `CrashLoopBackOff`. Avant de déployer le backend, installez donc une base PostgreSQL de **développement**, fournie clé en main.

Depuis la racine du dépôt (Option A) ou depuis `~` sur `k8s-control` (Option B, remplacez `labs/` par `~/labs/`) :

```bash
kubectl apply -f labs/03-deployments-resilience/starter/postgres-dev.yaml
kubectl get deployment,pods,service -l app=campus-postgres
```

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

Lisez la cause : `kubectl logs <nom-du-pod> --previous | grep -i -m 3 "error\|exception"`.

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

18. **Épingler le backend sur un nœud (`nodeSelector`).** Par défaut, le **kube-scheduler** choisit librement le nœud de chaque pod en fonction des ressources disponibles. En production, on doit pourtant souvent **contraindre** ce placement : réserver des nœuds à une équipe, éloigner les charges critiques des nœuds de supervision, ou répartir les réplicas sur des machines différentes pour survivre à la perte d'un nœud. Kubernetes propose 3 mécanismes complémentaires :

    | Mécanisme | Qui décide ? | Question posée | Usage typique |
    | :--- | :--- | :--- | :--- |
    | `nodeSelector` / `nodeAffinity` | Le **pod** | « Sur quels nœuds ai-je le droit d'aller ? » | Nœuds GPU, SSD, zone de disponibilité |
    | `taints` / `tolerations` | Le **nœud** | « Quels pods ai-je le droit de refuser ? » | Nœuds dédiés (monitoring, plan de contrôle) |
    | `podAntiAffinity` | Le **pod** | « Loin de quels autres pods dois-je être ? » | Haute disponibilité : 1 réplica par nœud |

    > 📌 **Noms des nœuds selon votre environnement :** `k8s-worker-1` / `k8s-worker-2` sur AWS (Lab 00), `node01` sur KillerCoda, `minikube` sur Minikube. Minikube n'a qu'un seul nœud, sans taint : l'étape 21 affiche `<none>` ; à l'étape 22, la taint posée sur l'unique nœud laisse le nouveau pod en `Pending` jusqu'à son retrait à l'étape 23 (comportement attendu) ; à l'étape 24, tous les réplicas restent sur le même nœud. Vérifiez avec `kubectl get nodes`.

    Posez un label métier sur le premier worker :
    ```bash
    kubectl label node k8s-worker-1 campus/tier=api
    kubectl get nodes -L campus/tier
    ```

    Ajoutez un `nodeSelector` dans le gabarit de pod de `deployment-backend.yaml` (au même niveau que `containers`) :
    ```yaml
        spec:
          nodeSelector:
            campus/tier: api
          containers:
          - name: campus-backend
    ```

    Appliquez puis observez la colonne `NODE` :
    ```bash
    kubectl apply -f deployment-backend.yaml
    kubectl get pods -l app=campus-backend -o wide
    ```
    *Tous les réplicas sont désormais regroupés sur `k8s-worker-1`.*

19. **Provoquer et diagnostiquer un pod `Pending`.** Remplacez la valeur par un label qui n'existe sur aucun nœud (`campus/tier: gpu`) et appliquez. Observez le nouveau pod bloqué en `Pending` (les anciens restent en service grâce à `maxUnavailable: 0`) :
    ```bash
    kubectl get pods -l app=campus-backend -o wide
    kubectl describe pod <nom-du-pod-pending> | tail -n 5
    ```

<details>
<summary>💡 <b>Indice 2 : Lire le message du Scheduler</b></summary>

La section `Events` contient un événement `FailedScheduling` du type :
`0/3 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }, 2 node(s) didn't match Pod's node affinity/selector.`

Lisez-le de droite à gauche : 2 workers refusés car le label ne correspond pas, 1 nœud refusé à cause d'une **taint**. C'est exactement le diagnostic à faire face à un pod `Pending` en production.
</details>

20. **Revenir à un état sain.** Remettez la valeur `campus/tier: api` et appliquez.

21. **Comprendre les taints : pourquoi aucun pod ne tourne sur le plan de contrôle.** Affichez les taints de tous les nœuds :
    ```bash
    kubectl get nodes -o custom-columns=NOM:.metadata.name,TAINTS:.spec.taints
    ```
    *Le nœud `k8s-control` porte la taint `node-role.kubernetes.io/control-plane:NoSchedule` posée par Kubeadm : c'est elle qui protège `etcd` et l'API Server de vos charges applicatives.*

22. **Réserver un nœud avec une taint.** Réservez le second worker à la future pile de supervision (Lab 06) :
    ```bash
    kubectl taint node k8s-worker-2 dedicated=monitoring:NoSchedule
    ```

    Retirez le `nodeSelector` de votre manifest, appliquez, puis forcez une redistribution :
    ```bash
    kubectl apply -f deployment-backend.yaml
    kubectl rollout restart deployment/campus-backend
    kubectl get pods -l app=campus-backend -o wide
    ```
    *Aucun pod backend n'atterrit sur `k8s-worker-2` : il ne tolère pas la taint.*

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

23. **Retirer la taint** (le `-` final retire la taint) :
    ```bash
    kubectl taint node k8s-worker-2 dedicated=monitoring:NoSchedule-
    ```

24. **Haute disponibilité : un réplica par nœud (`podAntiAffinity`).** Si vos 3 réplicas tournent sur le même worker, la perte de ce nœud coupe l'API. Demandez au Scheduler de **préférer** des nœuds différents en ajoutant au gabarit de pod (au même niveau que `containers`) :
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

    Appliquez, puis relancez une fois les pods et vérifiez la répartition :
    ```bash
    kubectl apply -f deployment-backend.yaml
    kubectl rollout status deployment/campus-backend
    kubectl rollout restart deployment/campus-backend
    kubectl rollout status deployment/campus-backend
    kubectl get pods -l app=campus-backend -o wide
    ```
    *Pourquoi relancer ? Pendant la première mise à jour progressive, les anciens pods (tous sur `k8s-worker-1` depuis l'étape 22) portent eux aussi le label `app=campus-backend` : le Scheduler évite ce nœud et place les 3 nouveaux pods sur `k8s-worker-2`. Au redémarrage suivant, le premier nouveau pod part forcément sur le worker libre. Les réplicas sont répartis entre `k8s-worker-1` et `k8s-worker-2`. Avec 3 réplicas et 2 workers, deux pods partagent forcément un nœud : c'est pourquoi on utilise `preferred…` (souhait) plutôt que `required…` (obligation), qui laisserait le 3e pod en `Pending`.*

25. **Nettoyer le label de nœud** pour repartir d'un état neutre au Lab 04 :
    ```bash
    kubectl label node k8s-worker-1 campus/tier-
    ```
    Conservez en revanche le bloc `podAntiAffinity` : c'est une bonne pratique de production.

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
- [ ] Vous savez épingler des pods sur un nœud (`nodeSelector`) et diagnostiquer un pod `Pending` avec `kubectl describe`.
- [ ] Vous expliquez pourquoi aucun pod applicatif ne tourne sur `k8s-control` (taint `control-plane:NoSchedule`).
- [ ] Les réplicas de `campus-backend` sont répartis sur plusieurs workers grâce à `podAntiAffinity`.
