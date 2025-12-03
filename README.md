# 🚀 Odoo Infrastructure avec Backup R2

Infrastructure Docker pour Odoo 19 avec backup automatique vers Cloudflare R2.

## 📋 Prérequis

- Docker & Docker Compose
- AWS CLI (pour R2)
- Compte Cloudflare avec R2 activé

### Installation AWS CLI

```bash
# Ubuntu/Debian
sudo apt install awscli

# macOS
brew install awscli

# Vérification
aws --version
```

## 🏗️ Structure du Projet

```
odoo-infra/
├── docker-compose.yml      # Configuration Docker
├── .env                    # Variables d'environnement (à créer)
├── .env.example            # Template de configuration
├── .gitignore             # Fichiers à ignorer
├── README.md              # Cette documentation
├── addons/                # Modules Odoo personnalisés
├── config/
│   └── odoo.conf         # Configuration Odoo
├── backup/               # Backups locaux
└── scripts/
    ├── setup.sh          # Installation infrastructure
    ├── backup.sh         # Création backup
    └── restore.sh        # Restauration backup
```

## 🚀 Installation Rapide

### 1. Configuration Initiale

```bash
# Cloner le projet
git clone <votre-repo>
cd odoo-infra

# Créer .env depuis template
cp .env.example .env
nano .env  # Configurer les mots de passe et R2
```

### 2. Configuration Cloudflare R2

1. Aller sur https://dash.cloudflare.com
2. R2 → Créer un bucket `odoo-backups`
3. R2 API Tokens → Créer un token avec accès R/W
4. Copier les credentials dans `.env`:

```bash
CF_R2_ENDPOINT=https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
CF_R2_BUCKET=odoo-backups
CF_R2_ACCESS_KEY_ID=your_key_here
CF_R2_SECRET_ACCESS_KEY=your_secret_here
```

### 3. Démarrer l'Infrastructure

```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

L'installation va:
- Créer la structure de dossiers
- Générer la config Odoo
- Tester la connexion R2
- Démarrer les containers
- Vérifier que tout fonctionne

**Odoo sera accessible sur:** http://localhost:8069

## 💾 Gestion des Backups

### Créer un Backup

```bash
./scripts/backup.sh
```

Le backup inclut:
- ✅ Base de données PostgreSQL (format custom)
- ✅ Filestore Odoo (fichiers uploadés)
- ✅ Modules personnalisés (addons/)
- ✅ Métadonnées (date, taille, etc.)

Le backup est:
1. Créé localement dans `backup/`
2. Compressé en `.tar.gz`
3. Uploadé vers R2 (si configuré)
4. Les anciens backups sont nettoyés selon `BACKUP_RETENTION_DAYS`

### Lister les Backups Disponibles

```bash
./scripts/restore.sh list
```

### Restaurer un Backup

```bash
# Depuis R2
./scripts/restore.sh odoo_backup_2024-01-15_10-30-00

# Depuis un fichier local
./scripts/restore.sh backup/odoo_backup_2024-01-15_10-30-00.tar.gz
```

**⚠️ ATTENTION:** La restauration va remplacer toutes les données actuelles!

## 🔄 Backup Automatique

### Configuration avec Cron

```bash
# Éditer crontab
crontab -e

# Ajouter (backup tous les 5 jours à 2h du matin)
0 2 */5 * * /chemin/vers/odoo-infra/scripts/backup.sh >> /var/log/odoo-backup.log 2>&1
```

### Ou avec Systemd Timer

```bash
# /etc/systemd/system/odoo-backup.service
[Unit]
Description=Odoo Backup

[Service]
Type=oneshot
ExecStart=/chemin/vers/odoo-infra/scripts/backup.sh
User=your_user

# /etc/systemd/system/odoo-backup.timer
[Unit]
Description=Odoo Backup Timer

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target

# Activer
sudo systemctl enable odoo-backup.timer
sudo systemctl start odoo-backup.timer
```

## 🛠️ Commandes Utiles

### Docker

```bash
# Voir les logs
docker compose logs -f
docker compose logs -f odoo
docker compose logs -f db

