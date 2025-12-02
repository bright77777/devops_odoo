# 📁 Structure du Projet

Vue d'ensemble complète de la structure du projet et de tous les fichiers.

---

## 🎯 Vue d'ensemble

```
odoo-infra/
├── docker-compose.yml        # Configuration Docker (Odoo + PostgreSQL)
├── config/
│   └── odoo.conf             # Configuration Odoo 17
├── scripts/
│   ├── setup.sh              # Installation et configuration
│   ├── backup.sh             # Sauvegarde complète
│   └── restore.sh            # Restauration depuis backup
├── addons/                   # Modules Odoo personnalisés
│   └── .gitkeep
├── backup/                   # Sauvegardes locales (exclu de Git)
│   └── .gitkeep
├── .env                      # Variables d'environnement (À CRÉER, exclu de Git)
├── .env.example              # Template pour .env
├── .env.template             # Template documenté pour .env
├── .gitignore                # Fichiers à ignorer par Git
├── README.md                 # Documentation principale
├── DEPLOYMENT.md             # Guide de déploiement détaillé
├── TROUBLESHOOTING.md        # Guide de dépannage
├── QUICK_REFERENCE.md        # Référence rapide des commandes
├── PROJECT_STRUCTURE.md      # Ce fichier
└── quickstart.sh             # Script de démarrage rapide
```

---

## 📄 Description des fichiers

### 📦 Configuration Docker

#### `docker-compose.yml`

Configuration Docker Compose pour la stack complète.

**Services** :
- **postgres:15** : Base de données PostgreSQL
  - Port : 5432 (interne, non exposé)
  - Volume : `odoo-db-data` (persistant)
  - Healthcheck : pg_isready

- **odoo:17** : Instance Odoo 17
  - Port : 80 → 8069 (HTTP)
  - Volumes :
    - `odoo-web-data` : filestore
    - `./addons` : modules personnalisés (RO)
    - `./config/odoo.conf` : configuration (RO)
  - Healthcheck : curl http://localhost:8069

**Réseaux** : `odoo-network` (bridge)

**Volumes persistants** :
- `odoo-db-data` : données PostgreSQL
- `odoo-web-data` : filestore Odoo

---

### ⚙️ Configuration

#### `config/odoo.conf`

Configuration Odoo 17 (fichier chargé au démarrage du conteneur).

**Sections** :
- `[options]` : Configuration générale
  - Connection DB
  - Addons path
  - Security settings
  - Performance tuning
  - Logging

Variables interpolées depuis `.env` :
- `%(POSTGRES_PASSWORD)s`
- `%(ODOO_ADMIN_PASSWORD)s`
- `%(ODOO_WORKERS)s`
- `%(ODOO_TIMEOUT)s`

---

### 🛠️ Scripts Bash

#### `scripts/setup.sh` (5 min)

Installation et configuration initiale.

**Étapes** :
1. Valider le fichier `.env`
2. Vérifier/installer Docker, Docker Compose, AWS CLI
3. Configurer AWS CLI pour Cloudflare R2
4. Créer les répertoires
5. Télécharger les images Docker
6. Démarrer les conteneurs
7. Attendre que PostgreSQL soit healthy
8. Installer le cron pour backups automatiques
9. Vérifier la connectivité R2
10. Afficher le statut

**Conditions de succès** :
- Docker daemon actif
- `.env` rempli correctement
- Credentials R2 valides
- Au moins 4 GB RAM libre
- Au moins 20 GB espace disque

---

#### `scripts/backup.sh` (5-30 min)

Sauvegarde complète : base + filestore + addons

**Étapes** :
1. Dump PostgreSQL au format "custom" (pg_dump -F c)
2. Archive le filestore (`/var/lib/odoo`)
3. Archive les addons personnalisés
4. Crée un fichier metadata (backup.info)
5. Compresse le tout en `.tar.gz`
6. Upload vers Cloudflare R2
7. Nettoie les fichiers temporaires
8. Supprime les backups > 30 jours (local + R2)

**Outputs** :
- Archive locale : `backup/odoo_backup_YYYY-MM-DD_HH-MM-SS.tar.gz`
- Archive R2 : `s3://bucket/odoo_backup_YYYY-MM-DD_HH-MM-SS.tar.gz`
- Metadata : `backup/odoo_backup_YYYY-MM-DD_HH-MM-SS/backup.info`

**Exigences** :
- Conteneur PostgreSQL healthy
- AWS CLI configuré
- Accès R2 (lecture/écriture)

---

#### `scripts/restore.sh` (10-20 min)

