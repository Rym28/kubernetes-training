# Support de Cours

Cette page rassemble les supports de la **partie cours** de la formation **XW335 — Kubernetes : orchestration et déploiement de conteneurs**. Ils complètent les ateliers pratiques et préparent l'[évaluation des acquis](evaluation.md).

<div class="admonition info" markdown>
<p class="admonition-title"><strong>Comment utiliser ces supports</strong></p>

Le support de présentation reprend les apports théoriques du formateur (environ 30 % du temps de formation). Les fiches PDF des ateliers sont la version imprimable des énoncés publiés dans l'onglet **Ateliers Pratiques**.

</div>

---

## Support de présentation

Le support de cours **Kubernetes — XW335** (135 diapositives) est consultable en lecture seule ci-dessous. Le téléchargement sera ouvert par le formateur en fin de session.


[:material-file-pdf-box: Télécharger le support de cours (PDF)](assets/XW335_Kubernetes_Support-Cours.pdf){ .md-button .md-button--primary }

<iframe src="../assets/XW335_Kubernetes_Support-Cours.pdf#toolbar=0&navpanes=0" title="Support de cours XW335" width="100%" height="720" style="border:1px solid var(--md-default-fg-color--lightest);border-radius:4px;" oncontextmenu="return false;"></iframe>

---

## Plan du cours

Le cours suit les 5 chapitres du programme officiel. Le tableau indique les ateliers qui mettent chaque chapitre en pratique.

| # | Chapitre | Notions abordées | Mise en pratique |
| :---: | :--- | :--- | :--- |
| 1 | **Introduction** | Origine du projet, fonctionnalités, containers supportés, plates-formes utilisant Kubernetes, composants, définitions (pods, labels, controllers, services) | [Atelier 02](labs/02-pods-trois-briques.md), [Atelier 03](labs/03-deploiements-resilience-rollback.md), [Atelier 04](labs/04-reseau-services-dns.md) |
| 2 | **Architecture** | Master : etcd (stockage des configurations), API Server ; Nœuds : hébergement des containers, Kubelet | Démonstration formateur, [Atelier 07](labs/07-securite-quotas-isolement-reseau.md) (etcd) |
| 3 | **Installation et configuration** | Solutions d'installation ; kubectl, minikube, kubeadm ; mémoire, stockage, CPU, affectation de pods à des nœuds ; configuration d'applications et exécution | [Atelier 01](labs/01-provisionnement-cluster.md), [Atelier 02](labs/02-pods-trois-briques.md), [Atelier 05](labs/05-configuration-stockage-persistant.md) |
| 4 | **Administration** | Supervision, logs, debugging ; `kubectl exec` ; Node Problem Detector ; StackDriver | [Atelier 06](labs/06-exploitation-observabilite-debugging.md) |
| 5 | **Sécurité** | Points à sécuriser ; accès à l'API ; limitation des ressources ; contrôle des accès réseau ; restrictions des accès à etcd | [Atelier 07](labs/07-securite-quotas-isolement-reseau.md) |

---

## Fiches PDF des ateliers

| Atelier | Fiche PDF |
| :--- | :---: |
| Atelier 01 : Provisionnement du Cluster | [:material-file-pdf-box: PDF](https://github.com/Rym28/kubernetes-training/raw/main/pdf/ateliers/Atelier-01-Installation-Cluster.pdf) |
| Atelier 02 : Les Pods | [:material-file-pdf-box: PDF](https://github.com/Rym28/kubernetes-training/raw/main/pdf/ateliers/Atelier-02-Les-Pods.pdf) |
| Atelier 03 : Déploiements — Résilience & Rollback | [:material-file-pdf-box: PDF](https://github.com/Rym28/kubernetes-training/raw/main/pdf/ateliers/Atelier-03-Les-Deploiements-Scheduling.pdf) |
| Atelier 04 : Réseau, Services & Découverte DNS | [:material-file-pdf-box: PDF](https://github.com/Rym28/kubernetes-training/raw/main/pdf/ateliers/Atelier-04-Les-Services.pdf) |
| Atelier 05 : Configuration & Stockage Persistant | [:material-file-pdf-box: PDF](https://github.com/Rym28/kubernetes-training/raw/main/pdf/ateliers/Atelier-05-Les-Volumes.pdf) |
| Atelier 06 : Exploitation, Observabilité & Debugging | [:material-file-pdf-box: PDF](https://github.com/Rym28/kubernetes-training/raw/main/pdf/ateliers/Atelier-06-Administration-Supervision.pdf) |
| Atelier 07 : Sécurité, Quotas & Isolement Réseau | [:material-file-pdf-box: PDF](https://github.com/Rym28/kubernetes-training/raw/main/pdf/ateliers/Atelier-07-Securite-Cluster.pdf) |
