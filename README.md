# Kubernetes — Orchestration et déploiement de conteneurs (XW335)

> **Formatrice :** Rym Regaieg
> **Application fil rouge :** *Campus Summer Portal* (Nginx, Spring Boot, PostgreSQL)

---

## Support en ligne

Tout le contenu de la formation est publié sur le site :
**<https://formation-kubernetes-labs.pages.dev/>**

* [Support de cours](https://formation-kubernetes-labs.pages.dev/support-cours/)
* Ateliers pratiques (énoncés pas à pas, commandes Windows PowerShell et Linux Bash)

---

## Contenu du dépôt

| Dossier | Contenu |
| :--- | :--- |
| `labs/` | Les 7 ateliers : énoncés (`README.md`), scripts, manifests de départ (`starter/`), Terraform |
| `pdf/ateliers/` | Version PDF imprimable de chaque atelier |
| `docs/` | Sources du site de formation (MkDocs) |

### Ateliers

| # | Atelier |
| :---: | :--- |
| 01 | Installation du cluster (Terraform AWS / scripts de session) |
| 02 | Les Pods |
| 03 | Les Déploiements & Scheduling |
| 04 | Les Services |
| 05 | Les Volumes |
| 06 | Administration & Supervision |
| 07 | Sécurité du cluster |

---

## Consulter le site en local (facultatif)

```bash
pip install mkdocs-material pymdown-extensions
python -m mkdocs serve   # http://127.0.0.1:8000
```