Restauration complète depuis un backup.

**Étapes** :
1. Rechercher le backup (local ou R2)
2. Télécharger depuis R2 si nécessaire
3. Extraire l'archive
4. Arrêter Odoo (garder PostgreSQL)
5. Demander confirmation (destructif)
6. Supprimer la base existante
7. Créer une nouvelle base
8. Restaurer le dump PostgreSQL
9. Restaurer le filestore
10. Restaurer les addons
11. Redémarrer les conteneurs
12. Vérifier la santé

**Inputs** :
- Nom du backup : `restore.sh odoo_backup_2025-12-01_02-00-00`

**Exigences** :
- Backup existe (local ou R2)
- PostgreSQL healthy
- Au moins 2x la taille du backup en espace disque

---

### 📂 Répertoires

#### `addons/`

Modules Odoo personnalisés (optionnel).

**Utilisation** :
- Ajouter les modules Odoo tiers ou développés localement
- Monté en lecture seule dans le conteneur (`/mnt/extra-addons`)
- Sauvegardé dans les backups

**Structure recommandée** :
```
addons/
├── module_1/
│   ├── __init__.py
│   ├── __manifest__.py
│   └── models/
├── module_2/
│   └── ...
└── .gitkeep
```

---

#### `backup/`

Sauvegardes locales (exclu de Git).

**Contenu** :
- Fichiers `.tar.gz` (archives comprimées)
- Dossiers temporaires pendant backup

**Nettoyage** :
- Automatique : suppression des backups > 30 jours
- Manuel : `rm backup/*.tar.gz`

**Taille** :
- Généralement 200 MB - 2 GB par backup
- Dépend de la taille du filestore

---

#### `config/`

Fichiers de configuration statiques.

**Contenu** :
- `odoo.conf` : Configuration Odoo

**Extensions futures** :
- `nginx.conf` : Configuration reverse proxy
- `ssl/` : Certificats SSL

---

### 📋 Fichiers de configuration

#### `.env` (À CRÉER)

Variables d'environnement sensibles.

**Ne jamais commit** : ajout du `.gitignore`

**Contenu** :
```
POSTGRES_USER=odoo
POSTGRES_PASSWORD=xxx
POSTGRES_DB=odoo
ODOO_ADMIN_PASSWORD=xxx
CF_R2_ENDPOINT=https://xxx.r2.cloudflarestorage.com
CF_R2_BUCKET=xxx
CF_R2_ACCESS_KEY_ID=xxx
CF_R2_SECRET_ACCESS_KEY=xxx
```

**Génération** :
```bash
cp .env.example .env
nano .env  # Remplir vos valeurs
chmod 600 .env
```

---

#### `.env.example`

Template minimal de `.env` (exemple simple).

**Contenu** :
- Même structure que `.env`
- Valeurs par défaut ou placeholders
- Version compacte

**Usage** :
```bash
cp .env.example .env
```

---

#### `.env.template`

Template très documenté avec commentaires.

**Contenu** :
- Structure complète
- Commentaires détaillés
- Instructions de remplissage
- Exemples

**Usage** :
```bash
cat .env.template > .env
nano .env  # Remplir et adapter
```

---

#### `.gitignore`

Fichiers/dossiers ignorés par Git.

