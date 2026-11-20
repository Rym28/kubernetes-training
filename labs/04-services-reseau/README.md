# Lab 04 : Réseau, Services & Découverte DNS

### Objectifs Pédagogiques :
* Observer le réseau des Pods (une IP par pod, attribuée par le CNI) et constater que ces adresses changent à chaque recréation, d'où le besoin d'un **Service**.
* Créer de façon déclarative le Service **ClusterIP** `campus-backend` et vérifier qu'il sélectionne ses pods par leur label.
* Joindre un Service par son nom DNS court et par son nom complet `<service>.<namespace>.svc.cluster.local` (**CoreDNS**).
* Exposer le frontend hors du cluster avec un Service **NodePort** et distinguer `targetPort`, `port` et `nodePort`.
* *(Optionnel)* Observer la répartition de charge d'un Service entre plusieurs réplicas.

> 📌 **Note Compatibilité OS :**  
> Les commandes de cet atelier (`kubectl expose`, `kubectl get svc`, `kubectl run`) sont **rigoureusement identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)**. Seul le filtrage des logs de l'étape 16 diffère (`grep` sous Linux/macOS, `Select-String` sous PowerShell) : les deux variantes sont fournies.
>
> 🖥️ **Environnement : le cluster 3 nœuds (1 control plane + 2 workers) du Lab 00.** Ce lab exploite le fait qu'un NodePort est ouvert sur **chaque** nœud : réalisez-le sur ce cluster, piloté au choix :
> * **Option A (Recommandée - Confort DevOps Local) :** depuis votre machine locale, avec votre `kubectl` et votre `kubeconfig`.  
> * **Option B (PC d'entreprise verrouillé) :** en SSH sur `k8s-control` : l'outillage et les manifests sont pré-installés dans `~/labs/`.
>
> 🛟 **Secours : Minikube sur votre poste** (session AWS indisponible), piloté forcément depuis votre poste comme en Option A. Tout fonctionne à l'identique, sauf l'accès navigateur des étapes 12 et 13, pour lequel un encadré dédié est fourni.
>
> 🗂️ **Namespace de travail : `campus-dev`.** Ce lab est **indépendant des autres** : son étape 0 recrée `campus-dev` à neuf et y installe tout ce dont il a besoin. Vous pouvez le réaliser sans avoir fait les labs précédents, ou le recommencer à tout moment.

---

## Contexte Métier
Dans une architecture Kubernetes, les pods naissent, meurent et changent d'adresse IP à chaque mise à jour, incident ou redémarrage. Si le frontend contactait le backend par l'adresse IP d'un pod, la communication casserait dès la première mise à jour. Nous mettons en place des **Services** : une adresse IP virtuelle stable, un nom DNS pérenne et une répartition automatique du trafic entre les pods.

---

## Étape 0 : Préparer l'environnement

Le dossier `starter/` du lab installe l'état de départ : la base PostgreSQL de développement (avec son Service `postgres`) et l'API `campus-backend` en 3 réplicas, **sans** Service : c'est vous qui allez le créer.

Repartez d'un namespace `campus-dev` vide, puis appliquez le starter. Depuis la racine du dépôt (Option A) ou depuis `~` sur `k8s-control` (Option B : mettez d'abord le dépôt à jour avec `git -C ~/formation pull`, puis remplacez `labs/` par `~/labs/`) :

```bash
kubectl delete namespace campus-dev --ignore-not-found   # ⚠️ supprime tout le contenu de campus-dev
kubectl create namespace campus-dev
kubectl config set-context --current --namespace=campus-dev
kubectl apply -f labs/04-services-reseau/starter/
kubectl rollout status deployment/campus-backend --timeout=300s
```

*La suppression du namespace peut prendre jusqu'à une minute.* L'API n'a pas de sonde de santé : `rollout status` rend la main dès que les conteneurs tournent, avant que Spring Boot ait fini de démarrer (20 secondes à 2 minutes). Vérifiez que chaque pod backend a bien démarré :

