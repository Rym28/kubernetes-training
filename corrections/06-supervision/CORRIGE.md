# Corrigé — Atelier 06 : Exploitation, Observabilité & Reverse Debugging

> 🔒 **Confidentiel formateur.** À diffuser en fin d'atelier uniquement. Énoncé : `labs/06-Administration & Supervision/README.md` (version **simplifiée** du 24/11/2026 : 4 exercices + exercice 5 FreeLens optionnel). La version longue d'origine (14 étapes) et son corrigé sont archivés dans `corrections/06-supervision-longue/`.

Toutes les commandes s'exécutent depuis le dossier du lab (`cd "labs/06-Administration & Supervision"`), namespace courant `campus-dev`.

## Durée et optimisations (testées sur le cluster AWS le 23/11/2026)

| | Version longue (archive) | Version optimisée (en vigueur) |
| :--- | :--- | :--- |
| Durée indicative | ~1 h 45 | **~1 h 20** (gain ~25 min) |
| Pile de supervision | Installée à l'exercice 5 : 1 à 2 min d'attente des pods, puis 1 min pour Metrics Server | Lancée en fin d'étape 0 : elle démarre pendant les exercices 1 à 4 (pods `Running` en ~65 s, `kubectl top` disponible dès l'exercice 5) |
| Logs à retrouver dans Loki | `rollout restart` du backend (≈ 1 min de redémarrage, avec la limite CPU de 500m) | Logs de `crash-app` (incident A), supprimé à l'exercice 3 : même démonstration, sans redémarrage |
| Incidents A et B | Deux étapes successives : deux attentes de `CrashLoopBackOff` | Lancés ensemble, un seul `kubectl get pods … -w` : les deux en `CrashLoopBackOff` en ~45 s |
| Exercice 1 | 3 étapes (`logs -f`, `logs -l --prefix`, événements) | 2 étapes (les deux lectures de logs regroupées) |
| Exercice 2 | Origine de chaque variable (ConfigMap / Secret / manifest) | Question retirée : relève de l'Atelier 05, pas des objectifs de l'Atelier 06 |

