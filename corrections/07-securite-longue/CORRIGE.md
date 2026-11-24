# Corrigé — Atelier 07 (version longue) : Sécurité, Quotas de Ressources & Isolement Réseau

> 🔒 **Confidentiel formateur.** À diffuser en fin d'atelier uniquement. Énoncé : `corrections/07-securite-longue/README.md` (archive de la version longue). La version en vigueur et son corrigé sont `labs/07-Sécurité Cluster/README.md` et `corrections/07-securite/CORRIGE.md`. Manifests fournis : `labs/07-Sécurité Cluster/manifests/`.

> ⏱️ **Durée indicative :** 1 h 30 à 1 h 45 (étape 0 : 10 min ; Ex. 1 : 15 min ; Ex. 2 : 25 min ; Ex. 3 : 15 min ; Ex. 4 : 10 min ; Ex. 5 : 15 min, démonstration comprise ; correction collective : 15 min).

> 📅 **Ordre de passage : 05 → 07 → 06**, comme la version en vigueur (même starter, mêmes manifests).

> ✅ **Sorties vérifiées sur le cluster de formation** (kubeadm v1.30, Calico). Les compteurs `Used` du ResourceQuota (étape 2 de l'exercice 1 et étape 3 de l'exercice 3) dépendent des pods présents au moment de la commande.

---

## Étape 0 — Préparer l'environnement

Commandes données dans l'énoncé. Attendu : `deployment "campus-postgres" successfully rolled out`, puis `deployment "campus-backend" successfully rolled out` (le backend a des sondes : `rollout status` attend la fin du démarrage de Spring Boot). 5 pods : 2 backend, 2 frontend, 1 base. Un ancien pod backend peut rester quelques secondes `Terminating` : le compteur `pods` du quota (exercice 1) peut alors afficher 6.

Erreur fréquente : oublier les guillemets autour de `"labs/07-Sécurité Cluster"` (espace et accent dans le chemin), (`"labs/07-Sécurité Cluster/starter/"`, `"labs/07-Sécurité Cluster/manifests/…"`). Les commandes ci-dessous s'exécutent depuis la racine du dépôt.

---

## Exercice 1 — Limiter les ressources avec LimitRange & ResourceQuota

### Étape 1 — Installer un LimitRange

```bash
kubectl apply -f "labs/07-Sécurité Cluster/manifests/01-limitrange.yaml"
kubectl describe limitrange campus-default-limits
kubectl describe pod -l app=campus-backend
```

Sortie attendue (extrait) :
```
Type        Resource  Min  Max  Default Request  Default Limit  Max Limit/Request Ratio
----        --------  ---  ---  ---------------  -------------  -----------------------
Container   cpu       -    -    100m             500m           -
Container   memory    -    -    128Mi            512Mi          -
```

* Un conteneur sans `resources` reçoit `requests: cpu 100m, memory 128Mi` (`defaultRequest`) et `limits: cpu 500m, memory 512Mi` (`default`).
* Les pods déjà en cours d'exécution **n'ont pas** ces valeurs : `kubectl describe pod` sur un pod backend ne montre ni `Requests` ni `Limits`. Le LimitRange agit à l'**admission** (création d'un pod par l'API Server) ; il ne modifie jamais un pod existant. Les valeurs s'appliqueront aux prochains pods recréés.

### Étape 2 — Plafonner le namespace avec un ResourceQuota

```bash
kubectl apply -f "labs/07-Sécurité Cluster/manifests/02-resourcequota.yaml"
kubectl describe resourcequota campus-compute-quota
```

Sortie attendue (vérifiée sur le cluster) :
```
Resource         Used  Hard
--------         ----  ----
limits.cpu       0     4
limits.memory    0     4Gi
pods             5     10
requests.cpu     0     2
requests.memory  0     2Gi
```

* `pods` : **5** déjà comptés (2 backend, 2 frontend, 1 base).
* `requests.cpu` à **0** : les pods existants ont été créés avant le LimitRange et ne déclarent aucune ressource ; ils comptent pour 0 dans le quota.
* Sans LimitRange, un nouveau pod sans `resources` serait **refusé** : `failed quota: campus-compute-quota: must specify limits.cpu for: …; limits.memory …; requests.cpu …; requests.memory …`. Dès qu'un quota porte sur le CPU ou la mémoire, chaque nouveau pod doit déclarer ces valeurs. Conséquence piège : même un `kubectl run` de test ou un redémarrage de pod échouerait.

### Étape 3 — Tester le rejet

```bash
kubectl apply -f "labs/07-Sécurité Cluster/manifests/03-pod-trop-gros.yaml"
kubectl get pod pod-trop-gros
```

