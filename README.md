# Kubernetes : Kubernetes - Orchestration des conteneurs

> **Auteur :** Rym Regaieg  
> **Application Fil Rouge :** *Campus Summer Portal* (Microservices Nginx, Spring Boot, PostgreSQL)

---

## Site de Documentation (MkDocs)

Le projet dispose d'un site web de documentation technique généré avec **MkDocs Material** :

```bash
# Lancer le serveur local de documentation (live-reload sur http://127.0.0.1:8000)
python -m mkdocs serve

# Compiler le site statique dans le dossier site/
python -m mkdocs build
```

Le portail inclut :
* **Architecture Applicative** : Schémas Mermaid du *Campus Summer Portal* et images Docker Hub officielles (`regaieg/campus`).
* **Guide d'Environnement** : Procédures Minikube, KillerCoda et AWS Academy Learner Lab (Terraform).
* **8 Ateliers Pratiques (Labs 00 à 08)** : Énoncés pas-à-pas avec indices interactifs pliables et commandes multi-OS (Windows PowerShell & Linux Bash).

---

## Structure des Compétences d'Agents IA (`.agents/skills`)

| Compétence | Description & Déclencheur | Source / Référence |
| :--- | :--- | :--- |
| **`formateur-xw335`** (agent) | Règles du dépôt alignées sur le programme officiel XW335 (`pgm/`) : périmètre, gabarit des labs, conventions, sécurité | [`.agents/agents/formateur-xw335.md`](./.agents/agents/formateur-xw335.md) |
| **`superpowers`** (15 skills) | Méthodologie d'ingénierie logicielle (TDD, brainstorming, planification, debugging systématique, revue de code) | [obra/superpowers](https://github.com/obra/superpowers) |
| **`kubernetes`** | Conception, audit, durcissement et dépannage de manifests, Helm, Kustomize et clusters K8s | [LukasNiessen/kubernetes-skill](https://github.com/LukasNiessen/kubernetes-skill) |
| **`formateur-pedagogique`** | Ingénierie pédagogique, andragogie, déroulés minutés, méthodes actives, Qualiopi et Kirkpatrick | Dédié formation professionnelle d'adultes |
| **`master-instructional-design`** | Conception pédagogique avancée, CPTD, e-learning, outils auteurs (Storyline, Rise) et architecture d'évaluation | [narosemena/master-instructional-design](https://github.com/narosemena/master-instructional-design) |

---

## Utilisation avec l'Agent

Les compétences sont reconnues automatiquement par le système d'agents :
- Pour structurer une tâche de code ou un bug : demandez un plan ou un diagnostic TDD, le framework **Superpowers** s'activera.
- Pour concevoir un cluster, une architecture de conteneurs ou un lab : mentionnez **Kubernetes / k8s**.
- Pour structurer un atelier pratique ou une grille d'évaluation : mentionnez vos besoins pédagogiques.