**Ignore** :
- `.env*` (tous les fichiers d'environnement)
- `backup/` (sauvegardes locales)
- `*.dump`, `*.sql`, `*.tar.gz` (données)
- `*.log` (logs)
- `.DS_Store`, `.idea/`, `.vscode/` (OS/IDE)

**Effet** : données jamais versionnées, infrastructure seulement

---

### 📚 Documentation

#### `README.md` (Principal)

Documentation complète du projet.

**Sections** :
- Vue d'ensemble
- Architecture (diagrammes)
- Prérequis
- Installation (étape par étape)
- Configuration (variables)
- Utilisation (accès, backup, restore)
- Architecture détaillée (flux)
- Dépannage
- Bonnes pratiques
- Ressources externes

---

#### `DEPLOYMENT.md` (Pratique)

Guide pas à pas de déploiement sur un serveur neuf.

**Sections** :
- Phase 1 : Préparation serveur
- Phase 2 : Clonage repository
- Phase 3 : Configuration `.env`
- Phase 4 : Credentials Cloudflare R2
- Phase 5 : Lancement setup
- Phase 6 : Vérification
- Phase 7 : Configuration Odoo initiale
- Tests de backup/restore
- Restauration sur nouveau serveur
- Dépannage rapide
- Monitoring
- Sécurité

---

#### `TROUBLESHOOTING.md` (Dépannage)

Solutions aux problèmes courants.

**Sections** :
- Installation
- Docker
- Backup
- Restauration
- Performance
- Connexion R2
- Cron
- Escalade support

---

#### `QUICK_REFERENCE.md` (Rapide)

Référence rapide des commandes essentielles.

**Contenu** :
- Commandes par use case
- Tableau "Aide rapide"
- Lien vers doc complète

---

#### `PROJECT_STRUCTURE.md` (Ce fichier)

Description de la structure du projet.

---

### 🚀 Scripts spéciaux

#### `quickstart.sh`

Script de démarrage ultra-rapide (optionnel).

**Étapes** :
1. Valide que `.env` existe
2. Copie `.env.example` → `.env`
3. Demande de remplir `.env`
4. Valide les credentials R2
5. Lance `./scripts/setup.sh`

**Usage** :
```bash
./quickstart.sh
```

---

## 🔄 Flux de données

### Installation

```
git clone
├─ Copier .env.example → .env
├─ Remplir .env avec credentials
└─ ./scripts/setup.sh
   ├─ Installer Docker
   ├─ Configurer AWS CLI
   ├─ docker-compose up -d
   ├─ Installer cron
   └─ Vérifier tout
```

### Sauvegarde (manuel)

```
./scripts/backup.sh
├─ pg_dump → database.dump
├─ tar → filestore.tar.gz
├─ tar → addons.tar.gz
├─ Créer metadata
├─ tar → backup.tar.gz
├─ aws s3 cp → R2
└─ Nettoyer local + R2
```

### Sauvegarde (auto)

```
Cron (tous les 5 jours 02:00)
└─ ./scripts/backup.sh
   └─ (même flux que manuel)
```

### Restauration

```
./scripts/restore.sh <backup-name>
├─ Télécharger de R2 (si nécessaire)
├─ Extraire
├─ Arrêter Odoo
├─ Confirmation utilisateur
├─ dropdb + createdb
├─ pg_restore
├─ Restaurer filestore
├─ Restaurer addons
├─ docker-compose start
└─ Vérifier santé
```

---

## 📊 Tailles typiques

| Élément | Taille |
|---------|--------|
| Image Odoo:17 | ~1 GB |
| Image PostgreSQL:15 | ~50 MB |
| Volume PostgreSQL (vide) | ~20 MB |
| Odoo filestore (vide) | ~10 MB |
| Backup initial (vide) | ~50 MB |
| Backup avec données (1 mois) | ~200-500 MB |
| Backup avec données (1 an) | ~1-2 GB |

---

## 🔐 Sécurité des fichiers

| Fichier | Permissions | Git | Confidentialité |
|---------|------------|-----|-----------------|
| `.env` | `600` | ❌ Ignored | 🔐 Secrets |
| `docker-compose.yml` | `644` | ✅ Tracked | 🟢 Public |
| `scripts/*.sh` | `755` | ✅ Tracked | 🟢 Public |
| `config/odoo.conf` | `644` | ✅ Tracked | 🟡 Config |
| `backup/*.tar.gz` | `644` | ❌ Ignored | 🔐 Données |
| `README.md` | `644` | ✅ Tracked | 🟢 Public |

---

## 🌳 Versioning

### Git flow

```
main branch (tracked)
├── docker-compose.yml
├── config/odoo.conf
├── scripts/*.sh
├── README.md
├── .gitignore
└── *.md

EXCLUDED (in .gitignore)
├── .env
├── backup/
├── *.dump
└── *.log
```

### Workflow recommandé

```bash
# Initial setup
git clone <repo>
cp .env.example .env
nano .env
./scripts/setup.sh

# Modifications
nano docker-compose.yml
git add docker-compose.yml
git commit -m "Update workers count"
git push

# Backups (ne pas versionner)
./scripts/backup.sh
# → backup/*.tar.gz (excluded from Git)
# → s3://bucket/ (external storage)
```

---

## 🎯 Checklist de configuration

- [ ] `.env` créé et rempli
- [ ] `.env` permissions 600
- [ ] `.env` non trackée par Git
- [ ] R2 bucket créé
- [ ] R2 token généré
- [ ] Docker installé
- [ ] `./scripts/setup.sh` exécuté
- [ ] Odoo accessible
- [ ] Premier backup manuel réussi
- [ ] Cron vérifié
- [ ] Restauration testée (sur staging)

---

**Version** : 1.0.0 | **Dernière mise à jour** : Décembre 2025
