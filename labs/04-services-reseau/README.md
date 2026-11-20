# Lab 04 : Réseau, Services & Découverte DNS

### Objectifs Pédagogiques :
* Comprendre pourquoi les adresses IP des Pods sont volatiles et éphémères.
* Comprendre le Service **ClusterIP** `campus-backend` (préparé au Lab 02), le régénérer de façon déclarative et tester la résolution DNS interne (**CoreDNS**).
* Inspecter l'anatomie des **Endpoints** et **EndpointSlices** et pratiquer la mise en quarantaine d'un Pod.
* Exposer le frontend vers l'extérieur avec un Service **NodePort** et comprendre la dissociation des 3 ports.
* Observer la répartition de charge d'un Service entre plusieurs réplicas.
* Utiliser `kubectl port-forward` pour des tests de connectivité locaux sécurisés.

> 📌 **Note Compatibilité OS :**  
> Les commandes de cet atelier (`kubectl expose`, `kubectl get svc`, `kubectl port-forward`) sont **rigoureusement identiques** sous **Windows (PowerShell)**, **Linux (Ubuntu)** et **macOS (Terminal)**.
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
>
> *Le namespace est présenté en détail à l'Exercice 0 du [Lab 02](../02-premiers-pods-labels/README.md#exercice-0--le-namespace-votre-périmètre-de-travail).*

---

## Contexte Métier
Dans une architecture Kubernetes, les pods naissent, meurent et changent d'adresse IP à chaque mise à jour, incident ou redémarrage. Si le frontend essayait de contacter le backend avec une adresse IP directe de pod, la communication casserait dès la première mise à jour. Nous devons mettre en place un **Service** pour fournir une adresse IP virtuelle stable, un nom DNS interne pérenne et de l'équilibrage de charge automatique (*Load Balancing*).

---

## Exercice 1 : Service ClusterIP & Découverte DNS CoreDNS

### 1. Identifier les pods cibles et leurs labels
Vérifiez que vos pods backend créés au Lab 03 sont actifs et notez leur label `app=campus-backend` :

```bash
kubectl get pods -l app=campus-backend --show-labels
```

### 2. Le Service ClusterIP `campus-backend` : du squelette au service opérationnel
Au Lab 02, vous avez créé le Service `campus-backend` alors qu'aucun pod backend n'existait. Depuis le Lab 03, ses endpoints contiennent les adresses de vos pods : **un Service et ses pods sont totalement découplés**, seul le sélecteur de labels les relie.

En production, on ne rédige pas un Service à la main : on le génère à partir du Deployment qu'il doit servir. Régénérez votre manifest avec `kubectl expose` en mode `--dry-run=client -o yaml` :
* Nom du service : `campus-backend` (le nom DNS attendu par le Nginx du frontend : il ne doit pas changer)
* Port exposé par le service : `8080`
* Port cible du conteneur (`targetPort`) : `8080`
* Type : `ClusterIP` (valeur par défaut)

```bash
kubectl expose deployment campus-backend --name=campus-backend --port=8080 --target-port=8080 --type=ClusterIP --dry-run=client -o yaml > service-backend.yaml
kubectl apply -f service-backend.yaml
```

*Ouvrez `service-backend.yaml` : `kubectl expose` a recopié automatiquement le sélecteur `app: campus-backend` depuis le Deployment. Le `kubectl apply` met à jour le Service existant sans changer son adresse IP.*

Inspectez le service et notez son adresse IP virtuelle (`CLUSTER-IP`) :

```bash
kubectl get svc campus-backend
```

### 3. Valider la résolution DNS avec un conteneur éphémère
Kubernetes intègre un serveur DNS interne (**CoreDNS**). Tout service nommé `<svc>` dans le namespace `<ns>` est joignable sous son nom court `http://<svc>:<port>` ou son FQDN complet `http://<svc>.<ns>.svc.cluster.local:<port>`.

Démarrez un pod temporaire de diagnostic équipé de `curl` :

```bash
kubectl run test-dns --image=curlimages/curl --rm -it --restart=Never -- sh
```

Depuis le terminal de ce conteneur éphémère, exécutez les vérifications suivantes :

```sh
# 1. Résolution DNS du nom court
nslookup campus-backend

# 2. Requête HTTP vers le endpoint de santé Spring Boot
curl -i http://campus-backend:8080/actuator/health

# 3. Requête avec le FQDN complet (Fully Qualified Domain Name)
curl -i http://campus-backend.campus-dev.svc.cluster.local:8080/actuator/health

# 4. Inspection de la configuration DNS injectée par le Kubelet
cat /etc/resolv.conf
```

