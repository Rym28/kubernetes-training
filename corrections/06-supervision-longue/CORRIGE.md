# Corrigé — Atelier 06 (version longue) : Exploitation, Observabilité & Reverse Debugging

> 🔒 **Confidentiel formateur.** À diffuser en fin d'atelier uniquement. Énoncé : `corrections/06-supervision-longue/README.md` (archive de la version longue, ~1 h 45). La version en vigueur et son corrigé sont `labs/06-Administration & Supervision/README.md` et `corrections/06-supervision/CORRIGE.md`.

Toutes les commandes s'exécutent depuis le dossier du lab (`cd "labs/06-Administration & Supervision"`), namespace courant `campus-dev`.

---

## Étape 0 — Préparer l'environnement

Commandes données dans l'énoncé. Attendu :

* `secret/campus-db-credentials created` (ou `configured`), puis les objets du starter : `configmap/campus-config`, `persistentvolume/pv-postgres`, `persistentvolumeclaim/pvc-postgres`, les Deployments `campus-postgres`, `campus-backend` (2 réplicas), `campus-frontend` (2 réplicas) et les Services `postgres`, `campus-backend`, `campus-frontend-svc` (NodePort 30088).
* La vérification des logs renvoie **2 lignes** `Started CampusOpsApplication in … seconds`, une par pod backend.

Erreur fréquente : oublier le Secret. Les pods backend restent alors en `CreateContainerConfigError` (`secret "campus-db-credentials" not found`), visible avec `kubectl describe pod`.

---

## Exercice 1 — Lire les logs et les événements

### Étape 1 — Lire et suivre les logs du backend

```bash
kubectl logs -f deployment/campus-backend --tail=20
```

**1.** La ligne `Started CampusOpsApplication in 12.5 seconds (process running for 13.7)` marque la fin du démarrage. La durée varie de 10 à 60 secondes selon la charge du nœud.

**2.** Les lignes viennent d'**un seul** pod : `kubectl logs deployment/…` choisit l'un des pods du Deployment et l'annonce par `Found 2 pods, using pod/campus-backend-xxxx-yyyy`. Pour lire tous les pods, il faut un sélecteur de labels (étape 2).

### Étape 2 — Lire les logs de tous les pods d'une étiquette

```bash
kubectl logs -l app=campus-backend --tail=5 --prefix
```

**1.** 10 lignes : les 5 dernières de chacun des **2** pods backend, chacune précédée de `[pod/campus-backend-…/campus-backend]`.

**2.** `--previous` (ou `-p`) : `kubectl logs <pod> --previous` lit les logs de l'instance précédente du conteneur, celle qui a planté. Vue dans l'indice *CrashLoopBackOff* de l'Atelier 03.

### Étape 3 — Lire la chronologie des événements

```bash
kubectl get events --sort-by=.metadata.creationTimestamp
```

