# Atelier 07 : Sécurité, Quotas de Ressources & Isolement Réseau (NetworkPolicy)

### Objectifs Pédagogiques :
* Protéger le cluster contre la surconsommation et l'effet « Noisy Neighbor » avec le couple **ResourceQuota** et **LimitRange**.
* Cloisonner le trafic réseau selon le modèle **Zéro-Trust** avec les **NetworkPolicies** : politique *Default Deny*, puis ouverture explicite des seuls flux légitimes (navigateur → frontend → backend → PostgreSQL).
* Durcir les conteneurs avec les **SecurityContext** (interdiction du compte root, pas d'élévation de privilèges).
* Auditer les privilèges et déléguer des accès avec les **ServiceAccounts** et le modèle **RBAC** (`kubectl auth can-i`).
* Identifier les verrous qui protègent l'**API Server** et **etcd** (exposition réseau, TLS mutuel, droits sur les clés, chiffrement des Secrets au repos).

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Compatibilité OS</strong></p>

Les commandes de cet atelier (`kubectl apply`, `kubectl describe resourcequota`, `kubectl auth can-i`, `kubectl exec`) sont **rigoureusement identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)**. Quand une commande diffère, les deux variantes sont fournies.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Environnement : le cluster 3 nœuds (1 control plane + 2 workers) de l'Atelier 01</strong></p>