# Arrêter
docker compose down

# Redémarrer
docker compose restart

# Reconstruire
docker compose up -d --build

# Nettoyer tout
docker compose down -v  # ⚠️ Supprime les données!
```

### Base de Données

```bash
# Se connecter à PostgreSQL
docker exec -it odoo-db psql -U odoo -d odoo

# Lister les bases
docker exec odoo-db psql -U odoo -c "\l"

# Taille de la base
docker exec odoo-db psql -U odoo -d odoo -c "SELECT pg_size_pretty(pg_database_size('odoo'));"
```

### Odoo

```bash
# Shell Odoo
docker exec -it odoo-app odoo shell -d odoo

# Mettre à jour un module
docker exec odoo-app odoo -d odoo -u nom_module

# Installer un module
docker exec odoo-app odoo -d odoo -i nom_module
```

## 🔒 Sécurité Production

### À Modifier Absolument

```bash
# Dans .env
POSTGRES_PASSWORD=un_mot_de_passe_fort_aleatoire_123!
ODOO_ADMIN_PASSWORD=un_autre_mot_de_passe_fort_456!

# Dans config/odoo.conf
admin_passwd = votre_master_password_unique
list_db = False  # Désactiver la liste des DB
```

### Reverse Proxy (Nginx)

```nginx
server {
    listen 80;
    server_name votre-domaine.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name votre-domaine.com;

    ssl_certificate /etc/ssl/certs/votre-cert.pem;
    ssl_certificate_key /etc/ssl/private/votre-key.pem;

    location / {
        proxy_pass http://localhost:8069;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /longpolling {
        proxy_pass http://localhost:8072;
    }
}
```

## 📊 Monitoring

### Vérifier l'État

```bash
# Santé des containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Utilisation ressources
docker stats

# Espace disque backups
du -sh backup/

# Espace R2
aws s3 ls s3://odoo-backups/ --endpoint-url $CF_R2_ENDPOINT --summarize --human-readable
```

## 🐛 Dépannage

### Odoo ne démarre pas

```bash
# Vérifier les logs
docker compose logs odoo

# Problème de DB?
docker compose logs db

# Redémarrer proprement
docker compose down
docker compose up -d
```

### Backup échoue

```bash
# Tester R2 manuellement
AWS_ACCESS_KEY_ID=$CF_R2_ACCESS_KEY_ID \
AWS_SECRET_ACCESS_KEY=$CF_R2_SECRET_ACCESS_KEY \
aws s3 ls s3://$CF_R2_BUCKET --endpoint-url $CF_R2_ENDPOINT

# Vérifier containers
docker ps | grep odoo
```

### Restauration échoue

```bash
# Vérifier intégrité backup
tar tzf backup/odoo_backup_XXX.tar.gz

# Espace disque?
df -h

# Forcer recréation DB
docker exec odoo-db psql -U odoo -c "DROP DATABASE odoo;"
docker exec odoo-db psql -U odoo -c "CREATE DATABASE odoo;"
```

## 📝 Notes Importantes

1. **Backups R2**: Les backups sont cryptés en transit (HTTPS) mais pas au repos. Activez le chiffrement R2 si nécessaire.

2. **Rétention**: Par défaut 30 jours. Les vieux backups sont supprimés automatiquement (local + R2).

3. **Performance**: Avec `workers=4`, prévoir minimum 2GB RAM pour Odoo.

4. **Modules**: Placez vos modules custom dans `addons/`. Ils seront backupés automatiquement.

5. **Config**: Modifiez `config/odoo.conf` selon vos besoins, puis `docker compose restart odoo`.

## 🔗 Liens Utiles

- [Documentation Odoo](https://www.odoo.com/documentation/19.0/)
- [Cloudflare R2](https://developers.cloudflare.com/r2/)
- [PostgreSQL](https://www.postgresql.org/docs/)

## 📄 Licence

Votre licence ici.

## 👤 Auteur

Votre nom