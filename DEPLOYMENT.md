# 📦 Guide de Déploiement Complet

Guide étape par étape pour déployer Odoo avec backup/restore sur un serveur Ubuntu neuf.

---

## 🎯 Objectif

Partir d'un serveur Ubuntu vierge et avoir une instance Odoo complètement opérationnelle avec backups automatiques en 15 minutes.

---

## 📋 Checklist de déploiement

### Phase 1 : Préparation du serveur (5 min)

**Sur le serveur :**

```bash
# 1. Mettre à jour le système
sudo apt-get update
sudo apt-get upgrade -y

# 2. Installer les dépendances de base
sudo apt-get install -y curl git wget

# 3. Créer un utilisateur dédié (optionnel)
sudo useradd -m -s /bin/bash odoo
sudo usermod -aG sudo odoo
sudo usermod -aG docker odoo

# 4. Se connecter en tant qu'utilisateur odoo
sudo su - odoo
```

---

### Phase 2 : Cloner le repository (2 min)

```bash
# 5. Cloner le projet
cd /opt
sudo git clone https://github.com/your-org/odoo-infra.git
sudo chown -R odoo:odoo /opt/odoo-infra
cd /opt/odoo-infra

# 6. Vérifier les fichiers
ls -la
# Vous devez voir:
# - docker-compose.yml
# - scripts/ (setup.sh, backup.sh, restore.sh)
# - config/ (odoo.conf)
# - addons/ (.gitkeep)
# - backup/ (.gitkeep)
# - .env.example
# - .gitignore
# - README.md
```

---

### Phase 3 : Configuration (3 min)

```bash
# 7. Copier le template .env
cp .env.example .env

# 8. Éditer avec vos valeurs (nano, vim, etc.)
nano .env
```

**Valeurs à remplir dans .env :**

| Variable | Valeur | Exemple |
|----------|--------|---------|
| `POSTGRES_PASSWORD` | Mot de passe fort 🔐 | `$(openssl rand -base64 32)` |
| `ODOO_ADMIN_PASSWORD` | Mot de passe fort 🔐 | `$(openssl rand -base64 32)` |
| `CF_R2_ENDPOINT` | Depuis Cloudflare R2 | `https://abc123.r2.cloudflarestorage.com` |
| `CF_R2_BUCKET` | Nom du bucket R2 | `my-company-odoo-backups` |
| `CF_R2_ACCESS_KEY_ID` | Depuis Cloudflare | `xxx` |
| `CF_R2_SECRET_ACCESS_KEY` | Depuis Cloudflare | `xxx` |

**Générer des mots de passe sécurisés :**

```bash
# PostgreSQL password
openssl rand -base64 32

# Odoo admin password
openssl rand -base64 32
```

---

### Phase 4 : Obtenir les credentials Cloudflare R2

**Sur le dashboard Cloudflare :**

