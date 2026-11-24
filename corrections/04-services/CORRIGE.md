# Corrigé — Atelier 04 : Réseau, Services & Découverte DNS

> 🔒 **Confidentiel formateur.** À diffuser en fin d'atelier uniquement. Énoncé : `labs/04-Les Services/README.md`.
>
> Sorties relevées sur le cluster de formation (kubeadm v1.30, Calico, 1 control plane + 2 workers) : les noms de pods, adresses IP et `CLUSTER-IP` changent d'une session à l'autre.
>
> Ce corrigé suit la **version courte** publiée (3 exercices). Variante **version longue** de l'atelier 04 (4 exercices, énoncé + corrigé) : `VERSION-LONGUE.md` dans ce dossier.

---

## Étape 0 — Préparer l'environnement

Commandes données dans l'énoncé. Attendu : `deployment.apps/campus-postgres`, `service/postgres` et `deployment.apps/campus-backend` créés (ou `configured` / `unchanged` si l'on sort de l'Atelier 03), puis `deployment "campus-backend" successfully rolled out`.

Les stagiaires enchaînent directement sur l'exercice 1 : le démarrage de Spring Boot (20 à 40 secondes en général) se fait pendant ce temps. La vérification par les logs est placée au début de l'exercice 2, seul exercice qui a besoin que l'API réponde.

Erreur fréquente : oublier les guillemets autour du chemin `"labs/04-Les Services/starter/"`, qui contient une espace (`error: the path "labs/04-Les" does not exist`).

---

## Exercice 1 — Du pod instable au Service stable

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

`-o wide` ajoute les colonnes `IP` et `NODE`. Les adresses sont dans la plage `192.168.x.x` (plage des pods configurée pour Calico) ; chaque worker reçoit son propre sous-bloc. Les pods sont répartis sur les deux workers (anti-affinité du starter), jamais sur `k8s-control`.

### Étape 2 — Générer et créer le Service

Commande de génération donnée dans l'énoncé. Fichier généré :

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

**1.**

```bash
kubectl apply -f service-backend.yaml
```
Attendu : `service/campus-backend created`.

Erreur fréquente sous Windows PowerShell 5.1 : utiliser `>` au lieu de `| Out-File -Encoding utf8`. Le fichier est écrit en UTF-16 et `kubectl apply` échoue (`error converting YAML to JSON` ou caractères illisibles).

**2.** `kubectl expose deployment` a **recopié le sélecteur du Deployment** (`spec.selector.matchLabels`). Il désigne les pods qui recevront le trafic : tous ceux qui portent le label `app: campus-backend`, quel que soit leur nom.

**3.** Oui, le Service serait créé : l'API Server ne vérifie pas qu'un pod correspond au sélecteur. Mais il ne recevrait **aucun trafic** utile : aucun pod ne porte `app: campus-backnd`, sa liste d'Endpoints serait vide et les connexions échoueraient (`Connection refused` ou délai dépassé).

> **Pourquoi ?** L'API Server ne valide que la syntaxe du manifeste. Un Service peut légitimement exister avant ses pods, ou entre deux rollouts. Le contrôleur d'Endpoints compare ensuite en continu le sélecteur aux labels des pods. Sans correspondance, la liste reste vide : le DNS résout bien la ClusterIP, mais aucun pod n'est derrière.
>
> **Diagnostic :** `kubectl get endpoints campus-backend` affiche `<none>`. Comparez alors le sélecteur (`kubectl describe svc campus-backend`) aux labels des pods (`kubectl get pods --show-labels`). Corrigez le sélecteur et refaites `kubectl apply` : les Endpoints se remplissent aussitôt, sans redémarrer les pods.

### Étape 3 — Vérifier l'adresse du Service et ses Endpoints

```bash
kubectl get svc,endpoints campus-backend
```

```
NAME                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/campus-backend   ClusterIP   10.109.242.31   <none>        8080/TCP   0s

NAME                       ENDPOINTS                                                     AGE
endpoints/campus-backend   192.168.140.12:8080,192.168.230.17:8080,192.168.230.19:8080   1s
```

**1.** La `CLUSTER-IP` est dans la plage des Services (`10.96.0.0/12` par défaut avec kubeadm), distincte de celle des pods. Les Endpoints sont **exactement** les adresses IP des 3 pods backend, suivies du `targetPort` `8080`.