Sortie attendue :
```
Error from server (Forbidden): error when creating "labs/07-Sécurité Cluster/manifests/03-pod-trop-gros.yaml": pods "pod-trop-gros" is forbidden: exceeded quota: campus-compute-quota, requested: limits.cpu=5,requests.cpu=5, used: limits.cpu=0,requests.cpu=0, limited: limits.cpu=4,requests.cpu=2
Error from server (NotFound): pods "pod-trop-gros" not found
```

* Les deux plafonds CPU sont dépassés : `requests.cpu` (5 > 2) et `limits.cpu` (5 > 4).
* Le pod **n'existe pas** : il n'a jamais été enregistré.
* Le refus a lieu **avant** tout placement : c'est le contrôleur d'admission `ResourceQuota` de l'API Server qui rejette la requête. Le Scheduler n'est jamais sollicité.

---

## Exercice 2 — Cloisonner le réseau avec les NetworkPolicies

### Étape 1 — Constater que le réseau est ouvert

Commande donnée. Sortie : `postgres:5432 - accepting connections`, puis `pod "rogue-pod" deleted`.

* N'importe quel pod du cluster, même sans rapport avec l'application, atteint la base.
* Risque : un conteneur compromis (faille web, image piégée) peut attaquer PostgreSQL directement (force brute, exploitation d'une faille du serveur), sans passer par l'API.

Note : grâce au LimitRange, ce pod sans `resources` est accepté malgré le quota.

### Étape 2 — Tout fermer (*Default Deny*)

```bash
kubectl apply -f "labs/07-Sécurité Cluster/manifests/04-default-deny-ingress.yaml"
kubectl run rogue-pod --image=postgres:16-alpine --rm -i --restart=Never -- pg_isready -h postgres -p 5432 -t 3
```

* `pg_isready` répond `postgres:5432 - no response` (code retour 2 : `kubectl` peut afficher `pod campus-dev/rogue-pod terminated (Error)`, c'est attendu).
* Le portail ne s'affiche plus (délai d'attente dépassé) : plus **aucune** connexion n'entre dans **aucun** pod du namespace, y compris le trafic du NodePort vers le frontend.
* Les pods restent `Running` et `READY` : Calico autorise toujours le trafic du nœud hôte vers ses pods, donc les sondes HTTP du kubelet passent.

### Étape 3 — Ouvrir les trois flux légitimes

```bash
kubectl apply -f "labs/07-Sécurité Cluster/manifests/05-campus-networkpolicies.yaml"
kubectl get networkpolicy
kubectl describe networkpolicy
```

Sortie attendue : 4 NetworkPolicies (`default-deny-ingress`, `allow-web-to-frontend`, `allow-frontend-to-backend`, `allow-only-backend-to-postgres`). La colonne `POD-SELECTOR` affiche `<none>` pour la première (tous les pods).

| Règle | Pods protégés (`podSelector`) | Sources autorisées (`from`) | Port |
| :--- | :--- | :--- | :--- |
| `allow-web-to-frontend` | `app=campus-frontend` | toutes (pas de `from`) | TCP 8080 |
| `allow-frontend-to-backend` | `app=campus-backend` | pods `app=campus-frontend` du namespace | TCP 8080 |
| `allow-only-backend-to-postgres` | `app=campus-postgres` | pods `app=campus-backend` du namespace | TCP 5432 |

* Absence de `from` = **toutes les sources**, mais seulement sur le port indiqué. Indispensable pour le NodePort : le trafic du navigateur arrive par n'importe quel nœud, avec une adresse source réécrite (SNAT) variable ; on ne peut pas le désigner par un sélecteur de pods.

Erreur fréquente : croire que le `podSelector` désigne la **source**. Il désigne la **destination** protégée.

### Étape 4 — Tester l'intrusion et les flux légitimes

```bash
kubectl run rogue-pod --image=postgres:16-alpine --rm -i --restart=Never -- pg_isready -h postgres -p 5432 -t 3
```

* `rogue-pod` : `postgres:5432 - no response`. Aucune règle n'autorise un pod sans label `app=campus-backend` à joindre la base.
* `test-auth` : `postgres:5432 - accepting connections`. Il porte `app=campus-backend` : la règle `allow-only-backend-to-postgres` le laisse passer.
* Le portail fonctionne de nouveau, données comprises. `/actuator/health` renvoie `{"status":"UP","components":{"db":{"status":"UP",…}…}}` : la chaîne navigateur → frontend → backend → PostgreSQL est entièrement autorisée.
* Faiblesse : **n'importe qui pouvant créer un pod peut poser n'importe quel label**. Une NetworkPolicy fondée sur les labels n'est solide que si le droit de créer des pods est restreint : c'est le rôle du **RBAC** (exercice 4).

---

## Exercice 3 — Durcir les conteneurs avec un SecurityContext

### Étape 1 — Constater l'identité actuelle du backend

```bash
kubectl exec deployment/campus-backend -- id
```

Sortie (vérifiée sur le cluster) : `uid=0(root) gid=0(root) groups=0(root)`.

* Le processus Java tourne en **root**. Si l'application est compromise, l'attaquant est root dans le conteneur : il peut modifier les fichiers de l'image, installer des outils et, en cas de faille du runtime ou de volume `hostPath` mal configuré, tenter de s'échapper vers le nœud.

### Étape 2 — Appliquer le Deployment durci

```bash
kubectl apply -f "labs/07-Sécurité Cluster/manifests/06-deployment-backend-secure.yaml"
kubectl rollout status deployment/campus-backend --timeout=300s
```

* Bloc ① : `runAsUser: 10001` force l'UID du processus ; `runAsNonRoot: true` fait refuser par le kubelet tout conteneur qui tournerait malgré tout en UID 0 (`CreateContainerConfigError: container has runAsNonRoot and image will run as root`).
* Bloc ② : `allowPrivilegeEscalation: false` interdit à un processus de gagner plus de privilèges que son parent (binaires `setuid` comme `sudo`) ; `capabilities.drop: [ALL]` retire toutes les capacités Linux (`NET_RAW`, `CHOWN`, `SETUID`…), même celles accordées par défaut.
* Bloc ③ : le LimitRange fournit des valeurs génériques (100m / 512Mi). Le backend Spring Boot a des besoins propres : on les déclare explicitement pour un placement correct (`requests`) et une protection adaptée (`limits`). Bonne pratique : ressources explicites sur toute application de production.

Le rolling update crée temporairement un 3e pod backend (`maxSurge: 1`) : il entre dans le quota (6 pods sur 10).

Erreur fréquente : passer `readOnlyRootFilesystem: true` sans volume `emptyDir` sur `/tmp` → Spring Boot échoue au démarrage (Tomcat ne peut pas créer son répertoire de travail).

### Étape 3 — Vérifier le durcissement

```bash
kubectl exec deployment/campus-backend -- id
kubectl describe resourcequota campus-compute-quota
```

* `uid=10001(10001) gid=10001(10001) groups=10001(10001)` (précédé de `id: cannot find name for user ID 10001` et `… group ID 10001`). Ce message est **normal** : l'UID n'est pas déclaré dans `/etc/passwd` de l'image, ce qui n'empêche pas le processus de tourner.
* Quota (vérifié sur le cluster) : `requests.cpu` passe à **300m** et `requests.memory` à **512Mi** (2 pods × 150m / 256Mi) ; `limits.cpu` à **1**, `limits.memory` à **1Gi** (2 × 500m / 512Mi). Seuls les nouveaux pods backend déclarent des ressources ; frontend et base, créés avant le LimitRange, comptent toujours pour 0.

---

## Exercice 4 — Contrôler l'accès à l'API avec RBAC

### Étape 1 — Auditer les droits

Commandes données. Sortie (vérifiée sur le cluster) :
```
ATTRIBUTE   VALUE
Username    kubernetes-admin
Groups      [kubeadm:cluster-admins system:authenticated]
yes
yes
no
```

* Vous êtes `kubernetes-admin`, membre du groupe `kubeadm:cluster-admins`, lié par kubeadm au ClusterRole `cluster-admin` : tous les droits sur tout le cluster, d'où les `yes`. Le kubeconfig récupéré à l'Atelier 01 est donc un **secret critique**.
* `kubectl auth can-i delete namespaces` affiche aussi `Warning: resource 'namespaces' is not namespace scoped` : le namespace courant `campus-dev` est ignoré pour une ressource de niveau cluster. Sans conséquence.
* `system:serviceaccount:campus-dev:default` : le compte de service créé automatiquement dans chaque namespace. Tous les pods qui ne précisent pas `serviceAccountName` l'utilisent (ici : tous les pods de l'application). Réponse `no` : il n'a aucun droit RBAC, donc un pod compromis ne peut pas lire les Secrets via l'API.