```bash
# Linux / macOS
kubectl logs -l app=campus-backend --prefix --tail=-1 | grep "Started CampusOpsApplication"
```
```powershell
# Windows (PowerShell)
kubectl logs -l app=campus-backend --prefix --tail=-1 | Select-String "Started CampusOpsApplication"
```

*Relancez la commande jusqu'à obtenir 3 lignes, une par pod backend. Il est normal qu'un pod backend redémarre une fois au premier lancement : les pods créent en même temps les tables de la base neuve, et l'un d'eux échoue (`relation ... already exists`) avant de repartir.*

---

1. **Repérer les adresses IP des pods backend.** Listez vos pods backend avec leur adresse IP et notez-les :
   ```bash
   kubectl get pods -l app=campus-backend -o wide
   ```
   *Chaque pod reçoit sa propre adresse IP à sa création (plage `192.168.x.x`), attribuée par le plugin réseau (**CNI**) : Calico sur votre cluster. La colonne `NODE` montre que les pods sont répartis sur les deux workers : ils se joignent pourtant directement, d'un nœud à l'autre, sans traduction d'adresse (NAT).*

2. **Supprimer un pod backend** (remplacez `<nom-du-pod>` par un nom de la liste) :
   ```bash
   kubectl delete pod <nom-du-pod>
   ```

3. **Constater le changement d'adresse.** Relancez la commande de l'étape 1 :
   ```bash
   kubectl get pods -l app=campus-backend -o wide
   ```
   *Le ReplicaSet a recréé un pod pour revenir à 3 réplicas, mais ce nouveau pod porte un **autre nom et une autre adresse IP**.*

   > 💡 **Observation clé :** une adresse IP de pod n'est jamais une adresse fiable. Les clients doivent passer par un **Service**, qui regroupe les pods grâce à leur label et leur offre une adresse et un nom stables.