Simplification du 24/11/2026 (énoncé en vigueur) : exercices 1 (logs, événements) et 2 (`exec`) fusionnés en un exercice 1 de 3 étapes, sans la question `--previous` (pratiquée à l'exercice 2) ni l'étape `wget` du frontend (Atelier 04) ; incident C (Service au sélecteur faux, Atelier 04) retiré ; encadré « Pod privilégié » et question `drain` retirés (le `drain` reste dans l'encadré info) ; une seule requête Loki (`{run="crash-app"}`) ; tableau des outils condensé. FreeLens devient l'exercice 5 optionnel (~10 min, 2 étapes), avec deux façons de charger le kubeconfig. Les exercices 3, 4, 5 deviennent 2, 3, 4. Gain estimé : ~15 min (durée indicative **~1 h 05** sans FreeLens).

Objectifs pédagogiques et outils manipulés inchangés. Seule la requête Loki de l'exercice 5 change : `{app="campus-frontend"}` après rechargement du portail, au lieu de `{app="campus-backend"}`, vide quand on sort de l'Atelier 07 (voir l'étape 3 de l'exercice 5).

Temps mesurés sur le cluster (commandes seules, hors lecture et réponses) : étape 0 = 75 s en partant de zéro (backend prêt en 53 s), 14 s en sortant de l'Atelier 07 (starter `unchanged`, test du 23/11/2026 enchaîné 05 → 07 → 06), incidents A + B = 45 s, déploiement NPD = 14 s, injection + `cordon` = 10 s.

---

## Étape 0 — Préparer l'environnement

Commandes données dans l'énoncé. Attendu :

* `secret/campus-db-credentials created` (ou `configured`), puis les objets du starter : `configmap/campus-config`, `persistentvolume/pv-postgres`, `persistentvolumeclaim/pvc-postgres`, les Deployments `campus-postgres`, `campus-backend` (2 réplicas), `campus-frontend` (2 réplicas) et les Services `postgres`, `campus-backend`, `campus-frontend-svc` (NodePort 30088).
* `rollout status` du backend rend la main quand les sondes sont vertes (≈ 1 min).
* La dernière commande crée le namespace `monitoring`, Metrics Server (dans `kube-system`), Loki, le DaemonSet Fluent Bit, Prometheus et Grafana. Le stagiaire n'attend pas : la pile démarre pendant les exercices 1 à 4.

Piège : `kubectl apply -f monitoring/` (dossier entier) échoue sur `monitoring/dashboard-kubernetes.json`, qui n'est pas un objet Kubernetes (`apiVersion not set, kind not set`) ; les autres fichiers sont tout de même appliqués. D'où la liste explicite des 6 fichiers.

Erreur fréquente : oublier le Secret. Les pods backend restent alors en `CreateContainerConfigError` (`secret "campus-db-credentials" not found`), visible avec `kubectl describe pod`.

---

## Exercice 1 — Lire les logs et les événements, entrer dans un conteneur

### Étape 1 — Lire les logs du backend

```bash
kubectl logs -f deployment/campus-backend --tail=20
kubectl logs -l app=campus-backend --tail=5 --prefix
```

**1.** La ligne `Started CampusOpsApplication in 52.9 seconds (process running for 57.6)` marque la fin du démarrage. La durée varie de 10 à 60 secondes selon la charge du nœud : avec la limite CPU de 500m posée à l'Atelier 07, compter plutôt 50 à 60 secondes (52,9 s et 53,8 s mesurées le 23/11/2026).

**2.** Première commande : **un seul** pod. `kubectl logs deployment/…` choisit l'un des pods du Deployment et l'annonce par `Found 2 pods, using pod/campus-backend-xxxx-yyyy`. Seconde commande : les **2** pods, grâce au sélecteur de labels, soit 10 lignes (5 par pod), chacune précédée de `[pod/campus-backend-…/campus-backend]`.

### Étape 2 — Lire la chronologie des événements

```bash
kubectl get events --sort-by=.metadata.creationTimestamp
```

**1.** Pour un pod : `Scheduled` (le Scheduler l'a placé sur un nœud) → `Pulling` / `Pulled` (image téléchargée, ou déjà présente) → `Created` → `Started` (le kubelet a lancé le conteneur). On voit aussi `ScalingReplicaSet` (Deployment) et `SuccessfulCreate` (ReplicaSet).

Question fréquente : des événements `Warning  Unhealthy … Startup probe failed: … connection refused` apparaissent pour les pods backend récents (constaté le 23/11/2026). C'est normal : la sonde de démarrage interroge l'API toutes les 5 s pendant que Spring Boot démarre (≈ 55 s avec la limite CPU de 500m) ; elle tolère 36 échecs avant de redémarrer le conteneur.

**2.** Non : les logs d'un pod sont stockés sur le nœud avec le conteneur et **disparaissent avec le pod**. Pour les conserver, il faut les centraliser hors du pod : agent de collecte sur chaque nœud (Fluent Bit) + stockage (Loki), vus à l'exercice 4. Les événements eux-mêmes ne sont conservés qu'une heure par défaut.

### Étape 3 — Vérifier la configuration reçue par le backend

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

**2.** `jdbc:postgresql://postgres:5432/campus` : l'API joint la base par le nom du Service `postgres`, sur le port 5432. Pour aller plus loin à l'oral (question retirée de l'énoncé optimisé) : l'URL est écrite dans le manifest du Deployment (`env.value`), `SPRING_PROFILES_ACTIVE` vient du ConfigMap `campus-config` (via `envFrom`), l'utilisateur et le mot de passe du Secret `campus-db-credentials` (via `secretKeyRef`).

**3.** Oui, en clair : un Secret est décodé quand il est injecté dans le conteneur. Toute personne autorisée à faire `kubectl exec` (verbe `create` sur la ressource `pods/exec`) lit donc les Secrets de l'application. L'Atelier 07, réalisé avant celui-ci, a montré comment restreindre ces droits avec le RBAC.

Erreurs fréquentes : `kubectl exec campus-backend -- …` (`pods "campus-backend" not found` : il faut le nom d'un pod ou `deployment/campus-backend`) ; oublier `--`.

---

## Exercice 2 — Dépanner avec méthode

### Étape 1 — Incidents A et B : `CrashLoopBackOff` et `OOMKilled`

```bash
kubectl run crash-app --image=busybox:1.36 -- sh -c "echo Demarrage; sleep 3; echo Erreur fatale; exit 42"
kubectl apply -f manifests/oom-victim.yaml
kubectl get pods crash-app oom-victim -w
```

Chronologie relevée sur le cluster AWS (23/11/2026) :

```text
t=7s   crash-app Running 1    oom-victim CrashLoopBackOff 1
t=24s  crash-app Running 2    oom-victim OOMKilled 2
t=41s  crash-app CrashLoopBackOff 2    oom-victim CrashLoopBackOff 2
```

**1.** `crash-app` : `ContainerCreating` → `Running` → `Error` → `Running` → `Error` → `CrashLoopBackOff`. `oom-victim` : `ContainerCreating` → `OOMKilled` → `CrashLoopBackOff` (relancé et retué à chaque tentative ; il alterne entre les deux statuts). `RESTARTS` augmente à chaque échec ; le délai entre deux tentatives double (10 s, 20 s, 40 s… plafonné à 5 minutes). `kubectl run` crée un pod avec `restartPolicy: Always` : le kubelet le relance sans fin. Seul `oom-victim` affiche un statut qui nomme sa cause (`OOMKilled`), et seulement par intermittence.

**2.** `kubectl describe pod <pod>`, section `Last State` :

```text
crash-app                        oom-victim
    Last State:  Terminated          Last State:  Terminated
      Reason:    Error                 Reason:    OOMKilled
      Exit Code: 42                    Exit Code: 137
```

Filtrer la sortie : `kubectl describe pod crash-app | grep -A 4 "Last State"` (Bash) ou `kubectl describe pod crash-app | Select-String "Last State" -Context 0,4` (PowerShell).

**3.** Un code différent de 0 signifie que le **processus** s'est arrêté sur une erreur. Pour `crash-app` (42), c'est l'application (ici le script) qui est en cause, pas Kubernetes. Pour `oom-victim`, 137 = 128 + signal 9 (`SIGKILL`) : c'est le **noyau Linux** du nœud (l'*OOM killer*, via le cgroup mémoire du conteneur) qui a tué le processus, car il dépassait `limits.memory: 50Mi`. Kubernetes ne fait que constater.

**4.** `kubectl logs crash-app --previous` → `Demarrage` puis `Erreur fatale`.

**5.** Augmenter `limits.memory` (au-dessus de la consommation réelle, mesurée avec `kubectl top`), ou réduire la consommation de l'application (ici, les 150 Mo demandés à `stress` ; pour une JVM, `-XX:MaxRAMPercentage`).

**6.** `kubectl delete pod crash-app oom-victim`.

Erreur fréquente : `kubectl logs crash-app` sans `--previous` affiche une sortie vide ou partielle (le conteneur courant vient de redémarrer).

À souligner : CrashLoopBackOff n'est pas une cause, c'est un symptôme : les deux pods l'affichent pour deux causes différentes. La cause se lit dans `Last State` : `Error` + `Exit Code` (application) ou `OOMKilled` (limite mémoire). C'est tout l'intérêt de les observer côte à côte.

---

## Exercice 3 — Détecter une panne de nœud

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
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/inject-kernel-err --timeout=60s
kubectl get events -A --field-selector reason=KernelDeadlock
kubectl delete pod inject-kernel-err
```

L'événement apparaît dans le namespace `default` (un nœud n'appartient à aucun namespace) : `Warning  KernelDeadlock  node/k8s-worker-1  kernel: BUG: unable to handle kernel NULL pointer dereference…`.

**1.** `kubectl describe node k8s-worker-1` → `KernelDeadlock   True   KernelDeadlock   kernel: BUG: unable to handle kernel NULL pointer dereference…`. NPD a reconnu dans `/dev/kmsg` un motif de sa configuration (`npd/npd.yaml`, règle `permanent` → condition `KernelDeadlock`).

**2.** Oui, `kubectl get nodes` affiche toujours `Ready` : la condition `Ready` vient du kubelet, qui fonctionne. Le Scheduler continuerait donc d'envoyer des pods sur un nœud dont le noyau est en panne. NPD signale ; il ne bloque rien.

`kubectl wait` répond `pod/inject-kernel-err condition met` en 2 à 4 secondes (testé le 23/11/2026, identique sous Bash et PowerShell) : sans lui, un stagiaire rapide pouvait supprimer le pod avant qu'il ait écrit dans `/dev/kmsg`. Si la condition est **déjà** `True` (injection rejouée), aucun nouvel événement n'apparaît : NPD ne signale que les changements d'état. Si la condition reste à `False` : attendre 10 à 20 secondes et relancer. Vérifier que le pod `inject-kernel-err` est bien passé en `Completed` (`kubectl get pod inject-kernel-err`) ; s'il est refusé, une Pod Security Admission bloque peut-être les pods privilégiés dans `campus-dev` (cas d'un cluster durci au-delà de l'Atelier 07).

### Étape 3 — Retirer le nœud du service

```bash
kubectl cordon k8s-worker-1
kubectl get nodes
kubectl uncordon k8s-worker-1
```

**1.** `Ready,SchedulingDisabled`. `cordon` pose la taint `node.kubernetes.io/unschedulable:NoSchedule` (et `spec.unschedulable: true`). Non : `cordon` ne touche pas aux pods existants (vérifiable avec `kubectl get pods -o wide`, colonne `NODE`). Il empêche seulement le Scheduler d'en placer de nouveaux.

À l'oral (question retirée de l'énoncé, `drain` présenté dans l'encadré info) : `kubectl drain k8s-worker-1 --ignore-daemonsets` : `cordon` + éviction des pods, recréés par leurs contrôleurs sur les autres nœuds. `--ignore-daemonsets` est nécessaire car les pods de DaemonSet (NPD, Fluent Bit, Calico, kube-proxy) ne peuvent pas être déplacés ; `--delete-emptydir-data` est requis si un pod utilise un `emptyDir`. Après la réparation : `kubectl uncordon`.

La condition `KernelDeadlock=True` reste affichée quelques minutes après l'`uncordon` : elle est indépendante du cordon, et NPD ne la remet à `False` qu'au redémarrage de son pod, **et seulement si le message est sorti de sa fenêtre d'analyse** (`"lookback": "5m"` dans `npd/npd.yaml`). Pour la remettre à zéro en fin de lab, **au moins 5 minutes après l'injection** : `kubectl delete pod -n kube-system -l app=node-problem-detector --field-selector spec.nodeName=k8s-worker-1`. Constaté en préparation : un redémarrage 2 ou 4 minutes après l'injection relit le message et remet la condition à `True` ; à 7 minutes, elle repasse à `False` en 5 secondes.

Piège à signaler : un `drain` déplacerait `campus-postgres` si elle tourne sur ce nœud. Son PV `pv-postgres` est un répertoire du disque de `k8s-worker-1` (`nodeAffinity`) : le pod resterait `Pending` jusqu'à l'`uncordon` (Atelier 05).

---

## Exercice 4 — Mesurer la consommation et centraliser les logs

### Étape 1 — Vérifier la pile de supervision

```bash
kubectl get pods -n monitoring -o wide
kubectl get pods -n kube-system -l k8s-app=metrics-server
```

**1.** Oui : la pile a été lancée à l'étape 0 et tourne depuis (pods `Running` en ~65 s lors du test). Les pods `fluent-bit` ont été créés par un **DaemonSet** (comme NPD) ; `loki`, `prometheus` et `grafana` par des Deployments.

**2.** **3 pods `fluent-bit`**, un par nœud y compris `k8s-control` : le DaemonSet Fluent Bit **tolère** la taint du control plane (bloc `tolerations` de `03-fluentbit.yaml`), pour collecter aussi les logs des composants système. NPD, lui, ne la tolère pas : 2 pods seulement (étape 1 de l'exercice 3).

Stagiaire qui a sauté la commande de l'étape 0 : il la lance maintenant (1 à 2 minutes d'attente) et rejoue `crash-app` pour avoir des logs dans Loki (indice de l'énoncé).

### Étape 2 — Mesurer la consommation

```bash
kubectl top nodes
kubectl top pods
```

**1.** CPU en **millicœurs** (`m`) : `1000m` = 1 cœur, donc `250m` = un quart de cœur. Mémoire en **Mi** (mébioctets).

**2.** Un pod **backend** (JVM Spring Boot) : typiquement 250 à 450 Mi, contre ~50 Mi pour PostgreSQL et 2 Mi pour un frontend Nginx. Relevé en préparation (23/11/2026, version optimisée) : backend 227 Mi et 222 Mi, PostgreSQL 53 Mi, frontend 2 Mi. Juste après un démarrage, la colonne CPU d'un backend peut dépasser `1500m` (démarrage de la JVM) avant de redescendre à quelques millicœurs.

**3.** C'est la consommation **réelle**, mesurée par le kubelet (cAdvisor) et relayée par Metrics Server. Les valeurs déclarées (`requests` / `limits`) se lisent dans le manifest ou avec `kubectl describe pod` ; comparez-les aux `requests` (150m / 256Mi) et `limits` (500m / 512Mi) déclarées par le backend à l'Atelier 07 pour juger leur dimensionnement.

Si `error: Metrics API not available` ou `metrics not available yet` : Metrics Server démarre ou n'a pas encore fait sa première collecte ; attendre 1 minute. Avec la pile lancée à l'étape 0, `kubectl top` répond du premier coup (constaté lors du test).

### Étape 3 — Grafana

`http://<IP_PUBLIQUE_D_UN_WORKER>:30300`, identifiants `admin` / `admin2026`, menu **Explore**.

**1.** Requête Prometheus : **une courbe par pod** de `campus-dev`, soit 5 (1 `campus-postgres`, 2 `campus-backend`, 2 `campus-frontend`), plus des courbes interrompues pour les pods supprimés pendant la période affichée (`crash-app`, `oom-victim`). Les valeurs sont en octets (Grafana affiche par exemple `230 MB`) et du même ordre que `kubectl top pods`, qui affiche la même métrique (`working_set`).

**2.** Oui : `{run="crash-app"}` affiche `Demarrage` et `Erreur fatale`, répétés à chaque redémarrage, alors que le pod a été supprimé à l'exercice 2. Le label `run=crash-app` a été posé par `kubectl run` ; Fluent Bit recopie les labels du pod en labels Loki (`Auto_Kubernetes_Labels on`), et le nom du pod, son namespace et son nœud se lisent dans la ligne elle-même (champ `kubernetes`). `kubectl logs crash-app` répond `pods "crash-app" not found` : les logs sont stockés sur le nœud avec le conteneur et disparaissent avec le pod ; Fluent Bit les a copiés dans Loki au fil de l'eau. Vérifié sur le cluster AWS le 23/11/2026 (labels Loki disponibles : `app`, `run`, `job`, `pod_template_hash`, `k8s_app`…).

Requête retirée de l'énoncé simplifié, utilisable à l'oral : `{app="campus-frontend"}` affiche une ligne Nginx par requête reçue (`"GET / HTTP/1.1" 200 …`), avec le nom du pod frontend dans le champ `kubernetes`. Vérifié le 23/11/2026. On n'interroge plus `{app="campus-backend"}` : en sortant de l'Atelier 07, le starter laisse le backend `unchanged`, et Spring Boot n'écrit rien après son démarrage. Ses logs, antérieurs à Fluent Bit, ne sont donc pas dans Loki (résultat vide constaté sur AWS).

Points de vigilance :

* Loki vide : Fluent Bit a été démarré **après** l'incident A (commande de l'étape 0 sautée), ou la période affichée est trop courte (passer à *Last 1 hour*).
* Pas de label `namespace` dans Loki avec cette configuration : sur un cluster partagé, `{app="campus-frontend"}` mélange les pods de tous les namespaces.
* IP publique périmée après un redémarrage de la session AWS : relever l'IP actuelle d'un worker dans la console AWS.
* Port filtré : `kubectl port-forward svc/grafana 3000:3000 -n monitoring`, puis `http://localhost:3000`.

**StackDriver** : l'ancien nom de la suite de supervision de Google Cloud, aujourd'hui **Google Cloud Observability** (Cloud Logging + Cloud Monitoring), activée par défaut sur GKE. Équivalents : **CloudWatch** (Container Insights) chez AWS, **Azure Monitor** (Container Insights) chez Azure.

---

## Exercice 5 (optionnel) — FreeLens

### Étape 1 — Connexion par le kubeconfig

*Kubeconfig Syncs* est plus robuste en Learner Lab : après un redémarrage de session, `get-kubeconfig` réécrit le fichier et FreeLens suit. *Add from kubeconfig* fige une copie, à recoller quand l'IP change. Échec : si `kubectl get nodes` échoue aussi avec ce fichier → kubeconfig périmé ; sinon → port 6443 filtré.

### Étape 2 — Retrouver les commandes du lab

**1.** Colonne `Restarts` qui augmente et statut `CrashLoopBackOff`. Le message `Erreur fatale` se lit dans **Logs**, case **Show previous terminated container** cochée (équivalent de `--previous`).

**2.** `k8s-worker-1   Ready,SchedulingDisabled` : FreeLens envoie les mêmes requêtes à l'API Server que `kubectl`, avec les droits du kubeconfig. Comme pour `exec`, les modifications faites dans l'interface (**Edit**) ne remplacent pas la correction du manifest.

---

## Nettoyage (facultatif, en fin de journée)

La pile de supervision consomme plusieurs centaines de Mo de mémoire sur les workers. Pour la retirer (fichiers listés un par un : `monitoring/dashboard-kubernetes.json` n'est pas un objet Kubernetes, `kubectl delete -f monitoring/` échouerait dessus) :

```bash
kubectl delete -f monitoring/05-grafana.yaml -f monitoring/04-prometheus.yaml -f monitoring/03-fluentbit.yaml -f monitoring/02-loki.yaml -f monitoring/01-metrics-server.yaml -f monitoring/00-namespace.yaml
kubectl delete -f npd/npd.yaml
```

L'Atelier 08 n'en dépend pas.
