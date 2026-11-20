# Solution Lab 01 — Anatomie du Plan de Contrôle Kubernetes

## 1. Raisonnement et chaîne causale

1. Les composants du plan de contrôle Kubernetes démarrés par `kubeadm` sont hébergés sous forme de **Pods statiques**. Le démon `kubelet` sur `k8s-control` surveille activement `/etc/kubernetes/manifests`.
2. Lorsqu'un fichier est retiré de ce répertoire (par exemple `kube-scheduler.yaml`), la `kubelet` termine le conteneur du scheduler.
3. Lors de la soumission d'un nouveau Pod via `kubectl apply`, l'API Server valide la ressource et l'écrit dans `etcd`. Le Pod est créé avec `.spec.nodeName = ""` et son statut est `Pending`.
4. En l'absence de scheduler, aucun composant n'observe les Pods non affectés. Le Pod reste indéfiniment en attente.
5. Dès que le manifeste du scheduler est remis en place, la `kubelet` redémarre le Pod `kube-scheduler`, qui détecte le Pod en `Pending`, exécute l'algorithme de filtrage/scoring et met à jour le champ `nodeName`.

---

## 2. Commandes complètes de la solution

### Étape 1 : Inspection des manifestes statiques
```bash
sudo ls -lh /etc/kubernetes/manifests/
# Visualiser les arguments de kube-apiserver
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep -E "etcd-servers|client-ca-file"
```

### Étape 2 : Commandes etcdctl
```bash
# Vérifier la présence du binaire ou installer etcd-client
which etcdctl || sudo apt-get install -y etcd-client

# Tester la santé d'etcd
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Lister les membres du cluster etcd
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list -w table

# Afficher les métriques d'espace disque d'etcd
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status -w table
```

### Étape 3 : Appels bruts à l'API Server
```bash
# Vérifier la disponibilité globale
kubectl get --raw /livez
kubectl get --raw /readyz

# Consulter les métriques internes du plan de contrôle
kubectl get --raw /metrics | head -n 25
```

### Étape 4 : Démonstration de la panne du scheduler
```bash
# 1. Isoler le manifeste du scheduler
sudo mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/kube-scheduler.yaml

# 2. Vérifier la disparition du scheduler
kubectl get pods -n kube-system | grep scheduler
# Le pod disparaît en 10 à 15 secondes

# 3. Déployer la charge de test
kubectl apply -f labs/01-control-plane-anatomy/starter/probe-workload.yaml

# 4. Observer le statut Pending
kubectl get pod scheduler-probe -o wide
# Node: <none>

# 5. Inspecter les événements
kubectl describe pod scheduler-probe | tail -n 10
# Aucun événement "Scheduled"

# 6. Rétablir le scheduler
sudo mv /tmp/kube-scheduler.yaml /etc/kubernetes/manifests/kube-scheduler.yaml

# 7. Constater le démarrage du scheduler puis l'ordonnancement du Pod
kubectl get pods -n kube-system -w
kubectl get pod scheduler-probe -o wide
# Node passe à k8s-worker-1 ou k8s-worker-2, statut Running
```

---

## 3. Nettoyage pour l'atelier suivant

```bash
kubectl delete -f labs/01-control-plane-anatomy/starter/probe-workload.yaml
```