4. **Générer et appliquer le Service ClusterIP `campus-backend`.** **Un Service et ses pods sont découplés** : seul le sélecteur de labels les relie. Plutôt que de rédiger le Service à la main, générez-le à partir du Deployment qu'il doit servir, avec `kubectl expose` en mode `--dry-run=client -o yaml` :
   * Nom du service : `campus-backend` (le nom DNS attendu par le Nginx du frontend : il ne doit pas changer)
   * Port exposé par le service (`port`) : `8080`
   * Port du conteneur (`targetPort`) : `8080`
   * Type : `ClusterIP` (valeur par défaut, accessible uniquement depuis l'intérieur du cluster)

   ```bash
   kubectl expose deployment campus-backend --name=campus-backend --port=8080 --target-port=8080 --type=ClusterIP --dry-run=client -o yaml > service-backend.yaml
   kubectl apply -f service-backend.yaml
   ```

5. **Lire le manifest.** Ouvrez `service-backend.yaml` et repérez les trois éléments d'un Service :

   | Champ | Valeur | Rôle |
   | :--- | :--- | :--- |
   | `spec.type` | `ClusterIP` | Service interne au cluster |
   | `spec.ports` | `port: 8080`, `targetPort: 8080` | Port du Service → port du conteneur |
   | `spec.selector` | `app: campus-backend` | Les pods qui recevront le trafic (recopié depuis le Deployment par `kubectl expose`) |

   > 💡 **Pas d'étiquette, pas de trafic :** le Service envoie le trafic aux pods dont les **labels** correspondent à son **sélecteur**. Si aucun pod ne correspond (faute de frappe dans un label, par exemple), le Service existe bien, mais il ne transmet rien.

6. **Vérifier l'adresse du Service et les pods sélectionnés.** Notez l'adresse IP virtuelle du Service (`CLUSTER-IP`), puis la liste des pods qu'il a sélectionnés (ses **Endpoints**) :
   ```bash
   kubectl get svc campus-backend
   kubectl get endpoints campus-backend
   ```
   *Les adresses affichées par `get endpoints` sont exactement celles de vos pods backend (`kubectl get pods -l app=campus-backend -o wide`).*

7. **Vérifier la stabilité du Service.** Supprimez de nouveau un pod backend, attendez que son remplaçant soit `Running`, puis relancez les deux commandes :
   ```bash
   kubectl delete pod <nom-du-pod>
   kubectl get svc campus-backend
   kubectl get endpoints campus-backend
   ```

   > 💡 **Observation clé :** la liste des Endpoints s'est mise à jour automatiquement avec la nouvelle adresse du pod, alors que la `CLUSTER-IP` du Service **n'a pas changé**. Les clients du Service ne voient rien.

8. **Tester la découverte DNS (CoreDNS).** Kubernetes intègre un serveur DNS interne (**CoreDNS**). Un Service `<svc>` du namespace `<ns>` est joignable :
   * sous son **nom court** `<svc>` depuis un pod du même namespace ;
   * sous son **nom complet (FQDN)** `<svc>.<ns>.svc.cluster.local` depuis n'importe quel namespace.

   Démarrez un pod de test temporaire équipé de `curl` et `nslookup` :
   ```bash
   kubectl run test-dns --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- sh
   ```

   Depuis le terminal de ce conteneur, exécutez :
   ```sh
   # a. Résolution du nom court (même namespace)
   nslookup campus-backend

   # b. Requête HTTP vers le endpoint de santé du backend, par le nom court
   curl -i http://campus-backend:8080/actuator/health

   # c. Même requête avec le FQDN complet
   curl -i http://campus-backend.campus-dev.svc.cluster.local:8080/actuator/health

   # d. Le nom de la base : c'est ce nom que le backend utilise
   nslookup postgres

   # e. Un Service d'un AUTRE namespace : le DNS du cluster (kube-dns), dans kube-system
   nslookup kube-dns.kube-system.svc.cluster.local
   curl -s -o /dev/null -w "%{http_code}\n" http://kube-dns.kube-system:9153/metrics

   # f. Configuration DNS injectée dans le pod
   cat /etc/resolv.conf
   ```

   > ⚠️ **Lecture de `nslookup` :** l'outil essaie chaque suffixe de la directive `search` (voir commande f) et affiche des lignes `** server can't find campus-backend.svc.cluster.local: NXDOMAIN`. Elles sont normales : seule compte la ligne `Name: campus-backend.campus-dev.svc.cluster.local`, suivie de l'adresse `CLUSTER-IP` du Service. En revanche, `nslookup` n'applique pas ces suffixes à un nom qui contient déjà un point : c'est pourquoi la commande e l'interroge avec le nom complet, et vérifie la forme courte `kube-dns.kube-system` avec `curl` (réponse `200`), comme le ferait une vraie application.

   > 💡 **Observation clé :** chaque brique appelle la suivante par le **nom** de son Service : le backend se connecte à `jdbc:postgresql://postgres:5432/campus`, sans jamais connaître une IP. La directive `search campus-dev.svc.cluster.local svc.cluster.local cluster.local` de `/etc/resolv.conf` complète le nom court avec le namespace du pod : `postgres` désigne donc la base **du même namespace**. Pour joindre un Service d'un autre namespace, ajoutez ce namespace (`kube-dns.kube-system`, ou `postgres.campus-prod` pour la base de production du Lab 08) ou utilisez le nom complet. C'est pourquoi la même configuration fonctionne en dev comme en prod.

   Tapez `exit` pour quitter : le pod de test est supprimé automatiquement (`--rm`).

<details>
<summary>💡 <b>Indice : <code>nslookup campus-backend</code> échoue</b></summary>

* Vérifiez que le Service existe dans le bon namespace : `kubectl get svc campus-backend -n campus-dev`.
* Vérifiez que le pod de test a bien été créé dans `campus-dev` : `kubectl config view --minify -o jsonpath='{..namespace}'`.
* Si le nom se résout mais que `curl` échoue, le Service n'a pas d'Endpoints : `kubectl get endpoints campus-backend` doit lister des adresses.
</details>

9. **Déployer le frontend** (2 réplicas). Il démarre sans erreur car le nom `campus-backend`, attendu par son Nginx, existe dans le namespace depuis l'étape 4 :
   ```bash
   kubectl create deployment campus-frontend --image=regaieg/campus:frontend-1.0.0 --replicas=2 --port=8080 --dry-run=client -o yaml > deployment-frontend.yaml
   kubectl apply -f deployment-frontend.yaml
   ```

10. **Créer le Service NodePort.** Créez un fichier `service-frontend.yaml` :
    ```yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: campus-frontend-svc
    spec:
      type: NodePort
      selector:
        app: campus-frontend
      ports:
      - targetPort: 8080   # ① port du conteneur
        port: 80           # ② port du Service
        nodePort: 30088    # ③ port ouvert sur chaque nœud
    ```

    > 💡 **Note d'attribution de port :** nous fixons le port `30088` car `30080` est réservé au contrôleur Ingress NGINX du cluster.

    Appliquez le Service, puis listez les Services du namespace :
    ```bash
    kubectl apply -f service-frontend.yaml
    kubectl get services
    ```
    *Vous retrouvez les deux Services `ClusterIP` (`postgres`, `campus-backend`) et le `NodePort` `campus-frontend-svc`, affiché `80:30088/TCP`. Remarquez qu'il possède lui aussi une `CLUSTER-IP` : un NodePort **inclut** un ClusterIP.*

11. **Distinguer les 3 ports d'un Service NodePort**, de l'intérieur vers l'extérieur :

    | Paramètre | Valeur dans notre lab | Rôle |
    | :--- | :--- | :--- |
    | ① `targetPort` | `8080` | Port sur lequel le conteneur écoute réellement dans le pod. |
    | ② `port` | `80` | Port de l'adresse IP virtuelle du Service, utilisé par les autres pods du cluster. |
    | ③ `nodePort` | `30088` | Port ouvert sur **chaque nœud** du cluster (plage 30000-32767), accessible de l'extérieur. |

    Une requête venue de l'extérieur suit donc le chemin inverse : **`nodePort` → `port` → `targetPort`**.

    > 💡 **Et le type LoadBalancer ?** Dans le cloud (EKS, AKS, GKE), il ajoute devant les NodePorts un répartiteur de charge avec une vraie IP publique. Notre cluster kubeadm n'a pas de fournisseur cloud : un tel Service resterait en `EXTERNAL-IP <pending>`. D'où la règle : trafic interne → `ClusterIP`, accès externe sur notre cluster → `NodePort`, production dans le cloud → `LoadBalancer`.

12. **Accéder à l'application depuis votre navigateur.** Récupérez l'adresse IP publique de votre nœud worker `k8s-worker-1` (notée lors du Lab 00 dans MobaXterm ou la console AWS), puis ouvrez **`http://<IP_PUBLIQUE_WORKER>:30088`**.
    *Le portail affiche les offres de stage lues par l'API dans PostgreSQL : la chaîne **navigateur → NodePort → frontend → Service `campus-backend` → API → Service `postgres` → base** fonctionne.*

13. **Constater que le NodePort est ouvert sur chaque nœud.** Ouvrez maintenant **`http://<IP_PUBLIQUE_k8s-worker-2>:30088`** : le portail répond aussi, que ce nœud héberge ou non un pod frontend (vérifiez le placement avec `kubectl get pods -l app=campus-frontend -o wide`).

> 🛟 **Vous êtes sur Minikube (secours) ?** Avec le pilote Docker sous Windows ou macOS, l'adresse du nœud Minikube n'est pas joignable depuis votre poste. Remplacez l'étape 12 par un tunnel vers le Service :
>
> ```bash
> minikube service campus-frontend-svc -n campus-dev --url
> ```
>
> La commande affiche une adresse `http://127.0.0.1:<port>` : ouvrez-la dans votre navigateur et **laissez le terminal ouvert** tant que vous l'utilisez (`Ctrl + C` pour fermer le tunnel). L'étape 13 n'a pas d'équivalent : Minikube n'a qu'un seul nœud.

<details>
<summary>💡 <b>Indice : la page ne s'affiche pas ou le tableau de bord reste vide</b></summary>

* **Le navigateur n'obtient aucune réponse :** utilisez l'IP **publique** d'un worker (pas l'IP privée `172.31.x.x`) et le port `30088`. Les IP publiques changent à chaque redémarrage de la session AWS.
* **Le port est bloqué par le pare-feu de votre entreprise (Option A) :** passez par un tunnel, comme au [Lab 02](../02-premiers-pods-labels/README.md) : `kubectl port-forward svc/campus-frontend-svc 8081:80` lancé **depuis votre poste**, puis ouvrez `http://localhost:8081`. En Option B, ce tunnel s'ouvrirait sur `k8s-control` et non sur votre poste : il ne vous aiderait pas.
* **La page s'affiche mais les données sont absentes :** testez l'API à travers le frontend avec `curl http://<IP_PUBLIQUE_WORKER>:30088/actuator/health`. Une erreur `502 Bad Gateway` signifie que le Service `campus-backend` ne transmet rien : appliquez le réflexe **« Service muet ? `kubectl get endpoints` »**. Une liste vide signifie que le sélecteur du Service et les labels des pods ne correspondent pas.
</details>