### Étape 2 — Déléguer un accès en lecture seule

Commandes données. Réponses : `yes`, `no`, `no`.

* `list pods` → `yes` : accordé par le Role `pod-reader` (verbes `get`, `list`, `watch` sur `pods`) via le RoleBinding `read-pods`.
* `delete pods` → `no` : le verbe `delete` n'est pas dans le Role. Le RBAC est **additif** : tout ce qui n'est pas explicitement accordé est refusé.
* `list pods -n kube-system` → `no` : un Role et un RoleBinding n'agissent que dans **leur** namespace (`campus-dev`).
* Rôles des objets : le **ServiceAccount** est l'identité (pour un programme) ; le **Role** est la liste des droits (verbes × ressources) dans un namespace ; le **RoleBinding** attribue ce Role à une identité.
* Pour un droit sur tout le cluster : un **ClusterRole** et un **ClusterRoleBinding**.

---

## Exercice 5 — Protéger l'API Server et etcd

### Étape 1 — Tester l'exposition réseau depuis votre poste

Sorties (vérifiées depuis un poste local) :

* `/version` → JSON `{"major": "1", "minor": "30", "gitVersion": "v1.30.14", …}` : l'API Server répond **sans authentification** à cette route publique (accès anonyme limité à quelques routes d'information).
* `/api/v1/namespaces/campus-dev/secrets` → `403 Forbidden` : `secrets is forbidden: User "system:anonymous" cannot list resource "secrets"…`. La requête sans certificat ni jeton est traitée sous l'identité **`system:anonymous`**, qui n'a aucun droit RBAC.
* Port 2379 → aucune réponse, `Code retour : 28` = **délai d'attente dépassé** (`curl` : operation timed out). Le pare-feu AWS rejette silencieusement le paquet.
* `main.tf` : le Security Group ouvre à `0.0.0.0/0` les ports **22** (SSH), **6443** (API Server) et **30000-32767** (NodePorts). Le port 2379 n'est couvert que par la règle `self = true` : seuls les membres du même Security Group (les nœuds du cluster) peuvent le joindre. De plus, etcd n'écoute que sur `127.0.0.1` et l'IP privée du nœud.