> 💡 **Observation clé :** Observez la directive `search campus-dev.svc.cluster.local svc.cluster.local cluster.local` dans `/etc/resolv.conf`. C'est elle qui permet de résoudre `campus-backend` sans saisir le suffixe complet !

Tapez `exit` pour quitter et détruire le conteneur de test.

---

## Exercice 2 : Anatomie des Endpoints, EndpointSlices & Quarantaine

### 1. Inspecter les Endpoints et EndpointSlices
Le Service n'est qu'une règle de routage virtuelle gérée par `kube-proxy` (via iptables ou IPVS). La liste réelle des adresses IP des pods sains est maintenue dans un objet séparé : **Endpoints** (et **EndpointSlices** en Kubernetes moderne) :

```bash
kubectl get endpoints campus-backend
kubectl get endpointslices -l kubernetes.io/service-name=campus-backend
```

Constatez que les adresses IP listées dans les Endpoints correspondent exactement aux IP des pods backend (`kubectl get pods -l app=campus-backend -o wide`).

### 2. Mettre un Pod en Quarantaine en Production (Cas d'Usage Réel)
En production, lorsqu'un pod produit des erreurs intermittentes, détruire le pod efface les preuves. La technique DevOps recommandée consiste à **modifier le label du pod** pour le sortir instantanément des Endpoints du Service sans l'arrêter :

1. Choisissez le nom d'un de vos pods backend :
   ```bash
   POD_TARGET=$(kubectl get pods -l app=campus-backend -o jsonpath='{.items[0].metadata.name}')
   echo "Pod ciblé : $POD_TARGET"
   ```

2. Changez son label `app` pour l'isoler :
   ```bash
   kubectl label pod $POD_TARGET app=campus-backend-debug --overwrite
   ```

3. Observez immédiatement les Endpoints du service :
   ```bash
   kubectl get endpoints campus-backend
   ```
   *L'adresse IP du pod ciblé a instantanément disparu de la liste des Endpoints ! Aucun utilisateur ne sera plus dirigé vers lui.*

4. Constatez également que le ReplicaSet du Deployment a immédiatement créé un nouveau pod de remplacement pour respecter le nombre de réplicas désiré (`replicas: 3` en fin de Lab 03) !

5. Remettez de l'ordre en supprimant le pod en quarantaine :
   ```bash
   kubectl delete pod $POD_TARGET
   ```

---

## Exercice 3 : Exposition Externe via NodePort & Détection de Pièges

### 1. Déployer le composant Frontend
Déployez le frontend de l'application (2 réplicas). Il démarre sans erreur car le nom `campus-backend`, attendu par son Nginx, existe dans le namespace depuis le Lab 02 :

```bash
kubectl create deployment campus-frontend --image=regaieg/campus:frontend-1.0.0 --replicas=2 --port=8080 --dry-run=client -o yaml > deployment-frontend.yaml
kubectl apply -f deployment-frontend.yaml
```

### 2. Créer le Service NodePort
Créez un fichier `service-frontend.yaml` :

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
  - port: 80
    targetPort: 8080
    nodePort: 30088
```

> 💡 **Note d'attribution de port :** Nous allouons le port statique `30088` car `30080` est réservé par le contrôleur Ingress NGINX sur le cluster.

Appliquez le Service :

```bash
kubectl apply -f service-frontend.yaml
kubectl get svc campus-frontend-svc
```

### 3. Comprendre la dissociation des 3 ports réseau

| Paramètre | Valeur dans notre lab | Rôle en architecture Kubernetes |
| :--- | :--- | :--- |
| `port` | `80` | Port virtuel interne exposé par le Service au sein du cluster (utilisé par d'autres pods). |
| `targetPort` | `8080` | Port sur lequel le conteneur applicatif écoute réellement à l'intérieur du Pod. |
| `nodePort` | `30088` | Port statique ouvert sur **chaque nœud (Node Worker)** du cluster dans la plage 30000-32767. |

### 4. Accéder à l'application via le NodePort sur AWS

Sur votre cluster AWS multi-nœuds :
1. Récupérez l'adresse IP publique de votre nœud worker `k8s-worker-1` (notée lors du Lab 00 dans votre session MobaXterm ou console AWS).
2. Ouvrez votre navigateur web à l'adresse : **`http://<IP_PUBLIQUE_WORKER>:30088`**.
3. Vous accédez directement au portail web d'accueil servi par le frontend : le tableau de bord affiche les offres de stage lues par l'API dans PostgreSQL. La chaîne complète **navigateur → NodePort → frontend → Service `campus-backend` → API → Service `postgres` → base** fonctionne !

