# 🎯 Démarrage Rapide (5 min)

Le moyen le plus rapide de mettre en route Odoo avec backup/restore.

---

## ⚡ Étapes (5 minutes)

### 1️⃣ Cloner (1 min)

```bash
git clone https://github.com/your-org/odoo-infra.git
cd odoo-infra
```

### 2️⃣ Préparer (2 min)

```bash
# Copier le template
cp .env.example .env

# Éditer le fichier (remplir vos credentials R2)
nano .env
```

**À remplir absolument** :
- `POSTGRES_PASSWORD` → générer avec : `openssl rand -base64 32`
- `ODOO_ADMIN_PASSWORD` → générer avec : `openssl rand -base64 32`
- `CF_R2_ENDPOINT` → depuis Cloudflare
- `CF_R2_BUCKET` → depuis Cloudflare
- `CF_R2_ACCESS_KEY_ID` → depuis Cloudflare
- `CF_R2_SECRET_ACCESS_KEY` → depuis Cloudflare

### 3️⃣ Configurer Cloudflare R2 (2 min)

Si vous n'avez pas déjà un bucket R2 :

1. Aller à [dashboard.cloudflare.com](https://dash.cloudflare.com/)
2. **R2** → **Create bucket** → nommer `my-odoo-backups`
3. **R2** → **Settings** → **API Tokens** → **Create API Token**
   - Name: `Odoo Backup`
   - Permissions: `Admin`
4. Copier et ajouter à `.env` :
   - Account ID (dans l'URL)
   - Access Key ID
   - Secret Access Key

### 4️⃣ Lancer (30 sec)

```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

Le script va automatiquement :
- ✅ Installer Docker + AWS CLI
- ✅ Configurer AWS CLI pour R2
- ✅ Démarrer les conteneurs
- ✅ Installer le cron de backup
- ✅ Tester la connectivité

### 5️⃣ Accéder (30 sec)

Odoo accessible à :

```
http://localhost
```

**Identifiants** :
- Login : `admin`
- Password : (valeur de `ODOO_ADMIN_PASSWORD` dans `.env`)

---

## 🎓 Prochaines étapes

### Juste après l'installation

1. **Changer le mot de passe admin** (security)
   - Aller à Settings → Users → Admin
   - Changer le mot de passe

2. **Installer les modules** (selon votre besoin)
   - Apps
   - Rechercher + installer

3. **Configurer votre entreprise**
   - Settings → Companies → Your Company
   - Logo, adresse, etc.

### Avant production

1. **Tester un backup manual**
   ```bash
   ./scripts/backup.sh
   ```

2. **Vérifier que le backup est sur R2**
   ```bash
   aws s3 ls s3://YOUR_BUCKET --region auto
   ```

3. **Tester une restauration** (sur serveur de test)
   ```bash
   ./scripts/restore.sh <backup-name>
   ```

4. **Mettre en place le monitoring**
   - Alertes disque plein
   - Alertes backup échoué
   - Alertes Odoo down

---

## 📚 Documentation

| Besoin | Document |
|--------|----------|
| Vue d'ensemble | `README.md` |
| Installation complète | `DEPLOYMENT.md` |
| Troubleshooting | `TROUBLESHOOTING.md` |
| Référence rapide | `QUICK_REFERENCE.md` |
| Structure du projet | `PROJECT_STRUCTURE.md` |
| Configuration avancée | `.env.template` |

---

## 🆘 Si ça ne marche pas

### Docker n'est pas installé

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker
```

### .env mal rempli

```bash
cat .env | grep "your_"
# Si vous voyez des "your_", c'est pas bon remplissage

nano .env  # Remplir proprement
./scripts/setup.sh
```

### R2 introuvable

```bash
# Vérifier les credentials
cat ~/.aws/credentials
cat .env | grep CF_R2

# Tester la connexion
aws s3 ls s3://YOUR_BUCKET --region auto

# Si erreur, reconfigurer
./scripts/setup.sh
```

### Plus d'infos

Voir `TROUBLESHOOTING.md` pour tous les problèmes courants.

---

## 🚀 Cas d'usage courants

### Je veux juste essayer Odoo

```bash
./scripts/setup.sh
# Accéder à http://localhost
# Tester, explorer
```

**Durée** : 5-10 minutes

### Je veux une installation production-ready

```bash
# Faire tous les "Juste après l'installation"
# Faire tous les "Avant production"
# Monitorer pendant 1 semaine
```

**Durée** : 1-2 jours

### Je veux restaurer d'un ancien serveur

```bash
git clone https://github.com/your-org/odoo-infra.git
cd odoo-infra

cp /path/to/old/.env .  # Copier l'ancien .env
./scripts/setup.sh      # Setup neuf serveur
./scripts/restore.sh <backup-name>  # Restaurer
```

**Durée** : 10-15 minutes

### Je veux faire une sauvegarde manuelle

```bash
./scripts/backup.sh

# Voir le résultat
aws s3 ls s3://YOUR_BUCKET --recursive --region auto
```

**Durée** : 5-30 minutes (selon taille données)

### Je veux restaurer depuis un ancien backup

```bash
./scripts/restore.sh odoo_backup_2025-11-15_02-00-00

# Confirmer la destruction
# Attendre la restauration
```

**Durée** : 10-20 minutes (selon taille backup)

---

## 💡 Astuces

### Générer des mots de passe sécurisés

```bash
# Méthode 1 : OpenSSL
openssl rand -base64 32

# Méthode 2 : Python
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# Méthode 3 : /dev/urandom
head -c 32 /dev/urandom | base64
```

### Voir les logs en temps réel

```bash
tail -f /var/log/odoo-backup.log  # Backups
docker-compose logs -f             # Tous les services
docker-compose logs -f odoo        # Juste Odoo
```

### Arrêter proprement

```bash
docker-compose down  # Arrête mais garde les volumes
# ou
docker-compose stop  # Seulement arrête
```

### Nettoyer l'espace disque

```bash
docker system prune -a  # Nettoie les vieilles images
docker volume prune     # Nettoie les volumes orphelins
```

---

## ✅ Checklist de succès

- [ ] Odoo accessible
- [ ] Connexion admin fonctionne
- [ ] Premier backup réussi
- [ ] Backup visible sur R2
- [ ] Cron installé
- [ ] Restauration testée

---

## 📞 Support

Si vous êtes bloqué :

1. **Vérifier les logs** : `docker-compose logs -f`
2. **Consulter `TROUBLESHOOTING.md`**
3. **Créer une issue GitHub**

---

**Bienvenue dans votre stack Odoo backup/restore ! 🚀**