1. Aller à [https://dash.cloudflare.com/](https://dash.cloudflare.com/)
2. Sélectionner votre compte
3. Aller à **R2** (dans la barre latérale)
4. Créer un bucket si nécessaire (ex: `my-company-odoo-backups`)
5. Aller à **R2** → **Settings** → **API Tokens**
6. Créer un nouveau token :
   - Nom : `Odoo Backup Token`
   - Permissions : **Admin** (lecture/écriture R2)
   - TTL : Illimité
7. Copier les informations :
   - **Access Key ID**
   - **Secret Access Key**
   - **Account ID** (visible dans l'URL R2)

**Remplir .env :**

```bash
CF_R2_ENDPOINT=https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
CF_R2_BUCKET=my-company-odoo-backups
CF_R2_ACCESS_KEY_ID=YOUR_ACCESS_KEY_ID
CF_R2_SECRET_ACCESS_KEY=YOUR_SECRET_ACCESS_KEY
```

---

### Phase 5 : Lancer le setup (5 min)

```bash
# 9. Rendre les scripts exécutables
chmod +x scripts/*.sh

# 10. Lancer le setup complet
./scripts/setup.sh
```

**Le setup va :**
- ✅ Installer Docker et Docker Compose
- ✅ Installer AWS CLI
- ✅ Configurer AWS CLI pour R2
- ✅ Télécharger les images Docker
- ✅ Démarrer les conteneurs
- ✅ Installer le cron automatique
- ✅ Vérifier la connectivité

**Durée estimée : 3-5 minutes**

---

### Phase 6 : Vérification (2 min)

```bash
# 11. Vérifier le statut des conteneurs
docker-compose ps

# Résultat attendu:
# CONTAINER ID   IMAGE                    STATUS              PORTS
# xxx            postgres:15-alpine       Up (healthy)        5432/tcp
# yyy            odoo:17                  Up (healthy)        0.0.0.0:80->8069/tcp

# 12. Vérifier les logs
docker-compose logs -f

# 13. Tester l'accès à Odoo
curl http://localhost
# Vous devriez avoir une page HTML (login page Odoo)
```

---

### Phase 7 : Configuration initiale Odoo (optionnel, 5 min)

```bash
# 14. Accéder à Odoo en navigateur
# http://YOUR_SERVER_IP
# ou http://localhost

# 15. Identifiants par défaut
# - Email: admin
# - Password: (valeur de ODOO_ADMIN_PASSWORD dans .env)

# 16. Premier login
# - Changer le mot de passe admin
# - Installer les modules essentiels
# - Configurer la base de données
```

---

## ✅ Checklist de vérification

Après déploiement, vérifier :

- [ ] Odoo accessible sur http://localhost
- [ ] Connexion possible avec identifiants admin
- [ ] PostgreSQL healthy (`docker-compose exec postgres pg_isready`)
- [ ] AWS CLI configuré (`aws s3 ls s3://bucket --region auto`)
- [ ] Cron job installé (`crontab -l | grep backup`)
- [ ] Dossier backup créé (`ls -la backup/`)
- [ ] Logs OK (`tail -f /var/log/odoo-backup.log`)

---

## 🧪 Tests de backup/restore

### Test 1 : Sauvegarde manuelle

```bash
./scripts/backup.sh

# Vous devriez voir:
# [INFO] ========== Starting Odoo Backup ==========
# [INFO] PostgreSQL database backed up ✓
# [INFO] Odoo filestore backed up ✓
# [INFO] Addons folder backed up ✓
# [INFO] Backup uploaded to R2 ✓
```

### Test 2 : Vérifier le backup sur R2

```bash
aws s3 ls s3://YOUR_BUCKET --recursive --region auto

# Vous devriez voir:
# 2025-12-01 15:23:45        123456789 odoo_backup_2025-12-01_15-23-45.tar.gz
```

### Test 3 : Restauration de test (optionnel)

Sur un **serveur de test uniquement** :

```bash
# Restaurer depuis le backup créé
./scripts/restore.sh odoo_backup_2025-12-01_15-23-45

# Confirmer la destruction
# Continue with restore? (yes/no): yes

# Le script devrait :
# - Télécharger depuis R2
# - Restaurer la base
# - Restaurer le filestore
# - Redémarrer les conteneurs
```

---

## 🔄 Restauration sur un nouveau serveur

### Scénario : EC2 supprimée, il faut recréer l'infra

```bash
# 1. Nouveau serveur Ubuntu vierge
# 2. Cloner le repository
git clone https://github.com/your-org/odoo-infra.git
cd odoo-infra

# 3. Copier et configurer .env (mêmes credentials que avant)
cp .env.example .env
nano .env

# 4. Lancer le setup
./scripts/setup.sh

# 5. Restaurer depuis le backup
./scripts/restore.sh odoo_backup_2025-12-01_15-23-45

# 6. L'Odoo devrait être identique à avant
```

**Durée estimée : 10-15 minutes**

---

## 🛑 Dépannage rapide

### Docker n'est pas installé

```bash
sudo apt-get install -y docker.io docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker
```

### Erreur : "Cannot connect to R2"

```bash
# Vérifier les credentials
cat ~/.aws/credentials

# Tester la connexion
aws s3 ls s3://YOUR_BUCKET --region auto

# Si erreur, reconfigurer
./scripts/setup.sh
```

### Odoo ne démarre pas

```bash
# Voir les logs
docker-compose logs odoo

# Augmenter le timeout
docker-compose exec postgres pg_isready

# Redémarrer
docker-compose restart
```

### Les conteneurs ne démarrent pas du tout

```bash
# Vérifier Docker
sudo systemctl status docker

# Nettoyer
docker-compose down
docker system prune -a

# Restart
sudo systemctl restart docker
docker-compose up -d
```

---

## 📊 Monitoring post-déploiement

### Commandes importantes

```bash
# Status des conteneurs
docker-compose ps

# Logs
docker-compose logs -f odoo
docker-compose logs -f postgres

# Ressources utilisées
docker stats

# Taille disque
du -sh /var/lib/docker/volumes/

# Backups
ls -lh backup/
aws s3 ls s3://YOUR_BUCKET --recursive --region auto
```

### Alertes à mettre en place

- 🔴 Conteneur arrêté
- 🔴 Backup échoué
- 🔴 Disque > 80% utilisé
- 🔴 PostgreSQL down
- 🟡 Backup > 48h sans succès

---

## 📚 Documentation

Pour plus de détails :

- **Setup détaillé** : `README.md`
- **Configuration** : `.env.example`
- **Scripts** : `scripts/`
- **Docker** : `docker-compose.yml`

---

## 🎓 Bonnes pratiques

### Avant production

- [ ] Tester sur un serveur de staging
- [ ] Documenter les identifiants
- [ ] Configurer les alertes
- [ ] Tester une restauration complète
- [ ] Vérifier la sauvegarde cron

### En production

- [ ] Monitorer les logs quotidiennement
- [ ] Vérifier les backups R2 hebdo
- [ ] Faire une restauration de test mensuellement
- [ ] Mettre à jour les modules Odoo régulièrement
- [ ] Archiver les logs tous les trimestres

---

## 🔐 Sécurité

### Access Control

```bash
# Permissions appropriées
chmod 600 .env
chmod 700 scripts/
sudo chmod 600 /var/log/odoo-backup.log
```

### Secrets

- [ ] Secrets stockés dans `.env` (jamais dans Git)
- [ ] Credentials R2 avec permissions minimales
- [ ] Mot de passe Odoo changé après 1er login
- [ ] SSH key only (pas de password SSH)

### Backup

- [ ] Backups chiffrés en transit (HTTPS)
- [ ] Backups stockés de manière sécurisée
- [ ] Rotation des credentials tous les 90 jours
- [ ] Test de restauration régulier

---

**Version** : 1.0.0  
**Date** : Décembre 2025  
**Durée totale** : ~15 minutes