### Étape 2 — Démonstration formateur

Déroulé conseillé (5 min, en SSH sur `k8s-control`, en projetant le terminal) : commandes a à d de l'énoncé. Penser à supprimer `test-etcd` à la fin. Toutes les commandes ont été jouées en préparation.

* TLS mutuel : `etcd.yaml` contient `--client-cert-auth=true` et `--trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt`. Le `curl -sk` échoue pendant la négociation TLS (**code retour 56**, relevé en préparation ; 35 possible avec une autre version de `curl`) : etcd exige un certificat client signé par **sa propre** autorité. Le seul client légitime est l'**API Server** (`--etcd-servers=https://127.0.0.1:2379`, `--etcd-cafile`, `--etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt`, `--etcd-keyfile` dans `kube-apiserver.yaml`).
* Droits : les 4 fichiers `.key` de `/etc/kubernetes/pki/etcd/` sont en mode `600` (`-rw-------`), propriétaire `root` ; les `.crt` sont en `644`. Sur le nœud, seul `root` (via `sudo`) peut lire les clés : un accès SSH **non privilégié** ne suffit pas. Par l'API, exécuter `etcdctl` dans le pod etcd exige le droit `create` sur `pods/exec` dans `kube-system`, c'est-à-dire en pratique des droits d'administrateur du cluster : encore une raison de protéger le kubeconfig `cluster-admin`.
* Si le formateur lance la commande c depuis **Git Bash** sur son poste plutôt qu'en SSH, préfixer par `MSYS_NO_PATHCONV=1` : sinon Git Bash convertit `/etc/kubernetes/...` en `C:/Program Files/Git/etc/...` (constaté le 23/11/2026).
* `etcdctl` n'est **pas installé** sur `k8s-control` (constaté en préparation) : la démonstration l'exécute dans le pod statique `etcd-k8s-control`, qui embarque l'outil et monte `/etc/kubernetes/pki/etcd/`. Un message `websocket.go … Unknown stream id 1, discarding message` peut s'afficher : sans conséquence.
* Chiffrement : la sortie `motdepasseSuperSecret2026` montre la valeur en clair dans etcd. Base64 n'est qu'un **encodage** réversible par n'importe qui (`base64 -d`), sans clé : ce n'est pas un chiffrement. Parade : `EncryptionConfiguration` (`aescbc`, `aesgcm` ou `secretbox`) passée à l'API Server via `--encryption-provider-config`, ou mieux un fournisseur **KMS** externe ; puis réécrire les Secrets existants.

Synthèse à faire reformuler par le groupe : les 4 verrous d'etcd (réseau, TLS mutuel, droits `root` sur les clés, chiffrement au repos) et les 5 points à sécuriser du programme (tableau de synthèse de l'énoncé).

---

## Nettoyage

Rien à faire avant l'Atelier 06 : son étape 0 supprime NetworkPolicies, ResourceQuota et LimitRange (sinon `test-api`, sans label, ne joindrait pas le backend, et le quota compterait les pods des incidents). Le backend durci est conservé. Pour tout retirer à la main :
```bash
kubectl delete networkpolicy --all
kubectl delete resourcequota campus-compute-quota
kubectl delete limitrange campus-default-limits
kubectl delete rolebinding read-pods ; kubectl delete role pod-reader ; kubectl delete serviceaccount campus-ci-runner
```
