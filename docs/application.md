# L'Application Fil Rouge : Campus Summer Portal

<div class="admonition info">
<p class="admonition-title">Architecture du Projet Fil Rouge</p>
<p>Pour ancrer chaque notion théorique dans une réalité d'entreprise concrète, tous les ateliers de cette formation gravitent autour d'une application d'entreprise moderne multi-niveaux : le <b>Campus Summer Portal</b> (Portail Horizon Stages).</p>
</div>

---

## Vue d'Ensemble de l'Architecture

L'application est découpée en **trois microservices conteneurisés** communicant au sein du cluster Kubernetes :

```mermaid
flowchart TD
    subgraph Client["Extérieur du Cluster"]
        Browser["Navigateur Utilisateur<br/>(Étudiant / Recruteur)"]
    end

    subgraph K8s["Cluster Kubernetes"]
        subgraph FrontTier["Niveau Présentation"]
            NodePortSvc["Service NodePort<br/>30088 (campus-dev) / 30089 (campus-prod)"]
            FE_Pod1["Pod Frontend 1<br/>(Nginx unprivileged)"]
            FE_Pod2["Pod Frontend 2<br/>(Nginx unprivileged)"]
        end

        subgraph BackTier["Niveau Métier (API REST)"]
            BackSvc["Service ClusterIP<br/>campus-backend:8080"]
            BE_Pod1["Pod Backend 1<br/>(Spring Boot 3 / Java 21)"]
            BE_Pod2["Pod Backend 2<br/>(Spring Boot 3 / Java 21)"]
        end

        subgraph DataTier["Niveau Données (Persistance)"]
            DBSvc["Service ClusterIP<br/>postgres:5432"]
            DB_Pod["Pod PostgreSQL 16"]
            PVC["PersistentVolumeClaim<br/>(1 GiB)"]
            PV["Disque local du worker<br/>(PersistentVolume local-path)"]
        end

        subgraph ConfigSec["Configuration & Secrets"]
            CM["ConfigMap<br/>campus-config"]
            SEC["Secret<br/>campus-db-credentials"]
        end
    end

    Browser -->|HTTP NodePort 30088 / 30089| NodePortSvc
    NodePortSvc --> FE_Pod1 & FE_Pod2
    FE_Pod1 & FE_Pod2 -->|HTTP 8080| BackSvc
    BackSvc --> BE_Pod1 & BE_Pod2
    BE_Pod1 & BE_Pod2 -->|TCP 5432| DBSvc
    DBSvc --> DB_Pod
    DB_Pod --- PVC
    PVC --- PV

    CM -.->|Variables non sensibles| BE_Pod1 & BE_Pod2
    SEC -.->|Identifiants (base64)| BE_Pod1 & BE_Pod2
    SEC -.->|Identifiants (base64)| DB_Pod
```

---

## Les Composants Détaillés

### 1. Le Frontend Web (`campus-frontend`)
* **Rôle** : Interface utilisateur pour la consultation des offres de stages et le dépôt de candidatures.
* **Technologie** : Nginx 1.27 unprivileged (sécurité sans compte root).
* **Image Docker Hub** : `regaieg/campus:frontend-1.0.0`
* **Port exposé** : `8080` (interne au conteneur)
* **Caractéristiques** :
  * Stateless (aucun état conservé localement).
  * Conçu pour être répliqué à l'échelle (2 à 5 pods selon la charge).
  * **Reverse proxy** : Nginx relaie `/api/` et `/actuator/` vers l'hôte **`campus-backend:8080`**. Ce nom est figé dans l'image : le Service du backend doit donc s'appeler exactement `campus-backend`, et exister **avant** le démarrage du frontend (Nginx vérifie le nom au lancement).

### 2. L'API Backend (`campus-backend`)
* **Rôle** : Cœur métier de l'application, validation des offres, exposition des endpoints REST et métriques de supervision.
* **Technologie** : Java 21, Spring Boot 3, Spring Data JPA, Spring Boot Actuator.
* **Image Docker Hub** : `regaieg/campus:backend-1.0.0`
* **Port d'écoute** : `8080`
* **Endpoints Clés** :
  * `/api/internships`, `/api/departments`, `/api/dashboard` : offres de stage, départements et tableau de bord.
  * `/api/applications` : liste (`GET`) et dépôt (`POST`) des candidatures.
  * `/actuator/health` : santé globale, **base de données comprise** (utilisée par la `readinessProbe`).
  * `/actuator/health/liveness` : vivacité du processus seul (utilisée par les `startupProbe` et `livenessProbe`).
  * `/actuator/prometheus` : métriques au format Prometheus.
* **Dépendance au démarrage** : l'API se connecte à PostgreSQL et insère ses données de démonstration dès son lancement. Sans base joignable, elle s'arrête en erreur (d'où la base de développement déployée au Lab 03).
* **Variables d'Environnement** :
  * `SPRING_DATASOURCE_URL` : `jdbc:postgresql://postgres:5432/campus`
  * `SPRING_DATASOURCE_USERNAME` : Fourni via Secret (`campus`)
  * `SPRING_DATASOURCE_PASSWORD` : Fourni via Secret (`CampusSecret2026!` en `campus-dev`, `ProductionSecretKey2026!` en `campus-prod`)
  * `SPRING_PROFILES_ACTIVE` : Fourni via ConfigMap (`production`)

### 3. La Base de Données (`campus-postgres`)
* **Rôle** : Persistance transactionnelle des candidatures et offres d'emploi.
* **Technologie** : PostgreSQL 16 Alpine.
* **Image Officielle** : `postgres:16-alpine`
* **Port standard** : `5432`
* **Chemin des données** : `/var/lib/postgresql/data` (monté sur un PersistentVolume).
* **Enjeu de Production** :
  * Si le conteneur est détruit ou redémarré sur un autre nœud worker, le volume persistant doit être immédiatement rattaché pour ne perdre aucune candidature.

---

## Images Docker Hub Officielles

Toutes les images applicatives nécessaires ont été pré-compilées, testées et publiées sur le compte officiel Docker Hub de la formatrice **Rym Regaieg** :

| Composant | Image Docker Hub | Taille | Port |
| :--- | :--- | :---: | :---: |
| **Frontend Web** | [`regaieg/campus:frontend-1.0.0`](https://hub.docker.com/r/regaieg/campus) | ~30 Mo | 8080 |
| **API Backend v1** | [`regaieg/campus:backend-1.0.0`](https://hub.docker.com/r/regaieg/campus) | ~250 Mo | 8080 |
| **Base PostgreSQL** | `postgres:16-alpine` | ~80 Mo | 5432 |

> 💡 Il n'existe pas d'image `backend-1.1.0` : la montée de version du Lab 03 est simulée en modifiant le gabarit de pod (variable `CAMPUS_RELEASE`), ce qui suffit à déclencher un *rolling update*.

Grâce à ces images publiques, **aucune étape de compilation Java locale n'est requise** sur les postes des apprenants, ce qui élimine toute friction technique le premier jour.
