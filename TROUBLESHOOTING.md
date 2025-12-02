# 🔧 Guide de Dépannage Complet

Solutions aux problèmes courants avec la stack Odoo Backup/Restore.

---

## 📋 Table des matières

1. [Problèmes d'installation](#problèmes-dinstallation)
2. [Problèmes Docker](#problèmes-docker)
3. [Problèmes de backup](#problèmes-de-backup)
4. [Problèmes de restauration](#problèmes-de-restauration)
5. [Problèmes de performance](#problèmes-de-performance)
6. [Problèmes de connexion R2](#problèmes-de-connexion-r2)
7. [Problèmes de cron](#problèmes-de-cron)

---

## 🚀 Problèmes d'installation

### Erreur: "sudo: apt-get: command not found"

**Symptôme**: Le script setup.sh échoue à installer les paquets

**Causes**:
- Vous n'êtes pas sur un système Ubuntu/Debian
- `sudo` n'est pas installé
- L'utilisateur n'a pas les permissions

**Solutions**:

```bash
# Option 1: Installer sudo
su - root
apt-get install -y sudo

# Option 2: Vérifier votre OS
cat /etc/os-release

# Option 3: Utiliser directement apt si vous êtes root
apt-get update
```

---

### Erreur: "Permission denied" lors de clone Git

**Symptôme**: `git clone` échoue avec "Permission denied"

**Causes**:
- Clé SSH non configurée
- Pas de permissions sur le répertoire cible

**Solutions**:

```bash
# Option 1: Utiliser HTTPS au lieu de SSH
git clone https://github.com/your-org/odoo-infra.git

# Option 2: Configurer SSH
ssh-keygen -t ed25519 -C "your_email@example.com"
ssh-add ~/.ssh/id_ed25519
# Ajouter la clé publique à GitHub Settings → SSH Keys

# Option 3: Vérifier les permissions
ls -la /opt/
# Devrait avoir drwxrwxr-x ou similaire
```

---

### Erreur: ".env file not found"

**Symptôme**: "❌ .env file not found at /path/to/.env"

**Causes**:
- Le fichier `.env` n'a pas été créé
- Mauvais chemin relatif

**Solutions**:

```bash
# Vérifier la structure
ls -la

# Créer le fichier
cp .env.example .env

# Vérifier que c'est au bon endroit
pwd
ls .env

# Exécuter le script depuis le bon répertoire
cd /path/to/odoo-infra
./scripts/setup.sh
```

---

## 🐋 Problèmes Docker

### Erreur: "Cannot connect to Docker daemon"

**Symptôme**: `docker: Cannot connect to Docker daemon`

**Causes**:
- Docker n'est pas installé
- Docker daemon n'est pas actif
- Permissions utilisateur insuffisantes

**Solutions**:

```bash
# Vérifier que Docker est installé
docker --version

# Si non installé:
sudo apt-get install -y docker.io

# Vérifier que Docker est actif
sudo systemctl status docker

# Si non actif:
sudo systemctl start docker
sudo systemctl enable docker

# Ajouter l'utilisateur au groupe docker
sudo usermod -aG docker $USER

# Appliquer les permissions (sans redémarrage)
newgrp docker

# Tester
docker ps
```

---

### Les conteneurs ne démarrent pas

**Symptôme**: `docker-compose ps` montre "Restarting" ou "Exit"

**Solutions**:

```bash
# Voir les logs détaillés
docker-compose logs -f

# Arrêter tous les conteneurs
docker-compose down

# Nettoyer les images
docker system prune -a

# Télécharger les images fraîches
docker-compose pull

# Redémarrer
docker-compose up -d

# Vérifier le statut
docker-compose ps
```

---

### PostgreSQL ne démarre pas

**Symptôme**: PostgreSQL container "Restarting" ou "Exit"

**Causes**:
- Volume endommagé
- Permissions incorrectes
- Ressources insuffisantes

**Solutions**:

```bash
# Voir les logs PostgreSQL
docker-compose logs postgres

# Vérifier les ressources disponibles
docker stats

# Si le volume est corrompu:
docker-compose down -v  # ⚠️ Supprime les données!
docker-compose up -d

# Vérifier que PostgreSQL fonctionne
docker-compose exec postgres psql -U odoo -d odoo -c "SELECT version();"

# Vérifier la santé du service
docker-compose exec postgres pg_isready
```

---

### Odoo reste en "Starting"

**Symptôme**: Odoo ne démarre jamais, reste en "Starting" indéfiniment

**Causes**:
- Attente de PostgreSQL
- Pas assez de RAM
- Problème de configuration

**Solutions**:

```bash
# Augmenter le timeout
sleep 30  # attendre plus longtemps

# Vérifier que PostgreSQL est healthy
docker-compose exec postgres pg_isready
# Doit retourner "accepting connections"

# Voir les logs Odoo
docker-compose logs -f odoo

# Vérifier la RAM disponible
free -h

# Si RAM insuffisante, augmenter ODOO_WORKERS dans .env
# ODOO_WORKERS=2  # au lieu de 4

# Redémarrer
docker-compose restart odoo
```

---

## 💾 Problèmes de backup

### Erreur: "Cannot find PostgreSQL container"

**Symptôme**: Backup script échoue avec "No such container"

**Causes**:
- Conteneur PostgreSQL arrêté
- Nom du conteneur incorrect

**Solutions**:

```bash
# Vérifier que PostgreSQL est en cours d'exécution
docker-compose ps

# Si pas en cours d'exécution:
docker-compose start postgres

# Attendre la santé
docker-compose exec postgres pg_isready

# Relancer le backup
./scripts/backup.sh
```

---

### Erreur: "pg_dump: error"

**Symptôme**: Backup échoue avec erreur PostgreSQL

**Causes**:
- Base de données corrompue
- Permissions insuffisantes
- Espace disque insuffisant

**Solutions**:

```bash
# Vérifier l'espace disque
df -h

# Vérifier la base de données
docker-compose exec postgres psql -U odoo -d odoo -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) FROM pg_database ORDER BY pg_database_size(pg_database.datname) DESC;"

# Tester le dump manuellement
docker-compose exec -T postgres pg_dump -U odoo -F c odoo > /tmp/test.dump

# Si ça fonctionne, l'erreur est peut-être ailleurs
ls -lh /tmp/test.dump
```

---

### Erreur: "Docker volume not found"

**Symptôme**: "tar: cannot open /var/lib/odoo: No such file"

**Causes**:
- Volume Docker mal configuré
- Conteneur n'a pas de volume monté

**Solutions**:

```bash
# Vérifier les volumes
docker-compose exec odoo df -h

# Vérifier le point de montage
docker-compose exec odoo ls -la /var/lib/odoo

# Si vide, il n'y a pas de données Odoo à backup
# C'est normal au premier backup

# Vérifier la config docker-compose.yml
grep -A5 "odoo-web-data" docker-compose.yml

# Recréer les volumes si nécessaire
docker-compose down -v
docker-compose up -d
```

---

### Erreur: "AWS S3 upload failed"

**Symptôme**: Backup échoue à l'upload "Unable to locate credentials"

**Causes**:
- Credentials R2 mal configurés
- AWS CLI non configuré
- Chemin ~/.aws/credentials incorrect

**Solutions**:

```bash
# Vérifier les credentials
cat ~/.aws/credentials

# Vérifier la configuration
cat ~/.aws/config

# Vérifier que les credentials sont chargés
aws s3 ls s3://YOUR_BUCKET --region auto

# Si erreur "NoSuchBucket":
#   - Vérifier que le bucket existe
#   - Vérifier le nom du bucket dans .env

# Si erreur "InvalidAccessKeyId":
#   - Vérifier que CF_R2_ACCESS_KEY_ID est correct
#   - Régénérer le token depuis Cloudflare

# Reconfigurer AWS CLI
./scripts/setup.sh
```

---

### Backup est trop gros

**Symptôme**: Le backup fait plus de 1 GB

**Causes**:
- Trop de données
- Compression insuffisante
- Anciens fichiers non supprimés

**Solutions**:

```bash
# Voir la taille du backup
du -sh backup/

# Voir le contenu
tar -tzf backup/*.tar.gz | head -20

# Nettoyer les vieilles données dans Odoo
# (Via l'interface Odoo)

# Augmenter la compression
# (Éditer backup.sh pour utiliser `tar cjf` au lieu de `tar czf`)

# Réduire la rétention
# Éditer .env: BACKUP_RETENTION_DAYS=14

# Archiver les anciens backups
tar czf backups-archive-2025-01.tar.gz backup/*.tar.gz
rm backup/*.tar.gz
```

---

## ↩️ Problèmes de restauration

### Erreur: "Backup file not found"

**Symptôme**: "Could not find backup locally or on R2"

**Solutions**:

```bash
# Lister les backups locaux
ls -lh backup/

# Lister les backups R2
aws s3 ls s3://YOUR_BUCKET --recursive --region auto

# Essayer avec chemin complet
./scripts/restore.sh /absolute/path/to/backup.tar.gz

# Essayer sans l'extension
./scripts/restore.sh odoo_backup_2025-12-01_02-00-00
```

---

### Erreur: "Invalid backup format"

**Symptôme**: "could not find backup directory"

**Causes**:
- Fichier corrompu
- Mauvais format d'archive
- Extraction échouée

**Solutions**:

```bash
# Vérifier l'intégrité du backup
tar -tzf backup/*.tar.gz > /dev/null

# Si erreur: le backup est corrompu
# Récupérer depuis R2
aws s3 cp s3://YOUR_BUCKET/odoo_backup_XXXX.tar.gz ./

# Vérifier le contenu
tar -tzf odoo_backup_XXXX.tar.gz | head -20

# Doit contenir: odoo_backup_*/odoo_db_*.dump
```

---

### Erreur: "Database restore failed"

**Symptôme**: La restauration de la base échoue

**Solutions**:

```bash
# Vérifier que PostgreSQL est healthy
docker-compose exec postgres pg_isready

# Vérifier que la base existe
docker-compose exec postgres psql -U odoo -l

# Tester une restauration manuelle
docker-compose exec -T postgres pg_restore -U odoo -d odoo < /path/to/dump.dump

# Si toujours une erreur, le dump peut être corrompu
# Essayer un autre backup

./scripts/restore.sh <older-backup>
```

---

### Restauration est très lente

**Symptôme**: La restauration prend plus d'1 heure

**Solutions**:

```bash
# Vérifier les ressources
docker stats postgres

# Augmenter le timeout
# Éditer restore.sh pour augmenter max_parallel_restore_jobs

# Vérifier la taille du dump
du -sh backup/*.dump

# Restaurer le dump dans PostgreSQL directement
time docker-compose exec -T postgres pg_restore -U odoo -d odoo < /path/to/dump

# Si ça prend du temps, attendre
# C'est normal pour les gros backups
```

---

## ⚡ Problèmes de performance

### Odoo est lent

**Symptôme**: L'interface Odoo est très lente

**Solutions**:

```bash
# Vérifier les ressources disponibles
docker stats odoo-web

# Vérifier la RAM disponible
free -h

# Augmenter le nombre de workers
# Éditer .env: ODOO_WORKERS=8
docker-compose restart odoo

# Vérifier les logs
docker-compose logs odoo

# Vérifier la base de données
docker-compose exec postgres psql -U odoo -d odoo -c "SELECT pg_size_pretty(pg_database_size('odoo'));"

# Nettoyer les logs PostgreSQL
docker-compose exec postgres vacuumdb -U odoo -d odoo -z
```

---

### PostgreSQL consomme beaucoup de RAM

**Symptôme**: PostgreSQL utilise plus de 2 GB de RAM

**Solutions**:

```bash
# Vérifier les processus PostgreSQL
docker-compose exec postgres psql -U odoo -d odoo -c "SELECT * FROM pg_stat_activity;"

# Killer les requêtes longues
docker-compose exec postgres psql -U odoo -d odoo -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid != pg_backend_pid();"

# Optimiser PostgreSQL
docker-compose exec postgres psql -U odoo -d odoo -c "VACUUM FULL;"
docker-compose exec postgres psql -U odoo -d odoo -c "ANALYZE;"

# Réduire la mémoire PostgreSQL dans docker-compose.yml
# Ajouter shared_buffers=256MB
```

---

## 🌐 Problèmes de connexion R2

### Erreur: "Unable to locate credentials"

**Symptôme**: AWS CLI ne trouve pas les credentials

**Causes**:
- ~/.aws/credentials n'existe pas
- Variables d'environnement pas définies
- Permissions insuffisantes

**Solutions**:

```bash
# Vérifier les credentials
ls -la ~/.aws/

# Si fichier n'existe pas, le créer
mkdir -p ~/.aws
touch ~/.aws/credentials

# Remplir manuellement
cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
EOF

# Permissions
chmod 600 ~/.aws/credentials

# Vérifier
aws s3 ls s3://YOUR_BUCKET --region auto
```

---

### Erreur: "InvalidAccessKeyId"

**Symptôme**: AWS CLI retourne "InvalidAccessKeyId"

**Solutions**:

```bash
# Vérifier la clé
cat ~/.aws/credentials

# Vérifier qu'elle correspond à .env
cat .env | grep CF_R2_ACCESS_KEY_ID

# Régénérer la clé depuis Cloudflare
# 1. Dashboard Cloudflare → R2
# 2. Settings → API Tokens
# 3. Créer un nouveau token
# 4. Mettre à jour .env
# 5. Relancer setup.sh
```

---

### Erreur: "NoSuchBucket"

**Symptôme**: "The specified bucket does not exist"

**Solutions**:

```bash
# Vérifier le nom du bucket
cat .env | grep CF_R2_BUCKET

# Lister tous les buckets
aws s3 ls --region auto

# Créer le bucket depuis Cloudflare Dashboard
# R2 → Create Bucket

# Vérifier que le bucket est accessible
aws s3 ls s3://YOUR_EXACT_BUCKET_NAME --region auto
```

---

### Erreur: "Access Denied" ou "RequestLimitExceeded"

**Symptôme**: Accès refusé ou limité

**Solutions**:

```bash
# Vérifier les permissions du token R2
# Dashboard Cloudflare → R2 → Settings → API Tokens
# Le token doit avoir permissions "Admin" pour R2

# Vérifier le rate limiting
# Attendre quelques minutes et réessayer

# Créer un nouveau token avec permissions complètes
# 1. Dashboard Cloudflare
# 2. R2 → Settings → API Tokens
# 3. Create API Token → Admin
# 4. Copier les credentials
# 5. Mettre à jour .env et reconfigurer

./scripts/setup.sh
```

---

## 🕐 Problèmes de cron

### Le backup automatique ne s'exécute pas

**Symptôme**: Pas de sauvegarde automatique

**Solutions**:

```bash
# Vérifier que le cron est installé
crontab -l

# Si vide, installer manuellement
(crontab -l 2>/dev/null || true; echo "0 2 */5 * * /path/to/odoo-infra/scripts/backup.sh >> /var/log/odoo-backup.log 2>&1") | crontab -

# Vérifier la syntaxe du cron
crontab -l

# Vérifier les logs du cron
tail -f /var/log/syslog | grep CRON

# Tester le cron manuellement
/path/to/scripts/backup.sh

# Vérifier les logs du backup
tail -f /var/log/odoo-backup.log
```

---

### Le log du cron est vide

**Symptôme**: /var/log/odoo-backup.log est vide ou n'existe pas

**Solutions**:

```bash
# Créer le fichier de log
sudo touch /var/log/odoo-backup.log
sudo chmod 666 /var/log/odoo-backup.log

# Vérifier les permissions
ls -la /var/log/odoo-backup.log

# Tester manuellement
./scripts/backup.sh >> /var/log/odoo-backup.log 2>&1

# Vérifier le log
cat /var/log/odoo-backup.log
```

---

### Le cron s'exécute mais échoue silencieusement

**Symptôme**: Pas de log, pas de backup créé

**Solutions**:

```bash
# Ajouter du logging
# Éditer crontab -e et remplacer par:
0 2 */5 * * bash -c 'cd /path/to/odoo-infra && ./scripts/backup.sh 2>&1' >> /var/log/odoo-backup.log

# Vérifier la variable PATH dans cron
# Ajouter en début du cron:
*/5 * * * * export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin && /path/to/scripts/backup.sh

# Tester directement le cron
env -i HOME=$HOME /usr/bin/crontab -l
env -i HOME=$HOME bash -c '/path/to/scripts/backup.sh'

# Vérifier les variables d'environnement
env -i HOME=$HOME bash -c 'source /path/to/.env && aws s3 ls s3://YOUR_BUCKET --region auto'
```

---

## 🆘 Demander de l'aide

Si le problème persiste :

1. **Rassembler les logs**:
   ```bash
   docker-compose logs > logs.txt
   cat /var/log/odoo-backup.log >> logs.txt
   ./scripts/setup.sh 2>&1 | tee setup-debug.log
   ```

2. **Vérifier l'espace disque**:
   ```bash
   df -h
   du -sh /var/lib/docker/volumes/
   ```

3. **Vérifier les ressources**:
   ```bash
   free -h
   docker stats
   ```

4. **Ouvrir une issue GitHub** avec :
   - Description du problème
   - Logs (sans données sensibles)
   - Commandes exactes exécutées
   - Configuration (système d'exploitation, Docker version, etc.)

---

**Version** : 1.0.0  
**Date** : Décembre 2025
