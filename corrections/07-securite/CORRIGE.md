# Corrigé — Atelier 07 : Sécurité, Quotas de Ressources & Isolement Réseau

> 🔒 **Confidentiel formateur.** À diffuser en fin d'atelier uniquement. Énoncé : `labs/07-Sécurité Cluster/README.md` (version optimisée, testée sur AWS le 23/11/2026). Manifests fournis : `labs/07-Sécurité Cluster/manifests/`. L'ancienne version longue (commandes à retrouver, chemins complets) est archivée dans `corrections/07-securite-longue/`.

> ⏱️ **Durée indicative :** 55 min (étape 0 : 5 min ; Ex. 1 : 10 min ; Ex. 2 : 20 min ; Ex. 3 (RBAC) : 10 min ; Ex. 4 (exposition API Server / etcd) : 5 min ; débrief : 5 min, mené au fil des exercices). Simplifié le 24/11/2026 (SecurityContext et démonstration formateur retirés) ; auparavant 1 h 15.
>
> 📅 **Ordre de passage : 05 → 07 → 06.** L'Atelier 07 se fait avant l'Atelier 06 : son starter part de l'état de fin de l'Atelier 05 (plus les sondes), et le starter 06 apporte son propre backend avec `securityContext` (un *rolling update* du backend a donc lieu à l'étape 0 de l'Atelier 06). L'étape 0 de l'Atelier 06 supprime NetworkPolicies, ResourceQuota et LimitRange.
>
> ✂️ **Ce qui a été raccourci, sans toucher aux objectifs :** chemins courts après `cd "labs/07-Sécurité Cluster"` (le chemin accentué était la première source d'erreurs de frappe) ; commandes `apply` / `describe` / `rollout status` données au lieu d'être demandées ; questions redondantes fusionnées (34 questions au lieu de 40, essentiellement les « Quelle commande… ? » sur des commandes déjà vues) ; lecture des manifests de l'exercice 1 pendant l'attente de l'étape 0.
>
> ⏱️ **Temps mesurés sur le cluster AWS le 23/11/2026** (enchaînement 05 → 07) : étape 0 en 45 s ; toutes les autres commandes répondent en quelques secondes.

> ✅ **Sorties vérifiées sur le cluster de formation** (kubeadm v1.30, Calico). Les compteurs `Used` du ResourceQuota (étape 2 de l'exercice 1) dépendent des pods présents au moment de la commande.

---

## Étape 0 — Préparer l'environnement

Commandes données dans l'énoncé. Attendu : `deployment "campus-postgres" successfully rolled out`, puis `deployment "campus-backend" successfully rolled out` (le backend a des sondes : `rollout status` attend la fin du démarrage de Spring Boot). 5 pods : 2 backend, 2 frontend, 1 base. Un ancien pod backend peut rester quelques secondes `Terminating` : le compteur `pods` du quota (exercice 1) peut alors afficher 6.

Erreur fréquente : oublier les guillemets autour de `"labs/07-Sécurité Cluster"` (espace et accent dans le chemin), dans l'`apply` du starter comme dans le `cd`. Toutes les commandes suivantes s'exécutent depuis le dossier du lab.

---

## Exercice 1 — Limiter les ressources avec LimitRange & ResourceQuota

### Étape 1 — Installer un LimitRange

```bash
kubectl apply -f manifests/01-limitrange.yaml
kubectl describe limitrange campus-default-limits
kubectl get pods -l app=campus-backend -o custom-columns=POD:.metadata.name,RESSOURCES:.spec.containers[0].resources
```

Sortie attendue (extrait) :
```
Type        Resource  Min  Max  Default Request  Default Limit  Max Limit/Request Ratio
----        --------  ---  ---  ---------------  -------------  -----------------------
Container   cpu       -    -    100m             500m           -
Container   memory    -    -    128Mi            512Mi          -
```

* Un conteneur sans `resources` reçoit `requests: cpu 100m, memory 128Mi` (`defaultRequest`) et `limits: cpu 500m, memory 512Mi` (`default`).
* Les pods déjà en cours d'exécution **n'ont pas** ces valeurs : la colonne `RESSOURCES` affiche `map[]` (aucune ressource). Le LimitRange agit à l'**admission** (création d'un pod par l'API Server) ; il ne modifie jamais un pod existant. Les valeurs s'appliqueront aux prochains pods recréés.

### Étape 2 — Plafonner le namespace avec un ResourceQuota

```bash
kubectl apply -f manifests/02-resourcequota.yaml
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
kubectl apply -f manifests/03-pod-trop-gros.yaml
kubectl get pod pod-trop-gros
```

Sortie attendue :
```
Error from server (Forbidden): error when creating "manifests/03-pod-trop-gros.yaml": pods "pod-trop-gros" is forbidden: exceeded quota: campus-compute-quota, requested: limits.cpu=5,requests.cpu=5, used: limits.cpu=0,requests.cpu=0, limited: limits.cpu=4,requests.cpu=2
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
kubectl apply -f manifests/04-default-deny-ingress.yaml
kubectl run rogue-pod --image=postgres:16-alpine --rm -i --restart=Never -- pg_isready -h postgres -p 5432 -t 3
```

* `pg_isready` répond `postgres:5432 - no response` (code retour 2 : `kubectl` peut afficher `pod campus-dev/rogue-pod terminated (Error)`, c'est attendu).
* Le portail ne s'affiche plus (délai d'attente dépassé) : plus **aucune** connexion n'entre dans **aucun** pod du namespace, y compris le trafic du NodePort vers le frontend.
* Les pods restent `Running` et `READY` : Calico autorise toujours le trafic du nœud hôte vers ses pods, donc les sondes HTTP du kubelet passent.

### Étape 3 — Ouvrir les trois flux légitimes

```bash
kubectl apply -f manifests/05-campus-networkpolicies.yaml
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
* Faiblesse : **n'importe qui pouvant créer un pod peut poser n'importe quel label**. Une NetworkPolicy fondée sur les labels n'est solide que si le droit de créer des pods est restreint : c'est le rôle du **RBAC** (exercice 3).

---

## Exercice 3 — Contrôler l'accès à l'API avec RBAC

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

## Exercice 4 — Protéger l'API Server et etcd

### Tester l'exposition réseau depuis votre poste

Sorties (vérifiées depuis un poste local) :

* `/version` → JSON `{"major": "1", "minor": "30", "gitVersion": "v1.30.14", …}` : l'API Server répond **sans authentification** à cette route publique (accès anonyme limité à quelques routes d'information).
* `/api/v1/namespaces/campus-dev/secrets` → `403 Forbidden` : `secrets is forbidden: User "system:anonymous" cannot list resource "secrets"…`. La requête sans certificat ni jeton est traitée sous l'identité **`system:anonymous`**, qui n'a aucun droit RBAC.
* Port 2379 → aucune réponse, `Code retour : 28` = **délai d'attente dépassé** (`curl` : operation timed out). Le pare-feu AWS rejette silencieusement le paquet.
* Pour info formateur (question retirée de l'énoncé le 24/11/2026) : le Security Group ouvre à `0.0.0.0/0` les ports **22** (SSH), **6443** (API Server) et **30000-32767** (NodePorts). Le port 2379 n'est couvert que par la règle `self = true` : seuls les membres du même Security Group (les nœuds du cluster) peuvent le joindre. De plus, etcd n'écoute que sur `127.0.0.1` et l'IP privée du nœud.

Synthèse à faire reformuler par le groupe : les points à sécuriser du programme (tableau de synthèse de l'énoncé). Le SecurityContext, le TLS mutuel d'etcd et le chiffrement des Secrets au repos ont été retirés de l'atelier (simplification du 24/11/2026) : à évoquer oralement si le groupe le demande.

---

## Nettoyage

Rien à faire avant l'Atelier 06 : son étape 0 supprime NetworkPolicies, ResourceQuota et LimitRange (sinon `test-api`, sans label, ne joindrait pas le backend, et le quota compterait les pods des incidents). Pour tout retirer à la main :
```bash
kubectl delete networkpolicy --all
kubectl delete resourcequota campus-compute-quota
kubectl delete limitrange campus-default-limits
kubectl delete rolebinding read-pods ; kubectl delete role pod-reader ; kubectl delete serviceaccount campus-ci-runner
```