**2.** Non : la `CLUSTER-IP` est une adresse **virtuelle**, portée par aucun pod ni aucune interface. `kube-proxy` programme chaque nœud pour que le trafic envoyé à `CLUSTER-IP:8080` soit redirigé vers l'un des Endpoints. La liste des Endpoints, elle, ne contient que des adresses de pods réels.

### Étape 4 — Supprimer un pod et comparer

**1.**

```bash
kubectl delete pod campus-backend-c9c4d5fdf-4ld8z
```

Puis :

```bash
kubectl get pods -l app=campus-backend -o wide
kubectl get svc,endpoints campus-backend
```

```
NAME                             READY   STATUS    RESTARTS   AGE   IP               NODE
campus-backend-c9c4d5fdf-cg9zd   1/1     Running   0          3s    192.168.140.15   k8s-worker-2
campus-backend-c9c4d5fdf-sbgk9   1/1     Running   0          60s   192.168.140.12   k8s-worker-2
campus-backend-c9c4d5fdf-vzpgh   1/1     Running   0          60s   192.168.230.17   k8s-worker-1

NAME                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/campus-backend   ClusterIP   10.109.242.31   <none>        8080/TCP   20s

NAME                       ENDPOINTS                                                     AGE
endpoints/campus-backend   192.168.140.12:8080,192.168.140.15:8080,192.168.230.17:8080   20s
```

**2.** Non : le pod recréé par le **ReplicaSet** porte un **nouveau nom** (nouveau suffixe) et une **nouvelle adresse IP**, parfois sur un autre nœud.

**3.** La `CLUSTER-IP` (`10.109.242.31`) est inchangée : elle reste fixe pendant toute la vie du Service. Les Endpoints, eux, ont changé : l'adresse du pod supprimé (`192.168.230.19`) a disparu et celle du nouveau pod (`192.168.140.15`) est apparue. C'est le **contrôleur Endpoints** (dans le `kube-controller-manager`) qui met la liste à jour.