<details>
<summary>💡 <b>Indice : la page ne s'affiche pas ou le tableau de bord reste vide</b></summary>

* **Le navigateur n'obtient aucune réponse :** vérifiez que vous utilisez l'IP **publique** d'un worker (pas l'IP privée `172.31.x.x`) et le port `30088`. Les IP publiques des workers changent à chaque redémarrage de la session AWS.
* **La page s'affiche mais les données sont absentes :** testez l'API à travers le frontend avec `curl http://<IP_PUBLIQUE_WORKER>:30088/actuator/health`. Une erreur `502 Bad Gateway` signifie que le Service `campus-backend` n'a pas d'endpoints : vérifiez `kubectl get endpoints campus-backend`.
</details>

---

## Exercice 4 : Répartition de Charge & Scalabilité

### 1. Tester la répartition du trafic
Testons comment un Service distribue les requêtes entre plusieurs réplicas. Nous utilisons le frontend, car Nginx écrit une ligne de log pour **chaque** requête reçue (Spring Boot, lui, ne journalise pas les appels à `/actuator/health`).

1. Montez le nombre de réplicas du frontend à 3 :
   ```bash
   kubectl scale deployment campus-frontend --replicas=3
   kubectl wait --for=condition=ready pod -l app=campus-frontend --timeout=60s
   ```

2. Lancez une boucle de 12 requêtes vers le Service depuis un conteneur de test :
   ```bash
   kubectl run test-lb --image=curlimages/curl --rm -it --restart=Never -- sh -c 'for i in $(seq 1 12); do curl -s -o /dev/null -w "%{http_code} " http://campus-frontend-svc/ ; done; echo'
   ```
   *Vous devez obtenir douze codes `200`.*

3. Affichez les dernières lignes de log des 3 pods frontend :
   ```bash
   kubectl logs -l app=campus-frontend --tail=12 --prefix=true | grep curl
   ```
   *L'indicateur `--prefix=true` affiche le nom du pod en tête de chaque ligne : les 12 requêtes (agent `curl`) sont réparties entre les réplicas. Relancez la boucle si un pod n'en a reçu aucune : c'est rare, mais possible (voir ci-dessous).*

> 💡 **Aléatoire, pas tourniquet :** en mode `iptables` (le mode par défaut de `kube-proxy`), chaque nouvelle connexion est envoyée vers un pod tiré au hasard. La répartition est équilibrée en moyenne, mais pas strictement alternée (*round-robin*) : il est normal qu'un pod reçoive 5 requêtes et un autre 3.

4. Ramenez le frontend à 2 réplicas :
   ```bash
   kubectl scale deployment campus-frontend --replicas=2
   ```

---

## Exercice 5 : Port-Forwarding et Débogage Local Sécurisé

En environnement d'entreprise, ouvrir un NodePort ou un LoadBalancer public n'est pas toujours autorisé pour des raisons de conformité de sécurité. La commande `kubectl port-forward` permet d'établir un tunnel chiffré direct via l'API Server pour accéder à un service interne.

1. Lancez un tunnel de port-forwarding vers le service frontend :
   ```bash
   kubectl port-forward svc/campus-frontend-svc 8081:80
   ```

2. Ouvrez un second terminal (ou votre navigateur) à l'adresse : **`http://localhost:8081`**
   * Vous devez voir s'afficher l'interface d'accueil du **Campus Summer Portal** !

3. Pour interrompre le tunnel, appuyez sur `Ctrl + C` dans le terminal où tourne la commande.

---

## Critères de Validation (Checklist)

- [ ] `campus-backend` est de type `ClusterIP` et résolu par CoreDNS (`nslookup campus-backend`).
- [ ] Vous avez inspecté les `endpoints` et compris la mise en quarantaine d'un pod par son label.
- [ ] `campus-frontend-svc` est exposé en `NodePort` sur le port `30088`.
- [ ] Vous distinguez clairement `port` (80), `targetPort` (8080) et `nodePort` (30088).
- [ ] Vous avez observé la répartition du trafic d'un Service entre plusieurs réplicas (aléatoire en mode `iptables`).
- [ ] Vous savez utiliser `kubectl port-forward` pour inspecter un service en toute sécurité.