> 🧭 **Pour aller plus loin (optionnel) – étapes 14 à 17 :** observer la répartition de charge du Service. À faire si le temps le permet : le lab est complet à l'étape 13.

14. **(Optionnel) Passer le frontend à 3 réplicas.** Un Service distribue les requêtes entre tous les pods qu'il sélectionne. Nous l'observons sur le frontend, car Nginx écrit une ligne de log pour **chaque** requête reçue :
    ```bash
    kubectl scale deployment campus-frontend --replicas=3
    kubectl wait --for=condition=ready pod -l app=campus-frontend --timeout=60s
    ```

15. **(Optionnel) Envoyer 12 requêtes au Service** depuis un pod de test :
    ```bash
    kubectl run test-lb --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- sh -c 'for i in $(seq 1 12); do curl -s -o /dev/null -w %{http_code}, http://campus-frontend-svc/; done; echo'
    ```
    *Vous devez obtenir douze codes `200`.*

16. **(Optionnel) Observer la répartition.** **Dans les 30 secondes qui suivent**, affichez les requêtes reçues par les 3 pods frontend :
    ```bash
    # Linux / macOS
    kubectl logs -l app=campus-frontend --since=30s --prefix=true | grep curl
    ```
    ```powershell
    # Windows (PowerShell)
    kubectl logs -l app=campus-frontend --since=30s --prefix=true | Select-String curl
    ```
    *`--prefix=true` affiche le nom du pod en tête de chaque ligne : vous comptez 12 lignes, réparties entre les réplicas.*

    > 💡 **Équilibrée, mais pas alternée :** chaque nouvelle connexion part vers un pod choisi au hasard. Il est normal qu'un pod reçoive 7 requêtes et un autre 2. Si vous relancez la boucle, attendez 30 secondes avant : sinon `--since=30s` additionne les deux séries.

17. **(Optionnel) Ramener le frontend à 2 réplicas :**
    ```bash
    kubectl scale deployment campus-frontend --replicas=2
    ```

---

## Critères de Validation (Checklist)

- [ ] Vous avez constaté qu'un pod recréé change d'adresse IP (`kubectl get pods -o wide`).
- [ ] `campus-backend` est un Service `ClusterIP` dont les Endpoints listent les pods backend, et vous savez qu'une liste vide signale un sélecteur qui ne correspond à aucun label (`kubectl get endpoints campus-backend`).
- [ ] `campus-backend` répond par son nom court et par son FQDN `campus-backend.campus-dev.svc.cluster.local`, et vous savez joindre un Service d'un autre namespace (`<svc>.<ns>`).
- [ ] `campus-frontend-svc` est exposé en `NodePort` sur le port `30088` et le portail s'affiche dans le navigateur via l'IP de chacun des deux workers.
- [ ] Vous distinguez `targetPort` (8080), `port` (80) et `nodePort` (30088).
- [ ] *(Optionnel)* Vous avez observé la répartition des requêtes entre les réplicas du frontend.