**1.** Pour un pod : `Scheduled` (le Scheduler l'a placé sur un nœud) → `Pulling` / `Pulled` (image téléchargée, ou déjà présente) → `Created` → `Started` (le kubelet a lancé le conteneur). On voit aussi `ScalingReplicaSet` (Deployment) et `SuccessfulCreate` (ReplicaSet).

**2.** Non : les logs d'un pod sont stockés sur le nœud avec le conteneur et **disparaissent avec le pod**. Pour les conserver, il faut les centraliser hors du pod : agent de collecte sur chaque nœud (Fluent Bit) + stockage (Loki), vus à l'exercice 5. Les événements eux-mêmes ne sont conservés qu'une heure par défaut.

---

## Exercice 2 — Exécuter une commande dans un conteneur

### Étape 1 — Vérifier la configuration reçue par le backend

```bash
kubectl exec deployment/campus-backend -- sh -c "env | grep SPRING"
```

Sortie attendue (ordre variable) :

```text
SPRING_PROFILES_ACTIVE=production
SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/campus
SPRING_DATASOURCE_USERNAME=campus
SPRING_DATASOURCE_PASSWORD=CampusSecret2026!
```

**1.** Commande ci-dessus. Le `sh -c "…"` est indispensable : sans lui, le `| grep` serait exécuté par le terminal local (ça « marche » sous Bash, mais le filtrage se fait sur le poste ; sous PowerShell, `grep` n'existe pas). Variante sans `sh -c` côté PowerShell : `kubectl exec deployment/campus-backend -- env | Select-String SPRING`.

**2.** `jdbc:postgresql://postgres:5432/campus`. Elle est écrite directement dans le manifest du Deployment (`env.value` de `starter/03-backend.yaml`), ni dans le ConfigMap ni dans le Secret. Le ConfigMap `campus-config` fournit `SPRING_PROFILES_ACTIVE` (via `envFrom`) ; le Secret `campus-db-credentials` fournit `SPRING_DATASOURCE_USERNAME` et `SPRING_DATASOURCE_PASSWORD` (via `secretKeyRef`).

**3.** Oui, en clair : un Secret est décodé quand il est injecté dans le conteneur. Toute personne autorisée à faire `kubectl exec` (verbe `create` sur la ressource `pods/exec`) lit donc les Secrets de l'application. L'Atelier 07 restreint ces droits avec le RBAC.

Erreurs fréquentes : `kubectl exec campus-backend -- …` (`pods "campus-backend" not found` : il faut le nom d'un pod ou `deployment/campus-backend`) ; oublier `--`.

### Étape 2 — Vérifier le réseau vu du frontend

```bash
kubectl exec deployment/campus-frontend -- wget -qO- http://campus-backend:8080/actuator/health
```

**1.** `{"status":"UP","components":{"db":{"status":"UP",…},…}}` : l'API répond et sa base est joignable. Le frontend joint bien le backend.

**2.** Par le nom `campus-backend`, qui est le nom du **Service** ClusterIP du backend. CoreDNS le résout en l'adresse virtuelle du Service, qui répartit vers les pods (Atelier 04).

---

## Exercice 3 — Dépanner avec méthode

### Étape 1 — Incident A : `CrashLoopBackOff`

```bash
kubectl run crash-app --image=busybox:1.36 -- sh -c "echo Demarrage; sleep 3; echo Erreur fatale; exit 42"
kubectl get pod crash-app -w
```

**1.** `ContainerCreating` → `Running` → `Error` → `Running` → `Error` → `CrashLoopBackOff`. `RESTARTS` augmente à chaque échec ; le délai entre deux tentatives double (10 s, 20 s, 40 s… plafonné à 5 minutes). `kubectl run` crée un pod avec `restartPolicy: Always` : le kubelet le relance sans fin.

**2.** `kubectl describe pod crash-app` :

```text
    State:          Waiting
      Reason:       CrashLoopBackOff
    Last State:     Terminated
      Reason:       Error
      Exit Code:    42
```

Un code différent de 0 signifie que le **processus** s'est arrêté sur une erreur : c'est l'application (ici le script) qui est en cause, pas Kubernetes.

Filtrer la sortie : `kubectl describe pod crash-app | grep -A 4 "Last State"` (Bash) ou `kubectl describe pod crash-app | Select-String "Last State" -Context 0,4` (PowerShell).

**3.** `kubectl logs crash-app --previous` → `Demarrage` puis `Erreur fatale`.

**4.** `kubectl delete pod crash-app`.

Erreur fréquente : `kubectl logs crash-app` sans `--previous` affiche une sortie vide ou partielle (le conteneur courant vient de redémarrer).

### Étape 2 — Incident B : `OOMKilled`

```bash
kubectl apply -f manifests/oom-victim.yaml
kubectl get pod oom-victim -w
```

**1.** `OOMKilled`, puis `CrashLoopBackOff` (le conteneur est relancé et retué à chaque tentative).

**2.** `kubectl describe pod oom-victim` → `Last State: Terminated`, `Reason: OOMKilled`, `Exit Code: 137` (128 + signal 9, `SIGKILL`). C'est le **noyau Linux** du nœud (l'*OOM killer*, via le cgroup mémoire du conteneur) qui a tué le processus, car il dépassait `limits.memory: 50Mi`. Kubernetes ne fait que constater.

**3.** Augmenter `limits.memory` (au-dessus de la consommation réelle, mesurée avec `kubectl top`), ou réduire la consommation de l'application (ici, les 150 Mo demandés à `stress` ; pour une JVM, `-XX:MaxRAMPercentage`).

**4.** `kubectl delete pod oom-victim` (ou `kubectl delete -f manifests/oom-victim.yaml`).

À souligner : CrashLoopBackOff n'est pas une cause, c'est un symptôme. La cause se lit dans `Last State` : `Error` + `Exit Code` (application) ou `OOMKilled` (limite mémoire).

### Étape 3 — Incident C : Service sans réponse

```bash
kubectl create service clusterip campus-api --tcp=8080:8080
kubectl run test-api --image=curlimages/curl:8.11.1 --rm -i --restart=Never -- curl -s -m 5 http://campus-api:8080/actuator/health
```

**1.** « Service muet ? `kubectl get endpoints` » :

```bash
kubectl get endpoints campus-api
```

```text
NAME         ENDPOINTS   AGE
campus-api   <none>      30s
```

Aucun pod derrière le Service : le nom se résout (le Service existe, avec une `CLUSTER-IP`), mais le trafic n'a nulle part où aller.

**2.** `kubectl describe service campus-api` → `Selector: app=campus-api`. `kubectl get pods -l app=campus-backend --show-labels` → les pods portent `app=campus-backend` (plus `pod-template-hash=…`). `kubectl create service` a fabriqué le sélecteur `app=<nom du service>` : il ne correspond à aucun pod.

**3.** Après `kubectl set selector service campus-api app=campus-backend`, `kubectl get endpoints campus-api` liste les 2 pods backend (`192.168.x.x:8080,192.168.y.y:8080`) et le pod de test affiche `{"status":"UP",…}`.

Nettoyage : `kubectl delete service campus-api`.

Autre correction acceptable : `kubectl edit service campus-api` ou `kubectl expose deployment campus-backend --name=campus-api --port=8080` après suppression (le sélecteur est alors recopié du Deployment, comme à l'Atelier 04).

---

## Exercice 4 — Détecter une panne de nœud

### Étape 1 — Déployer Node Problem Detector

```bash
kubectl apply -f npd/npd.yaml
kubectl rollout status daemonset/node-problem-detector -n kube-system
kubectl get pods -n kube-system -l app=node-problem-detector -o wide
```

**1.** **2 pods**, un sur `k8s-worker-1` et un sur `k8s-worker-2`. Aucun sur `k8s-control` : le DaemonSet NPD ne tolère pas la taint `node-role.kubernetes.io/control-plane:NoSchedule` posée par kubeadm.

**2.** `kubectl describe node k8s-worker-1`, section `Conditions` :

```text
Type                 Status  Reason                       Message
KernelDeadlock       False   KernelHasNoDeadlock          kernel has no deadlock
ReadonlyFilesystem   False   FilesystemIsNotReadOnly      Filesystem is not read-only
NetworkUnavailable   False   CalicoIsUp                   Calico is running on this node
MemoryPressure       False   KubeletHasSufficientMemory   …
DiskPressure         False   KubeletHasNoDiskPressure     …
PIDPressure          False   KubeletHasSufficientPID      …
Ready                True    KubeletReady                 …
```

NPD a ajouté `KernelDeadlock` et `ReadonlyFilesystem`, à `False` (pas de problème). `NetworkUnavailable` est posée par Calico ; les quatre dernières viennent du kubelet.

Filtrer : `kubectl describe node k8s-worker-1 | grep -A 12 "Conditions:"` (Bash) ou `… | Select-String "Conditions:" -Context 0,12` (PowerShell).

### Étape 2 — Simuler une erreur du noyau

```bash
kubectl apply -f manifests/inject-kernel-err.yaml
kubectl get events -A --field-selector reason=KernelDeadlock
kubectl delete pod inject-kernel-err
```

L'événement apparaît dans le namespace `default` (un nœud n'appartient à aucun namespace) : `Warning  KernelDeadlock  node/k8s-worker-1  kernel: BUG: unable to handle kernel NULL pointer dereference…`.

**1.** `kubectl describe node k8s-worker-1` → `KernelDeadlock   True   KernelDeadlock   kernel: BUG: unable to handle kernel NULL pointer dereference…`. NPD a reconnu dans `/dev/kmsg` un motif de sa configuration (`npd/npd.yaml`, règle `permanent` → condition `KernelDeadlock`).

**2.** Oui, `kubectl get nodes` affiche toujours `Ready` : la condition `Ready` vient du kubelet, qui fonctionne. Le Scheduler continuerait donc d'envoyer des pods sur un nœud dont le noyau est en panne. NPD signale ; il ne bloque rien.

Si la condition reste à `False` : attendre 10 à 20 secondes et relancer. Vérifier que le pod `inject-kernel-err` est bien passé en `Completed` (`kubectl get pod inject-kernel-err`) ; s'il est refusé, une Pod Security Admission bloque peut-être les pods privilégiés dans `campus-dev` (cas d'un cluster déjà durci par l'Atelier 07).

### Étape 3 — Retirer le nœud du service

```bash
kubectl cordon k8s-worker-1
kubectl get nodes
kubectl uncordon k8s-worker-1
```

**1.** `Ready,SchedulingDisabled`. `cordon` pose la taint `node.kubernetes.io/unschedulable:NoSchedule` (et `spec.unschedulable: true`).

**2.** Non : `cordon` ne touche pas aux pods existants (vérifiable avec `kubectl get pods -o wide`, colonne `NODE`). Il empêche seulement le Scheduler d'en placer de nouveaux.

**3.** `kubectl drain k8s-worker-1 --ignore-daemonsets` : `cordon` + éviction des pods, recréés par leurs contrôleurs sur les autres nœuds. `--ignore-daemonsets` est nécessaire car les pods de DaemonSet (NPD, Fluent Bit, Calico, kube-proxy) ne peuvent pas être déplacés ; `--delete-emptydir-data` est requis si un pod utilise un `emptyDir`. Après la réparation : `kubectl uncordon`.

La condition `KernelDeadlock=True` reste affichée quelques minutes après l'`uncordon` : elle est indépendante du cordon, et NPD ne la remet à `False` qu'au redémarrage de son pod, **et seulement si le message est sorti de sa fenêtre d'analyse** (`"lookback": "5m"` dans `npd/npd.yaml`). Pour la remettre à zéro en fin de lab, **au moins 5 minutes après l'injection** : `kubectl delete pod -n kube-system -l app=node-problem-detector --field-selector spec.nodeName=k8s-worker-1`. Constaté en préparation : un redémarrage 2 ou 4 minutes après l'injection relit le message et remet la condition à `True` ; à 7 minutes, elle repasse à `False` en 5 secondes.

Piège à signaler : un `drain` déplacerait `campus-postgres` si elle tourne sur ce nœud. Son PV `pv-postgres` est un répertoire du disque de `k8s-worker-1` (`nodeAffinity`) : le pod resterait `Pending` jusqu'à l'`uncordon` (Atelier 05).

---

## Exercice 5 — Mesurer la consommation et centraliser les logs

### Étape 1 — Déployer la pile de supervision

```bash
kubectl apply -f monitoring/00-namespace.yaml -f monitoring/01-metrics-server.yaml -f monitoring/02-loki.yaml -f monitoring/03-fluentbit.yaml -f monitoring/04-prometheus.yaml -f monitoring/05-grafana.yaml
kubectl get pods -n monitoring
kubectl rollout restart deployment/campus-backend
kubectl rollout status deployment/campus-backend
```

**1.** **3 pods `fluent-bit`**, un par nœud y compris `k8s-control` : Fluent Bit est un DaemonSet qui **tolère** la taint du control plane (bloc `tolerations` de `03-fluentbit.yaml`), pour collecter aussi les logs des composants système. À comparer avec NPD (2 pods, étape 1 de l'exercice 4).

**2.** `kubectl rollout restart deployment/campus-backend` (Atelier 03, famille `rollout`) : les pods sont recréés un par un selon la stratégie `RollingUpdate`, ce qui produit des logs de démarrage frais.

Les pods `loki`, `prometheus` et `grafana` sont `Running` après 1 à 2 minutes ; `metrics-server` est dans `kube-system` (`kubectl get pods -n kube-system -l k8s-app=metrics-server`).

### Étape 2 — Mesurer la consommation

```bash
kubectl top nodes
kubectl top pods
```

**1.** CPU en **millicœurs** (`m`) : `1000m` = 1 cœur, donc `250m` = un quart de cœur. Mémoire en **Mi** (mébioctets).

**2.** Un pod **backend** (JVM Spring Boot) : typiquement 250 à 450 Mi, contre ~50 Mi pour PostgreSQL et 2 Mi pour un frontend Nginx. Relevé en préparation, une minute après le `rollout restart` : backend 240 Mi et 287 Mi, PostgreSQL 53 Mi, frontend 2 Mi. Juste après un démarrage, la colonne CPU d'un backend peut dépasser `1500m` (démarrage de la JVM) avant de redescendre à quelques millicœurs.

**3.** C'est la consommation **réelle**, mesurée par le kubelet (cAdvisor) et relayée par Metrics Server. Les valeurs déclarées (`requests` / `limits`) se lisent dans le manifest ou avec `kubectl describe pod` ; on compare les deux à l'Atelier 07 pour dimensionner les `requests`.

Si `error: Metrics API not available` ou `metrics not available yet` : Metrics Server démarre ou n'a pas encore fait sa première collecte ; attendre 1 minute.

### Étape 3 — Grafana

`http://<IP_PUBLIQUE_D_UN_WORKER>:30300`, identifiants `admin` / `admin2026`, menu **Explore**.

**1.** Requête Prometheus : **une courbe par pod** de `campus-dev`, soit 5 (1 `campus-postgres`, 2 `campus-backend`, 2 `campus-frontend`), plus brièvement les anciens pods backend remplacés à l'étape 1. Les valeurs sont en octets (Grafana affiche par exemple `350 MB`) et du même ordre que `kubectl top pods`, qui affiche la même métrique (`working_set`).

**2.** Oui : Loki affiche les logs des pods backend **supprimés** par le `rollout restart`, en particulier leurs lignes d'arrêt (`Commencing graceful shutdown`, `HikariPool-1 - Shutdown completed`). Les labels Loki de ces lignes sont `app`, `job` et `pod_template_hash` : l'ancien hash (celui du ReplicaSet remplacé) les distingue des nouveaux pods, et le nom exact du pod se lit dans la ligne elle-même (champ `kubernetes.pod_name`). `kubectl logs` en est incapable, car les logs disparaissent avec le pod ; Fluent Bit les a copiés dans Loki au fil de l'eau.

Points de vigilance :

* Loki vide : le backend n'a pas été redémarré **après** le démarrage de Fluent Bit, ou la période affichée est trop courte.
* IP publique périmée après un redémarrage de la session AWS : relever l'IP actuelle d'un worker dans la console AWS.
* Port filtré : `kubectl port-forward svc/grafana 3000:3000 -n monitoring`, puis `http://localhost:3000`.

**StackDriver** : l'ancien nom de la suite de supervision de Google Cloud, aujourd'hui **Google Cloud Observability** (Cloud Logging + Cloud Monitoring), activée par défaut sur GKE. Équivalents : **CloudWatch** (Container Insights) chez AWS, **Azure Monitor** (Container Insights) chez Azure.

### Optionnel — FreeLens

Le cluster apparaît dans **Catalog → Clusters** après import du `kubeconfig.yaml`. Les graphiques CPU / mémoire s'affichent grâce à Metrics Server (étape 1). Échec de connexion : le poste ne joint pas le port 6443 du control plane (réseau d'entreprise, ou IP du control plane changée dans le kubeconfig).

---

## Nettoyage (facultatif, en fin de journée)

La pile de supervision consomme plusieurs centaines de Mo de mémoire sur les workers. Pour la retirer (fichiers listés un par un : `monitoring/dashboard-kubernetes.json` n'est pas un objet Kubernetes, `kubectl delete -f monitoring/` échouerait dessus) :

```bash
kubectl delete -f monitoring/05-grafana.yaml -f monitoring/04-prometheus.yaml -f monitoring/03-fluentbit.yaml -f monitoring/02-loki.yaml -f monitoring/01-metrics-server.yaml -f monitoring/00-namespace.yaml
kubectl delete -f npd/npd.yaml
```

L'Atelier 07 n'en dépend pas.