**4.** L'adresse d'un pod change à chaque recréation (mise à jour, panne, rollback, mise à l'échelle). Un client configuré avec une IP de pod tomberait en erreur à la première recréation et ne saurait pas répartir le trafic entre 3 pods. Le Service lui offre une adresse et un nom **stables** : la recréation du pod lui est invisible.

---

## Exercice 2 — Joindre un Service par son nom (DNS)

### Étape 1 — Vérifier que l'API a démarré

Commande donnée dans l'énoncé. Attendu : 3 lignes `Started CampusOpsApplication in … seconds`, une par pod. Le pod recréé à l'exercice 1 est en général le dernier à apparaître.

### Étape 2 — Appeler le backend par son nom

Commandes données dans l'énoncé. Réponse des deux `curl` :

```json
{"status":"UP","components":{"db":{"status":"UP","details":{"database":"PostgreSQL","validationQuery":"isValid()"}},"diskSpace":{"status":"UP",...},"livenessState":{"status":"UP"},"ping":{"status":"UP"},"readinessState":{"status":"UP"}},"groups":["liveness","readiness"]}
```

**1.** Oui, la même réponse `"status":"UP"` (et `"db":{"status":"UP"}` : l'API joint aussi sa base). Aucune adresse IP n'a été utilisée : le DNS du cluster (CoreDNS) traduit le nom en `CLUSTER-IP`, puis `kube-proxy` redirige vers un pod. Le nom court `campus-backend` est complété automatiquement avec le namespace du pod de test (`campus-dev`) ; le nom complet `campus-backend.campus-dev.svc.cluster.local` désigne le même Service.

**2.** `postgres` est le **nom du Service** de la base, dans le même namespace `campus-dev` (créé par le starter). Le backend n'utilise jamais l'adresse IP du pod PostgreSQL.

Erreurs fréquentes :
* `curl: (6) Could not resolve host` : faute de frappe dans le nom, ou pod de test créé dans un autre namespace (namespace courant non défini à l'étape 0).
* `curl: (7) Failed to connect … Connection refused` de temps en temps : un pod figure déjà dans les Endpoints mais Spring Boot n'a pas fini de démarrer (pas de sonde de disponibilité avant l'Atelier 07). Refaire l'étape 1 et attendre les 3 lignes.
* Message `warning: couldn't attach to pod/test-dns, falling back to streaming logs` : sans conséquence.

---

## Exercice 3 — Exposer le frontend hors du cluster (NodePort)

### Étape 1 — Déployer le frontend

Commandes données dans l'énoncé. Attendu : `deployment.apps/campus-frontend created`, puis 2 pods `Running`.

Erreur fréquente : déployer le frontend **avant** de créer le Service `campus-backend`. Les pods partent en `CrashLoopBackOff` (`host not found in upstream "campus-backend"`). Il suffit de créer le Service : les pods redémarrent seuls et finissent `Running`.

### Étape 2 — Créer le Service NodePort

**1.**

```bash
kubectl apply -f service-frontend.yaml
kubectl get services
```
```
NAME                  TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
campus-backend        ClusterIP   10.109.242.31   <none>        8080/TCP       31s
campus-frontend-svc   NodePort    10.101.5.60     <none>        80:30088/TCP   1s
postgres              ClusterIP   10.107.175.83   <none>        5432/TCP       79s
```

**2.** `80:30088/TCP` : le Service écoute sur le port `80` de sa `CLUSTER-IP` (`port`) et sur le port `30088` de **chaque nœud** (`nodePort`), en TCP. Le `targetPort` (8080) n'apparaît pas dans cette colonne. Oui, il a une `CLUSTER-IP` (`10.101.5.60`) : un Service `NodePort` **est** un `ClusterIP` auquel Kubernetes ajoute un port ouvert sur chaque nœud.

**3.** ① `targetPort: 8080` : le port sur lequel Nginx écoute dans le conteneur. ② `port: 80` : le port de la `CLUSTER-IP`, utilisé par les autres pods (`http://campus-frontend-svc/`). ③ `nodePort: 30088` : ouvert sur chaque nœud, joignable de l'extérieur, dans la plage **30000-32767**.

**4.** **`nodePort` (30088, sur le nœud) → `port` (80, sur le Service) → `targetPort` (8080, dans le pod).**

Erreur fréquente : `nodePort: 30080` → `provided port is already allocated` (port réservé à l'Ingress NGINX). Une valeur hors de la plage 30000-32767 est refusée (`provided port is not in the valid range`).

### Étape 3 — Accéder à l'application depuis votre navigateur

**1.** Oui, sur les deux adresses : le tableau de bord, les offres de stage, les départements et les candidatures s'affichent. Ces données viennent de **PostgreSQL** : la page appelle `/api/…`, que Nginx relaie au backend, qui interroge la base (données de démonstration insérées au démarrage du backend).

**2.** **navigateur → `nodePort` 30088 d'un nœud → Service `campus-frontend-svc` → pod frontend (Nginx) → Service `campus-backend` → pod API → Service `postgres` → pod PostgreSQL.**

**3.** Oui : `kube-proxy` ouvre le port `30088` sur **tous** les nœuds, y compris ceux qui n'hébergent aucun pod frontend, et même sur `k8s-control` (vérifié en préparation : réponse `200` sur `http://<IP_control_plane>:30088`). Le nœud qui reçoit la requête la transmet à l'un des pods du Service, où qu'il se trouve. Pour le vérifier : `kubectl get pods -l app=campus-frontend -o wide`.

Erreur fréquente (constatée en préparation) : utiliser les IP publiques notées lors d'une session précédente, ou celles affichées par un `terraform output` non rafraîchi. Les IP publiques des workers changent à chaque redémarrage de la session AWS : la page ne répond pas (délai dépassé). Relever les IP actuelles dans la console AWS.

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

Manifests produits par le stagiaire :

* `service-backend.yaml` (ci-dessus, étape 2 de l'exercice 1) ;
* `deployment-frontend.yaml` (généré, sans modification) ;
* `service-frontend.yaml` (donné dans l'énoncé).

Le starter de l'Atelier 05 repart de cet état : PostgreSQL de développement, backend en 3 réplicas, frontend en 2 réplicas, Services `campus-backend`, `postgres` et `campus-frontend-svc` (NodePort 30088).
