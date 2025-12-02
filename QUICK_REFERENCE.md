# 🚀 Référence Rapide

Commandes essentielles pour la stack Odoo Backup/Restore.

---

## 📦 Installation initiale

```bash
# 1. Cloner le repository
git clone https://github.com/your-org/odoo-infra.git
cd odoo-infra

# 2. Configurer .env
cp .env.example .env
nano .env  # Remplir vos valeurs

# 3. Lancer le setup (tout automatisé)
chmod +x scripts/*.sh
./scripts/setup.sh

# 4. Accéder à Odoo
# → http://localhost
# → Identifiants: admin / (valeur ODOO_ADMIN_PASSWORD)
```

**Durée** : ~10-15 minutes (dépend de votre connexion)

---

## 💾 Backup

### Sauvegarde manuelle

```bash
./scripts/backup.sh
```

**Résultat** :
- Archive compressée dans `./backup/`
- Uploadée automatiquement vers Cloudflare R2
- Vieux backups automatiquement supprimés (> 30 jours)

### Sauvegarde automatique

Configurée par `setup.sh` via cron (tous les 5 jours à 02:00)

Modifier dans `.env` :
```bash
BACKUP_SCHEDULE="0 2 */7 * *"  # Tous les 7 jours
BACKUP_RETENTION_DAYS=60        # Garder 2 mois
```

### Vérifier les backups

```bash
# Locaux
ls -lh backup/

# Sur R2
aws s3 ls s3://YOUR_BUCKET --recursive --region auto

# Voir les logs
tail -f /var/log/odoo-backup.log
```

---

## ↩️ Restauration

### Depuis backup local

```bash
./scripts/restore.sh odoo_backup_2025-12-01_02-00-00
```

### Depuis Cloudflare R2

```bash
./scripts/restore.sh odoo_backup_2025-12-01_02-00-00.tar.gz
# Télécharge automatiquement depuis R2
```

### Lister les backups disponibles

```bash
# Locaux
ls backup/

# R2
aws s3 ls s3://YOUR_BUCKET --recursive --region auto
```

---

## 🐋 Docker

### Statut

```bash
docker-compose ps
docker-compose logs -f
```

### Démarrage/Arrêt

```bash
docker-compose up -d       # Démarrer
docker-compose down         # Arrêter (garder les volumes)
docker-compose down -v      # Arrêter (supprimer TOUTES les données ⚠️)
docker-compose restart      # Redémarrer
```

### Logs

```bash
docker-compose logs odoo              # Logs Odoo
docker-compose logs postgres          # Logs PostgreSQL
docker-compose logs -f                # Suivi en temps réel (Ctrl+C pour quitter)
docker-compose logs --tail 50         # Dernières 50 lignes
```

### Base de données

```bash
# Accéder à PostgreSQL
docker-compose exec postgres psql -U odoo -d odoo

# Commandes SQL utiles
SELECT version();                    -- Version PostgreSQL
SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) FROM pg_database ORDER BY pg_database_size(pg_database.datname) DESC;  -- Taille des bases
VACUUM FULL;                         -- Optimiser la base
ANALYZE;                             -- Analyser les stats
```

---

## 🌐 Cloudflare R2

### Vérifier les credentials

```bash
# Voir les credentials configurés
cat ~/.aws/credentials
cat ~/.aws/config

# Tester la connexion
aws s3 ls s3://YOUR_BUCKET --region auto
```

### Reconfigurer R2

```bash
# Éditer .env avec les nouvelles credentials
nano .env

# Relancer setup (reconfigure AWS CLI)
./scripts/setup.sh
```

### Nettoyer les backups R2

```bash
# Lister
aws s3 ls s3://YOUR_BUCKET --recursive --region auto

# Supprimer un backup
aws s3 rm s3://YOUR_BUCKET/odoo_backup_2025-12-01_02-00-00.tar.gz --region auto

# Supprimer tous les backups (⚠️ !)
aws s3 rm s3://YOUR_BUCKET --recursive --region auto
```

---

## ⚙️ Configuration

### Éditer la configuration

```bash
# Variables d'environnement
nano .env

# Configuration Odoo
nano config/odoo.conf

# Docker Compose
nano docker-compose.yml
```

### Appliquer les modifications

```bash
docker-compose restart
# ou
docker-compose down
docker-compose up -d
```

---

## 🔍 Dépannage rapide

### Odoo ne répond pas

```bash
docker-compose restart odoo
docker-compose logs odoo
```

### PostgreSQL échoue

```bash
docker-compose exec postgres pg_isready
docker-compose logs postgres
docker-compose restart postgres
```

### Backup échoue

```bash
tail -f /var/log/odoo-backup.log        # Voir l'erreur
aws s3 ls s3://YOUR_BUCKET --region auto # Vérifier R2
./scripts/setup.sh                        # Reconfigurer
```

### R2 introuvable

```bash
cat ~/.aws/credentials
cat .env | grep CF_R2
aws s3 ls s3://YOUR_BUCKET --region auto
```

### Espace disque plein

```bash
df -h                                  # Voir l'espace
du -sh /var/lib/docker/volumes/       # Docker volumes
docker system prune -a                # Nettoyer
```

---

## 📊 Monitoring

### En production

```bash
# Dashboard global
docker stats

# Disque
df -h

# RAM/CPU
free -h
top -n 1 | head -20

# Backups
crontab -l
tail -f /var/log/odoo-backup.log

# Services
docker-compose ps
```

---

## 🔐 Sécurité

### Permissions

```bash
chmod 600 .env                    # Fichier .env protégé
chmod 700 scripts/                # Scripts exécutables seulement par owner
sudo chmod 600 /var/log/odoo-backup.log  # Logs protégés
```

### Credentials

```bash
# ❌ NE PAS commit .env
git rm --cached .env

# ✅ Vérifier que .gitignore l'exclude
cat .gitignore | grep .env

# ✅ Stocker en lieu sûr (backup chiffré)
gpg -c .env
```

---

## 📚 Documentation complète

- **Installation détaillée** : `DEPLOYMENT.md`
- **Dépannage** : `TROUBLESHOOTING.md`
- **Architecture** : `README.md`
- **Configuration avancée** : `.env.template`

---

## 💬 Commandes utiles

```bash
# Afficher la structure du projet
tree odoo-infra

# Vérifier la santé globale
./scripts/setup.sh  # (sans risque, valide juste la config)

# Voir toutes les variables chargées
source .env && printenv | grep -E "POSTGRES|ODOO|CF_"

# Compresser un backup manuel
tar czf backup-manual-$(date +%s).tar.gz \
  <(docker-compose exec -T postgres pg_dump -U odoo -F c odoo) \
  ./addons

# Migrer vers un nouveau serveur
git clone https://github.com/your-org/odoo-infra.git
cd odoo-infra && cp /path/to/old/.env . && ./scripts/setup.sh
```

---

## 🆘 Aide rapide

| Problème | Commande |
|----------|----------|
| Odoo lent | `docker-compose restart odoo` |
| PostgreSQL down | `docker-compose restart postgres` |
| Backup échoue | `tail -f /var/log/odoo-backup.log` |
| R2 introuvable | `./scripts/setup.sh` |
| Espace disque | `docker system prune -a` |
| Cron ne fonctionne pas | `crontab -l && tail -f /var/log/syslog` |

---

**Version** : 1.0.0 | **Dernière mise à jour** : Décembre 2025
