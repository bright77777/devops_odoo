# Odoo Backup & Restore Infrastructure

Une stack complète et portable pour déployer Odoo 17 en Docker avec sauvegarde automatique et restauration depuis Cloudflare R2.

## 📋 Table des matières

- [Vue d'ensemble](#vue-densemble)
- [Prérequis](#prérequis)
- [Installation](#installation)
- [Configuration](#configuration)
- [Utilisation](#utilisation)
- [Architecture](#architecture)
- [Dépannage](#dépannage)
- [Bonnes pratiques](#bonnes-pratiques)

---

## 🎯 Vue d'ensemble

Cette infrastructure permet :

✅ **Déploiement simple** : `./scripts/setup.sh`  
✅ **Sauvegardes automatiques** : Tous les 5 jours via cron  
✅ **Stockage externe** : Cloudflare R2 (S3-compatible)  
✅ **Restauration complète** : Base + Filestore + Addons  
✅ **Portabilité** : Fonctionne sur n'importe quel serveur Ubuntu  
✅ **Versioning** : Infrastructure versionée, données externalisées  

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Ubuntu Server                        │
├─────────────────────────────────────────────────────────┤
│  Docker                                                 │
│  ├─ Odoo 17 Container (Port 80 → 8069)                 │
│  │  └─ Volumes:                                         │
│  │     ├─ odoo-web-data (filestore)                    │
│  │     ├─ ./addons (RO)                                │
│  │     └─ ./config/odoo.conf (RO)                      │
│  │                                                      │
│  └─ PostgreSQL 15 Container                            │
│     └─ Volumes:                                         │
│        └─ odoo-db-data                                 │
├─────────────────────────────────────────────────────────┤
│  Backup Scripts (Cron toutes les 5 jours)              │
│  ├─ Dump PostgreSQL                                     │
│  ├─ Archive Filestore                                   │
│  ├─ Archive Addons                                      │
│  └─ Upload vers Cloudflare R2                          │
├─────────────────────────────────────────────────────────┤
│                  Cloudflare R2                          │
│                  (Stockage S3)                          │
└─────────────────────────────────────────────────────────┘
```

---

## 📦 Prérequis

### Matériel
- **CPU** : Minimum 2 vCPU (4 recommandé)
- **RAM** : Minimum 4 GB (8 GB recommandé)
- **Disque** : 20 GB minimum (100 GB recommandé)
- **OS** : Ubuntu 20.04 LTS ou supérieur

### Logiciels requis
- `curl` ou `wget`
- `git`
- `docker` (sera installé par setup.sh)
- `docker-compose` (sera installé par setup.sh)
- `awscli` (sera installé par setup.sh)

### Comptes externes
- **Cloudflare** : Compte avec R2 activé
- **R2** : Bucket créé et credentials générées

---

## 🚀 Installation

### 1. Cloner le repository

```bash
git clone https://github.com/your-org/odoo-infra.git
cd odoo-infra
```

### 2. Copier et configurer le fichier `.env`

```bash
cp .env.example .env
```

Éditer `.env` avec vos valeurs :

```bash
nano .env
```

### 3. Configurer Cloudflare R2

Obtenir vos credentials R2 :
1. Aller à [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Navigate to **R2** → **Settings** → **API Token**
3. Créer un token avec permissions **Admin**
4. Copier :
   - Account ID (dans l'URL R2)
   - Access Key ID
   - Secret Access Key

Remplir `.env` :

```bash
CF_R2_ENDPOINT=https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
CF_R2_BUCKET=your-bucket-name
CF_R2_ACCESS_KEY_ID=your_access_key
CF_R2_SECRET_ACCESS_KEY=your_secret_key
```

### 4. Lancer le setup

```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

Le script va :
- ✅ Vérifier et installer les dépendances (Docker, Compose, AWS CLI)
- ✅ Configurer AWS CLI pour Cloudflare R2
- ✅ Télécharger les images Docker
- ✅ Démarrer les conteneurs Odoo et PostgreSQL
- ✅ Attendre que les services soient sains
- ✅ Installer le cron pour les backups automatiques
- ✅ Vérifier la connectivité R2

**Durée estimée** : 3-5 minutes

---

## 📝 Configuration

### Variables d'environnement (.env)

| Variable | Description | Exemple |
|----------|-------------|---------|
| `POSTGRES_USER` | Utilisateur PostgreSQL | `odoo` |
| `POSTGRES_PASSWORD` | Mot de passe PostgreSQL | `SecurePassword123!` |
| `POSTGRES_DB` | Nom de la base données | `odoo` |
| `ODOO_ADMIN_PASSWORD` | Mot de passe admin Odoo | `AdminPass456!` |
| `ODOO_WORKERS` | Nombre de workers Odoo | `4` |
| `ODOO_TIMEOUT` | Timeout en secondes | `600` |
| `CF_R2_ENDPOINT` | URL endpoint R2 | `https://xxx.r2.cloudflarestorage.com` |
| `CF_R2_BUCKET` | Nom du bucket R2 | `my-odoo-backups` |
| `CF_R2_ACCESS_KEY_ID` | Clé d'accès R2 | `xxx` |
| `CF_R2_SECRET_ACCESS_KEY` | Clé secrète R2 | `xxx` |
| `BACKUP_RETENTION_DAYS` | Durée de rétention | `30` |
| `BACKUP_SCHEDULE` | Cron schedule | `0 2 */5 * *` |

### Fichiers importants

```
odoo-infra/
├─ docker-compose.yml       # Configuration Docker
├─ .env                      # Variables sensibles (À REMPLIR)
├─ .env.example              # Template
├─ .gitignore               # Fichiers à ignorer
├─ config/
│  └─ odoo.conf             # Configuration Odoo 17
├─ addons/                  # Modules personnalisés
├─ scripts/
│  ├─ setup.sh              # Installation initiale
│  ├─ backup.sh             # Sauvegarde manuelle
│  └─ restore.sh            # Restauration
└─ backup/                  # Sauvegardes locales (exclu de Git)
```

---

## 💻 Utilisation

### Accès à Odoo

Après `setup.sh` :

```
http://localhost
```

Identifiants par défaut :
- **Utilisateur** : `admin`
- **Mot de passe** : (la valeur de `ODOO_ADMIN_PASSWORD` dans `.env`)

### Sauvegarde manuelle

```bash
./scripts/backup.sh
```

Le script va :
1. Dumper la base PostgreSQL
2. Archiver le filestore (`/var/lib/odoo`)
3. Archiver les addons personnalisés
4. Compresser le tout
5. Uploader vers Cloudflare R2
6. Nettoyer les fichiers temporaires
7. Supprimer les vieilles sauvegardes (> 30 jours)

**Sortie exemple** :
```
[INFO] ==========================================
[INFO] Starting Odoo Backup
[INFO] ==========================================
[INFO] PostgreSQL database backed up ✓ (Size: 245M)
[INFO] Odoo filestore backed up ✓ (Size: 1.2G)
[INFO] Addons folder backed up ✓ (Size: 52M)
[INFO] Backup package compressed ✓ (Size: 892M)
[INFO] Backup uploaded to R2 ✓
[INFO] R2 Path: s3://my-odoo-backups/odoo_backup_2025-12-01_02-00-00.tar.gz
```

### Sauvegarde automatique

Le cron s'installe automatiquement via `setup.sh`.

Vérifier :
```bash
crontab -l | grep backup.sh
```

Voir les logs :
```bash
tail -f /var/log/odoo-backup.log
```

Pour modifier la fréquence, éditer `.env` :
```bash
BACKUP_SCHEDULE="0 2 */7 * *"  # Tous les 7 jours à 02:00
```

Puis réinstaller le cron :
```bash
crontab -e  # Modifier manuellement
```

### Restauration

#### Option 1 : Depuis une sauvegarde locale

```bash
./scripts/restore.sh odoo_backup_2025-12-01_02-00-00
```

#### Option 2 : Depuis Cloudflare R2

```bash
./scripts/restore.sh odoo_backup_2025-12-01_02-00-00.tar.gz
```

Le script va :
1. Télécharger depuis R2 (si nécessaire)
2. Extraire l'archive
3. Confirmer la restauration (⚠ destructif)
4. Supprimer la base existante
5. Créer une nouvelle base
6. Restaurer le dump PostgreSQL
7. Restaurer le filestore
8. Restaurer les addons
9. Redémarrer les conteneurs
10. Vérifier que tout fonctionne

**Sortie exemple** :
```
[INFO] Backup downloaded from R2 ✓
[INFO] Backup extracted ✓
Continue with restore? (yes/no): yes
[INFO] Database restored ✓
[INFO] Filestore restored ✓
[INFO] Addons restored ✓
[INFO] ✓ Restore completed successfully!
```

### Commandes Docker utiles

```bash
# Voir le status
docker-compose ps

# Voir les logs Odoo
docker-compose logs -f odoo

# Voir les logs PostgreSQL
docker-compose logs -f postgres

# Accéder à la base PostgreSQL
docker-compose exec postgres psql -U odoo -d odoo

# Redémarrer les services
docker-compose restart

# Arrêter les services
docker-compose down

# Supprimer tous les volumes (⚠ destructif)
docker-compose down -v
```

---

## 🏗️ Architecture détaillée

### Flux de sauvegarde

```
┌──────────────────────┐
│  Cron (toutes 5j)    │
│  ou backup.sh        │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  1. Dump PostgreSQL                  │
│     pg_dump odoo → odoo_db.dump      │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  2. Archive Filestore                │
│     /var/lib/odoo → filestore.tar.gz │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  3. Archive Addons                   │
│     ./addons → addons.tar.gz         │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  4. Créer metadata + compresser      │
│     → odoo_backup_TIMESTAMP.tar.gz   │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  5. Upload vers Cloudflare R2        │
│     aws s3 cp → s3://bucket/         │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  6. Nettoyer les fichiers temporaires│
│     Supprimer backups > 30 jours     │
└──────────────────────────────────────┘
```

### Flux de restauration

```
┌──────────────────────────────────────┐
│  restore.sh <backup-name>            │
└──────────┬───────────────────────────┘
           │
           ├─ Si local : utiliser directement
           │
           └─ Si distant : télécharger de R2
                           ▼
┌──────────────────────────────────────┐
│  Arrêter Odoo, garder PostgreSQL     │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  Confirmation utilisateur             │
│  (⚠ destructif)                      │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  Supprimer base existante             │
│  Créer nouvelle base                  │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  Restaurer dump PostgreSQL            │
│  pg_restore → odoo                    │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  Restaurer filestore                  │
│  filestore.tar.gz → /var/lib/odoo    │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  Restaurer addons                     │
│  addons.tar.gz → ./addons            │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  Démarrer les conteneurs              │
│  Vérifier que tout fonctionne         │
└──────────────────────────────────────┘
```

---

## 🔧 Dépannage

### Les conteneurs ne démarrent pas

```bash
# Voir les logs
docker-compose logs

# Vérifier les ressources
docker stats

# Arrêter et nettoyer
docker-compose down
docker-compose up -d

# Redémarrer Docker
sudo systemctl restart docker
```

### Le backup échoue

```bash
# Vérifier les logs
tail -f /var/log/odoo-backup.log

# Tester la connectivité R2
aws s3 ls s3://YOUR_BUCKET --region auto

# Vérifier les credentials R2
aws configure list

# Tester Docker exec
docker-compose exec postgres pg_isready
```

### La restauration échoue

```bash
# Vérifier que le backup existe
ls -lh backup/

# Vérifier les credentials R2
./scripts/restore.sh help

# Tester une restauration manuelle
docker-compose exec postgres psql -U odoo -d odoo < backup.dump
```

### L'Odoo est lent

```bash
# Augmenter les workers dans .env
ODOO_WORKERS=8

# Redémarrer
docker-compose restart odoo

# Vérifier les ressources
docker stats odoo-web
```

### Erreur : "Can't connect to R2"

```bash
# Vérifier l'endpoint R2
echo $CF_R2_ENDPOINT

# Tester avec curl
curl -I $CF_R2_ENDPOINT

# Vérifier les credentials
cat ~/.aws/credentials

# Reconfigurer AWS CLI
./scripts/setup.sh
```

---

## 📚 Bonnes pratiques

### 🔐 Sécurité

✅ **Secrets** :
- Ne jamais commit `.env`
- Utiliser des secrets managers en production (HashiCorp Vault, AWS Secrets Manager)
- Changer `ODOO_ADMIN_PASSWORD` immédiatement après install

✅ **R2** :
- Utiliser un token R2 dédié (pas le master token)
- Limiter les permissions du token à R2 uniquement
- Rotation des credentials tous les 90 jours

✅ **Réseau** :
- Utiliser HTTPS en production (reverse proxy nginx)
- Firewall : ouvrir seulement port 80/443
- SSH : clé publique uniquement, pas de mot de passe

### 📊 Monitoring

```bash
# Alertes : surveiller les logs
tail -f /var/log/odoo-backup.log

# Vérifier les backups régulièrement
aws s3 ls s3://YOUR_BUCKET --recursive --region auto

# Size check
du -sh /var/lib/docker/volumes/*/

# Uptime
docker-compose ps
```

### 🔄 Rotation des sauvegardes

Par défaut : **30 jours de rétention**

Modifier dans `.env` :
```bash
BACKUP_RETENTION_DAYS=60  # Garder 2 mois
```

### 🆘 Disaster Recovery

**Checklist avant déploiement en production** :

- [ ] Tester la restauration sur un serveur de staging
- [ ] Vérifier les logs pendant 7 jours
- [ ] Mettre en place des alertes (NewRelic, Sentry, Datadog)
- [ ] Documenter la procédure de restauration
- [ ] Former l'équipe support
- [ ] RTO/RPO définis et testés
  - **RTO** : 1 heure (temps pour restaurer)
  - **RPO** : 5 jours (max de données perdues)

### 📝 Maintenance

```bash
# Nettoyer les vieilles images Docker
docker image prune -a

# Nettoyer les volumes orphelins
docker volume prune

# Logs à archiver
tar czf odoo-logs-$(date +%Y-%m).tar.gz /var/log/odoo-*

# Backup du repo
git push --all
git push --tags
```

---

## 🔗 Ressources externes

- [Odoo Documentation](https://www.odoo.com/documentation/)
- [Cloudflare R2 Documentation](https://developers.cloudflare.com/r2/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [AWS CLI S3 Documentation](https://docs.aws.amazon.com/cli/latest/reference/s3/)

---

## 📄 Licence

MIT - Libre d'utilisation et modification

---

## 🤝 Support

Pour les questions ou problèmes :

1. Vérifier les logs : `tail -f /var/log/odoo-backup.log`
2. Consulter le dépannage ci-dessus
3. Créer une issue GitHub
4. Contacter l'équipe DevOps

---

**Version** : 1.0.0  
**Dernière mise à jour** : Décembre 2025  
**Odoo Version** : 17  
**PostgreSQL Version** : 15  
**Docker Compose Version** : 3.8+