Les NetworkPolicies exigent un plugin réseau qui les applique (Calico, installé à l'Atelier 01) : réalisez ce lab sur ce cluster, piloté au choix :

* **Option A (Recommandée - Confort DevOps Local) :** depuis votre machine locale, avec votre `kubectl` et votre `kubeconfig`. Dans **chaque nouveau terminal**, placé à la racine du dépôt, pointez d'abord `kubectl` vers le fichier `kubeconfig.yaml` récupéré à l'étape 17 de l'Atelier 01 :
    * Windows (PowerShell) : `$env:KUBECONFIG = "$PWD\labs\01-Installation-Cluster\terraform\kubeconfig.yaml"`
    * Linux / macOS (Bash) : `export KUBECONFIG=$PWD/labs/01-Installation-Cluster/terraform/kubeconfig.yaml`
    * Vérification : `kubectl get nodes` doit afficher les 3 nœuds à l'état `Ready`.
* **Option B (PC d'entreprise verrouillé) :** en SSH sur `k8s-control` : l'outillage et les manifests sont pré-installés dans `~/labs/`.

🛟 **Secours : Minikube sur votre poste** (session AWS indisponible). Les exercices 1, 3 et 4 fonctionnent à l'identique. L'exercice 2 exige un Minikube démarré avec Calico (`minikube start --cni=calico`) : sans lui, les NetworkPolicies sont acceptées mais **n'ont aucun effet**. L'exercice 5 n'a pas d'équivalent sur Minikube.

</div>

<div class="admonition note" markdown>
<p class="admonition-title"><strong>Namespace de travail : <code>campus-dev</code></strong></p>

Ce lab est **indépendant des autres** : son étape 0 crée `campus-dev` s'il n'existe pas encore, puis y installe ou met à jour tout ce dont il a besoin. Vous pouvez le réaliser sans avoir fait les labs précédents ; pour le recommencer à zéro, utilisez l'encadré « Repartir de zéro » de l'étape 0.

</div>

---

## Contexte Métier
En environnement partagé ou de production réglementée (secteur bancaire, assurance, santé), laisser un conteneur consommer toute la mémoire d'un nœud ou permettre à n'importe quel conteneur compromis d'atteindre le port 5432 de PostgreSQL constitue une faille critique. Cet atelier verrouille les ressources, cloisonne le réseau, durcit les conteneurs et contrôle les droits d'accès à l'API.

Tous les manifests de l'atelier sont **fournis** dans le dossier `labs/07-Sécurité Cluster/manifests/` : vous les lisez, les appliquez et observez leurs effets.

<div class="admonition tip" markdown>
<p class="admonition-title"><strong>Mode d'emploi</strong></p>

* Les encadrés rouges **« À vous de répondre »** contiennent les questions. Pour les commandes déjà vues dans les labs précédents, on vous demande la commande au lieu de vous la donner : cherchez avec `kubectl --help`, `kubectl <commande> --help` ou `kubectl explain`.
* Les commandes nouvelles sont données.
* Les encadrés **« Indice »** sont repliés : cliquez dessus seulement si vous bloquez.

</div>

---

## Étape 0 : Préparer l'environnement

Le dossier `starter/` du lab installe l'application complète dans l'état de fin de l'Atelier 06 :

| Fichier | Contenu |
| :--- | :--- |
| `01-config.yaml` | Le ConfigMap `campus-config` (paramètres non sensibles de l'API). |
| `02-postgres.yaml` | Le PVC `pvc-postgres`, la base PostgreSQL persistante et son Service `postgres`. |
| `03-backend.yaml` | L'API `campus-backend` (2 réplicas, ConfigMap, Secret et sondes de santé, **sans** `securityContext` ni ressources : ce lab les ajoute) et son Service `campus-backend`. |
| `04-frontend.yaml` | Le frontend et son Service NodePort `campus-frontend-svc` (port `30088`). |

Les identifiants de la base ne sont **pas** versionnés dans le starter : vous créez le Secret `campus-db-credentials` par une commande, comme à l'Atelier 05.

Créez le namespace `campus-dev` s'il n'existe pas encore, sélectionnez-le, puis appliquez le starter. Si vous sortez du lab précédent, vos objets sont conservés et simplement mis à jour. Depuis la racine du dépôt (Option A) ou depuis `~` sur `k8s-control` (Option B : mettez d'abord le dépôt à jour avec `git -C ~/formation pull`, puis remplacez `labs/` par `~/labs/`) :

```bash
kubectl create namespace campus-dev --dry-run=client -o yaml | kubectl apply -f -   # sans effet s'il existe déjà
kubectl config set-context --current --namespace=campus-dev
kubectl create secret generic campus-db-credentials --from-literal=POSTGRES_DB=campus --from-literal=POSTGRES_USER=campus --from-literal='POSTGRES_PASSWORD=CampusSecret2026!' --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "labs/07-Sécurité Cluster/starter/"
kubectl rollout status deployment/campus-postgres --timeout=180s
kubectl rollout status deployment/campus-backend --timeout=300s
```

<details class="warning" markdown>
<summary><strong>Environnement incohérent ou lab à recommencer ? Repartez de zéro</strong></summary>

Supprimez le namespace et tout son contenu, puis relancez les commandes ci-dessus :

```bash
kubectl delete namespace campus-dev   # ⚠️ supprime tout le contenu de campus-dev
```

*La suppression peut prendre jusqu'à une minute : `kubectl` rend la main quand elle est terminée.*

</details>

Le backend a maintenant des sondes de santé : `rollout status` attend que Spring Boot ait fini de démarrer (20 secondes à 2 minutes).

---

## Exercice 1 : Limiter les ressources avec LimitRange & ResourceQuota

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Un `ResourceQuota` plafonne la consommation totale d'un namespace. Dès qu'il plafonne le CPU ou la mémoire, **tout pod sans `requests` ni `limits` est refusé** : c'est pourquoi on installe toujours d'abord un `LimitRange`, qui fournit des valeurs par défaut.

</div>

### Étape 1 : Installer un LimitRange

Ouvrez `labs/07-Sécurité Cluster/manifests/01-limitrange.yaml` dans votre éditeur, puis appliquez-le.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande applique ce fichier ? Quelle commande affiche ensuite le détail du LimitRange `campus-default-limits` ?
2. Un conteneur créé **sans** section `resources` : quelles `requests` et quelles `limits` recevra-t-il ?
3. Les pods backend **déjà en cours d'exécution** ont-ils reçu ces valeurs ? Vérifiez avec `kubectl describe pod` sur l'un d'eux (sections `Requests` / `Limits`). Pourquoi ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : afficher le détail d'un objet</strong></summary>

La commande qui décrit un pod décrit aussi n'importe quel objet : `kubectl describe <type> <nom>`.

Un LimitRange agit au moment de l'**admission**, c'est-à-dire quand l'API Server accepte un nouveau pod. Il ne modifie jamais un pod existant.

</details>

### Étape 2 : Plafonner le namespace avec un ResourceQuota

Le fichier `manifests/02-resourcequota.yaml` plafonne le namespace à : 10 pods, 2 cœurs et 2 Gio de RAM en `requests`, 4 cœurs et 4 Gio de RAM en `limits`. Appliquez-le, puis affichez sa consommation :

```bash
kubectl describe resourcequota campus-compute-quota
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande applique ce fichier ?
2. Combien de pods sont déjà comptés (colonne `Used`) ? Combien de `requests.cpu` sont consommées, et pourquoi cette valeur ?
3. Sans le LimitRange de l'étape 1, que se passerait-il si vous lanciez maintenant un pod sans section `resources` ?

</div>

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Pourquoi 10 pods ?</strong></p>

Le namespace en compte déjà 5. Une mise à jour progressive avec `maxSurge: 1` a besoin d'une place pour le pod supplémentaire, et vos pods de test aussi. Un quota trop serré bloquerait les déploiements : dimensionnez-le toujours en tenant compte des *rolling updates*.

</div>

### Étape 3 : Tester le rejet

Le fichier `manifests/03-pod-trop-gros.yaml` décrit un pod qui demande **5 cœurs CPU**. Appliquez-le.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quel message renvoie l'API Server ? Quelles limites du quota sont dépassées ?
2. Le pod `pod-trop-gros` existe-t-il ? Quelle commande le vérifie ?
3. À quel moment le refus a-t-il lieu : avant ou après le placement sur un nœud ?

</div>

---

## Exercice 2 : Cloisonner le réseau avec les NetworkPolicies

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Par défaut, le réseau Kubernetes est **plat** : n'importe quel pod peut joindre n'importe quel autre. Le modèle Zéro-Trust consiste à **tout fermer**, puis à ouvrir uniquement les flux légitimes.

</div>

### Étape 4 : Constater que le réseau est ouvert

Un pod de test, sans aucun label, tente de joindre PostgreSQL avec l'outil `pg_isready` (l'image `postgres:16-alpine` est déjà présente sur les nœuds) :

```bash
kubectl run rogue-pod --image=postgres:16-alpine --rm -i --restart=Never -- pg_isready -h postgres -p 5432 -t 3
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Que répond `pg_isready` ?
2. Ce pod n'a rien à voir avec l'application. Quel risque cela représente-t-il ?

</div>

### Étape 5 : Tout fermer (*Default Deny*)

Le fichier `manifests/04-default-deny-ingress.yaml` refuse **tout** le trafic entrant vers **tous** les pods du namespace (`podSelector: {}`). Appliquez-le, relancez le pod de test de l'étape 4, puis rechargez le portail dans votre navigateur (`http://<IP_PUBLIQUE_WORKER>:30088`).

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande applique ce fichier ?
2. Que répond maintenant `pg_isready` ?
3. Le portail s'affiche-t-il encore ? Pourquoi ?
4. Les pods restent `Running` et `READY` : pourquoi les sondes de santé du kubelet ne sont-elles pas bloquées ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : NetworkPolicy et sondes</strong></summary>

Une NetworkPolicy `Ingress` vide (`podSelector: {}` sans règle `ingress`) bloque toutes les connexions entrantes. Le trafic du **nœud** qui héberge le pod, celui du `kubelet` qui exécute les sondes, reste toujours autorisé.

</details>

### Étape 6 : Ouvrir les trois flux légitimes

```mermaid
flowchart LR
    Web["Navigateur<br/>(NodePort 30088)"] -->|"TCP 8080 ✅"| FE["campus-frontend"]
    FE -->|"TCP 8080 ✅"| BE["campus-backend"]
    BE -->|"TCP 5432 ✅"| DB["campus-postgres"]
    Rogue["Pod non autorisé"] -.->|"❌ bloqué"| DB
    Rogue -.->|"❌ bloqué"| BE
```

Ouvrez `manifests/05-campus-networkpolicies.yaml` : il contient trois NetworkPolicies, une par flux. Appliquez-le, puis listez les NetworkPolicies du namespace.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelles commandes appliquent le fichier, puis listent les NetworkPolicies ? Combien en voyez-vous ?
2. Pour chacune des trois règles, indiquez : les pods **protégés** (`podSelector`), les sources **autorisées** (`from`) et le **port** ouvert.
3. La règle `allow-web-to-frontend` n'a pas de champ `from`. Que signifie cette absence ? Pourquoi est-elle nécessaire pour le NodePort ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : lire une NetworkPolicy</strong></summary>

* `spec.podSelector` : les pods **auxquels la règle s'applique** (la destination).
* `ingress[].from` : qui a le droit d'entrer. Absent = toutes les sources.
* `ingress[].ports` : sur quel port.

Les règles s'additionnent : un flux passe dès qu'une règle l'autorise. `kubectl describe networkpolicy` les résume en clair.

</details>

### Étape 7 : Tester l'intrusion et les flux légitimes

Relancez le pod de test de l'étape 4. Puis lancez un pod de test qui **porte le label du backend** :

```bash
kubectl run test-auth --image=postgres:16-alpine --labels='app=campus-backend' --rm -i --restart=Never -- pg_isready -h postgres -p 5432 -t 3
```

Rechargez enfin le portail dans votre navigateur et testez la chaîne complète à travers le frontend :

**Linux / macOS**

```bash
curl -s http://<IP_PUBLIQUE_WORKER>:30088/actuator/health
```

**Windows (PowerShell)**

```powershell
curl.exe -s http://<IP_PUBLIQUE_WORKER>:30088/actuator/health
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Que répond `pg_isready` pour `rogue-pod` ? Et pour `test-auth` ? Pourquoi cette différence ?
2. Le portail fonctionne-t-il de nouveau ? Que contient la réponse de `/actuator/health` ?
3. `test-auth` a obtenu l'accès simplement en **se déclarant** backend. Quelle faiblesse cela révèle-t-il ? Quel mécanisme (exercice 4) permet de la limiter ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : le portail reste inaccessible</strong></summary>

* Vérifiez les labels des pods : `kubectl get pods --show-labels`. Les règles reposent sur `app=campus-frontend`, `app=campus-backend` et `app=campus-postgres`.
* Listez les règles actives et leur cible : `kubectl describe networkpolicy`.
* Utilisez l'IP **publique** actuelle d'un worker : elle change à chaque redémarrage de la session AWS.

</details>

---

## Exercice 3 : Durcir les conteneurs avec un SecurityContext

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Selon le guide de durcissement Kubernetes de la NSA et de la CISA, un conteneur de production ne doit jamais tourner en `root` (UID 0) ni pouvoir élever ses privilèges. Le `securityContext` l'impose, sans modifier l'image.

</div>

### Étape 8 : Constater l'identité actuelle du backend

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelle commande exécute `id` à l'intérieur d'un conteneur du Deployment `campus-backend` ?
2. Sous quel utilisateur (UID) tourne le processus ? Quel risque cela représente-t-il si l'application est compromise ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : exécuter une commande dans un conteneur</strong></summary>

Vous avez utilisé `kubectl exec` à l'Atelier 02. Il accepte un nom de pod ou `deployment/<nom>` (il choisit alors l'un de ses pods). La commande à exécuter se place après `--`.

</details>

### Étape 9 : Appliquer le Deployment durci

Ouvrez `manifests/06-deployment-backend-secure.yaml`. C'est le backend du starter, complété de trois blocs repérés ①, ② et ③ dans les commentaires. Appliquez-le, puis suivez la mise à jour jusqu'à son terme.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelles commandes appliquent le fichier, puis suivent le *rolling update* jusqu'à son terme (revoyez l'Atelier 03) ?
2. Que garantissent `runAsNonRoot: true` et `runAsUser: 10001` (bloc ①) ?
3. Que garantissent `allowPrivilegeEscalation: false` et `capabilities.drop: [ALL]` (bloc ②) ?
4. Pourquoi le bloc ③ déclare-t-il des ressources explicites, alors que le LimitRange en fournit par défaut ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : et <code>readOnlyRootFilesystem: false</code> ?</strong></summary>

Un système de fichiers racine en lecture seule est le niveau de durcissement suivant. Spring Boot écrit des fichiers temporaires dans `/tmp` : il faudrait alors monter un volume `emptyDir` sur `/tmp`. À mettre en œuvre en production.

</details>

### Étape 10 : Vérifier le durcissement

Relancez la commande de l'étape 8, puis la commande `describe` du ResourceQuota de l'étape 2.

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Sous quel UID tourne maintenant le processus ? Le message `cannot find name for user ID 10001` est-il un problème ?
2. Dans le ResourceQuota, comment ont évolué les valeurs `Used` de `requests.cpu` et `requests.memory` ? D'où viennent-elles ?

</div>

---

## Exercice 4 : Contrôler l'accès à l'API avec RBAC

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

Chaque appel à l'API Kubernetes est fait par une **identité** (un utilisateur, ou un **ServiceAccount** pour un programme) et autorisé, ou non, par des règles **RBAC**. Un compte ne reçoit que les droits dont il a besoin.

</div>

### Étape 11 : Auditer les droits

`kubectl auth whoami` affiche votre identité ; `kubectl auth can-i` répond `yes` ou `no` à la question « ai-je le droit de… ? ». L'option `--as` pose la question pour une autre identité :

```bash
kubectl auth whoami
kubectl auth can-i create pods
kubectl auth can-i delete namespaces
kubectl auth can-i list secrets --as=system:serviceaccount:campus-dev:default
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Sous quel nom d'utilisateur et dans quel groupe travaillez-vous ? Pourquoi toutes vos réponses sont-elles `yes` ?
2. Que répond la dernière commande ? Qui est `system:serviceaccount:campus-dev:default`, et quels pods l'utilisent ?

</div>

### Étape 12 : Déléguer un accès en lecture seule

Une chaîne d'intégration continue doit seulement **lire** l'état des pods. Créez-lui un compte de service, un rôle en lecture seule et la liaison entre les deux :

```bash
kubectl create serviceaccount campus-ci-runner
kubectl create role pod-reader --verb=get,list,watch --resource=pods
kubectl create rolebinding read-pods --role=pod-reader --serviceaccount=campus-dev:campus-ci-runner
```

Vérifiez les droits accordés :

```bash
kubectl auth can-i list pods --as=system:serviceaccount:campus-dev:campus-ci-runner
kubectl auth can-i delete pods --as=system:serviceaccount:campus-dev:campus-ci-runner
kubectl auth can-i list pods -n kube-system --as=system:serviceaccount:campus-dev:campus-ci-runner
```

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Quelles sont les trois réponses ? Expliquez chacune.
2. Quel est le rôle de chacun des trois objets créés (ServiceAccount, Role, RoleBinding) ?
3. Un `Role` agit dans un seul namespace. Quel objet faudrait-il pour donner un droit sur tout le cluster ?

</div>

---

## Exercice 5 : Protéger l'API Server et etcd

<div class="admonition abstract" markdown>
<p class="admonition-title"><strong>Ce que vous allez comprendre</strong></p>

`etcd` contient **tout** l'état du cluster, Secrets compris. Quiconque le lit directement contourne le RBAC. Sa protection repose sur 4 verrous : le **réseau**, le **TLS mutuel**, les **droits sur les fichiers de clés** et le **chiffrement des données au repos**.

</div>

### Étape 13 : Tester l'exposition réseau depuis votre poste

Récupérez l'adresse de l'API Server inscrite dans votre kubeconfig, puis interrogez depuis **votre poste** l'API Server (port 6443) et etcd (port 2379) :

```bash
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
```

**Linux / macOS**

```bash
curl -sk https://<IP_PUBLIQUE_k8s-control>:6443/version
curl -sk https://<IP_PUBLIQUE_k8s-control>:6443/api/v1/namespaces/campus-dev/secrets
curl -sk --max-time 5 https://<IP_PUBLIQUE_k8s-control>:2379/version ; echo "Code retour : $?"
```

**Windows (PowerShell)**

```powershell
curl.exe -sk https://<IP_PUBLIQUE_k8s-control>:6443/version
curl.exe -sk https://<IP_PUBLIQUE_k8s-control>:6443/api/v1/namespaces/campus-dev/secrets
curl.exe -sk --max-time 5 https://<IP_PUBLIQUE_k8s-control>:2379/version ; echo "Code retour : $LASTEXITCODE"
```

*En Option B, lancez ces trois `curl` depuis votre poste (`curl` est présent sur Windows 10/11, macOS et Linux).*

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. L'API Server répond-il à `/version` sans authentification ? Et à la liste des Secrets ? Sous quelle identité votre requête a-t-elle été traitée ?
2. etcd répond-il ? Que signifie le code retour `28` de `curl` ?
3. Ouvrez `labs/01-Installation-Cluster/terraform/main.tf` : quels ports le Security Group ouvre-t-il à Internet (`0.0.0.0/0`) ? Comment le port `2379` est-il protégé ?

</div>

<details class="tip" markdown>
<summary><strong>Indice : et le port 6443 ouvert à <code>0.0.0.0/0</code> ?</strong></summary>

C'est un compromis de formation, pour que chacun utilise `kubectl` depuis son poste. En production, l'API Server n'est exposé qu'aux plages d'administration (VPN, bastion) ou via un endpoint privé. C'est le premier des « points à sécuriser » : **l'accès à l'API Kubernetes**.

</details>

### Étape 14 : Démonstration formateur : TLS mutuel, clés et chiffrement

Le formateur réalise cette démonstration sur `k8s-control`. Suivez-la, puis répondez aux questions.

<details class="example" markdown>
<summary><strong>Commandes de la démonstration (formateur, en SSH sur <code>k8s-control</code>)</strong></summary>

**a. TLS mutuel : etcd exige un certificat client**

```bash
sudo grep -E 'client-cert-auth|trusted-ca-file' /etc/kubernetes/manifests/etcd.yaml
curl -sk https://127.0.0.1:2379/version ; echo "Code retour : $?"
sudo grep -E 'etcd-(servers|cafile|certfile|keyfile)' /etc/kubernetes/manifests/kube-apiserver.yaml
```

*Sans certificat client, la négociation TLS échoue. Le seul client légitime d'etcd est l'API Server.*

**b. Droits sur les clés**

```bash
sudo ls -l /etc/kubernetes/pki/etcd/
```

*Les fichiers `.key` sont en mode `600` et appartiennent à `root`.*

**c. Un Secret lu directement dans etcd**

L'outil `etcdctl` n'est pas installé sur le nœud : on utilise celui du pod statique `etcd-k8s-control`, qui voit les clés du dossier `/etc/kubernetes/pki/etcd/` :

```bash
kubectl create secret generic test-etcd -n campus-dev --from-literal=motdepasse=SuperSecret2026
kubectl -n kube-system exec etcd-k8s-control -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/campus-dev/test-etcd | grep -a -o "motdepasse.*SuperSecret2026"
kubectl delete secret test-etcd -n campus-dev
```

*La valeur apparaît en clair (`motdepasseSuperSecret2026`) : par défaut, kubeadm ne chiffre pas les Secrets au repos.*

**d. La parade : chiffrer les Secrets au repos**

On fournit à l'API Server un fichier `EncryptionConfiguration` (option `--encryption-provider-config`) :

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources: ["secrets"]
  providers:
  - aescbc:
      keys:
      - name: cle-2026
        secret: <clé de 32 octets encodée en base64>
  - identity: {}
```

Les nouveaux Secrets sont alors chiffrés avant d'être écrits dans etcd ; les anciens doivent être réécrits (`kubectl get secrets -A -o json | kubectl replace -f -`). En production, on préfère un fournisseur **KMS** (AWS KMS, Google Cloud KMS, Azure Key Vault). Cette manipulation redémarre l'API Server : elle n'est pas réalisée par les stagiaires.

</details>

<div class="admonition question" markdown>
<p class="admonition-title"><strong>À vous de répondre</strong></p>

1. Pourquoi un client sans certificat ne peut-il pas dialoguer avec etcd ? Quel est le seul client légitime ?
2. Pour lire etcd, il faut les clés du dossier `/etc/kubernetes/pki/etcd/`. Qui peut les lire sur le nœud (partie b) ? Un accès SSH non privilégié suffit-il ? Et quel droit Kubernetes faut-il pour exécuter `etcdctl` dans le pod etcd ?
3. Le Secret apparaît en clair dans etcd. Pourquoi l'encodage base64 vu à l'Atelier 05 n'est-il **pas** un chiffrement ? Quelle est la parade ?

</div>

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Synthèse : les points à sécuriser</strong></p>

| Point à sécuriser | Mesure vue dans cet atelier |
| :--- | :--- |
| Accès à l'API Kubernetes | RBAC + ServiceAccounts dédiés (Ex. 4), exposition réseau du port 6443 (Ex. 5) |
| Limitation des ressources | `LimitRange` + `ResourceQuota` (Ex. 1) |
| Contrôle des accès réseau | `NetworkPolicy` *Default Deny* + flux autorisés (Ex. 2) |
| Durcissement des conteneurs | `securityContext` non-root (Ex. 3) |
| Restriction des accès à `etcd` | Isolement réseau, TLS mutuel, droits `root`, chiffrement au repos (Ex. 5) |

</div>

---

## Critères de Validation (Checklist)

- [ ] Le LimitRange `campus-default-limits` et le ResourceQuota `campus-compute-quota` sont actifs (`kubectl describe resourcequota campus-compute-quota`).
- [ ] Le pod `pod-trop-gros` a été refusé par l'API Server (`exceeded quota`).
- [ ] La politique `default-deny-ingress` est active et seuls les trois flux légitimes sont ouverts (`kubectl get networkpolicy` en liste 4).
- [ ] `rogue-pod` n'atteint plus PostgreSQL, et le portail fonctionne toujours de bout en bout.
- [ ] Le backend tourne sous l'UID `10001` (`kubectl exec deployment/campus-backend -- id`).
- [ ] Vous savez auditer des droits avec `kubectl auth can-i` et déléguer un accès en lecture seule (ServiceAccount + Role + RoleBinding).
- [ ] Vous savez expliquer pourquoi etcd n'est pas joignable depuis Internet, pourquoi il exige un certificat client, et comment chiffrer les Secrets au repos.
