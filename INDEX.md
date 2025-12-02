# 📑 Index du Projet

Navigation complète de la stack Odoo Backup/Restore.

---

## 🗺️ Où aller selon votre besoin

### 🚀 Je suis nouveau

1. **Commencer ici** → `GETTING_STARTED.md` (5 minutes)
2. Puis → `DEPLOYMENT.md` (pas à pas)
3. Besoin d'aide ? → `TROUBLESHOOTING.md`

### ⚡ Je suis pressé

1. `quickstart.sh` (automatisé)
2. `QUICK_REFERENCE.md` (commandes)

### 📚 Je veux tout comprendre

1. `README.md` (vue d'ensemble)
2. `docker-compose.yml` (architecture Docker)
3. `PROJECT_STRUCTURE.md` (structure)
4. `.env.template` (configuration)

### 🔧 J'ai un problème

→ `TROUBLESHOOTING.md`

---

## 📄 Liste complète des fichiers

### Documentation

| Fichier | Taille | But |
|---------|--------|-----|
| `GETTING_STARTED.md` | 1 min | Démarrage ultra-rapide |
| `README.md` | 10 min | Documentation générale |
| `DEPLOYMENT.md` | 15 min | Guide complet de déploiement |
| `QUICK_REFERENCE.md` | 3 min | Référence des commandes |
| `TROUBLESHOOTING.md` | 15 min | Guide de dépannage |
| `PROJECT_STRUCTURE.md` | 5 min | Structure du projet |
| `INDEX.md` | Ce fichier | Navigation |

### Configuration

| Fichier | But |
|---------|-----|
| `.env.example` | Template minimal |
| `.env.template` | Template documenté |
| `.env` | Variables sensibles (À créer) |
| `.gitignore` | Fichiers ignorés |

### Docker

| Fichier | But |
|---------|-----|
| `docker-compose.yml` | Configuration Docker |
| `config/odoo.conf` | Configuration Odoo 17 |

### Scripts

| Fichier | Durée | But |
|---------|-------|-----|
| `scripts/setup.sh` | 5 min | Installation initiale |
| `scripts/backup.sh` | 5-30 min | Sauvegarde |
| `scripts/restore.sh` | 10-20 min | Restauration |
| `quickstart.sh` | 2 min | Démarrage guidé |

### Répertoires

| Répertoire | But |
|-----------|-----|
| `addons/` | Modules Odoo personnalisés |
| `backup/` | Sauvegardes locales |
| `config/` | Fichiers de configuration |
| `scripts/` | Scripts Bash |

---

## 🎯 Parcours d'apprentissage

### Niveau 1 : Débutant (30 min)

**Objectif** : Avoir Odoo qui tourne

1. `GETTING_STARTED.md` (5 min)
2. `quickstart.sh` (5 min)
3. Accéder à http://localhost (20 min d'attente)

**Résultat** : Odoo opérationnel ✅

---

### Niveau 2 : Intermédiaire (2 heures)

**Objectif** : Comprendre la stack

1. `GETTING_STARTED.md` (5 min)
2. `DEPLOYMENT.md` (30 min lecture)
3. `docker-compose.yml` (20 min)
4. `PROJECT_STRUCTURE.md` (15 min)
5. Faire un backup manuel (20 min)
6. Tester une restauration (30 min)

**Résultat** : Comprendre le flux complet ✅

---

### Niveau 3 : Avancé (1 jour)

**Objectif** : Maîtriser et customiser

1. Tous les niveaux précédents (2h30)
2. `.env.template` (20 min)
3. `config/odoo.conf` (30 min)
4. `docker-compose.yml` en détail (1h)
5. Lire tous les scripts (1h)
6. `TROUBLESHOOTING.md` (30 min)

**Résultat** : Pouvoir troubleshooter et customizer ✅

---

### Niveau 4 : Expert (2 jours)

**Objectif** : Production-ready

1. Tous les niveaux précédents (1 jour)
2. Déployer sur 3+ serveurs différents (4h)
3. Tester disaster recovery (4h)
4. Mettre en place monitoring (3h)
5. Créer sa documentation interne (2h)

**Résultat** : Cluster production stable ✅

---

## 📋 Commandes essentielles

### Installation

```bash
git clone https://github.com/your-org/odoo-infra.git
cd odoo-infra
cp .env.example .env
nano .env
./scripts/setup.sh
```

### Utilisation quotidienne

```bash
docker-compose ps
docker-compose logs -f
./scripts/backup.sh
./scripts/restore.sh <backup>
```

### Dépannage

```bash
tail -f /var/log/odoo-backup.log
docker-compose logs -f
aws s3 ls s3://YOUR_BUCKET --recursive --region auto
```

---

## 🎓 Topics détaillés

### Docker

- `docker-compose.yml` → Configuration
- `config/odoo.conf` → Configuration Odoo
- `DEPLOYMENT.md` → Installation
- `TROUBLESHOOTING.md` → Problèmes Docker

### Backup/Restore

- `scripts/backup.sh` → Sauvegarde
- `scripts/restore.sh` → Restauration
- `TROUBLESHOOTING.md` → Problèmes backup
- `QUICK_REFERENCE.md` → Commandes backup

### Sécurité

- `.env.template` → Secrets
- `.gitignore` → Fichiers sensibles
- `DEPLOYMENT.md` → Section sécurité
- `TROUBLESHOOTING.md` → Permissions

### Performance

- `docker-compose.yml` → Tuning
- `config/odoo.conf` → Tuning Odoo
- `TROUBLESHOOTING.md` → Performance issues

### Monitoring

- `README.md` → Section monitoring
- `DEPLOYMENT.md` → Monitoring post-déploiement
- `TROUBLESHOOTING.md` → Dépannage

---

## 🆘 Aide rapide

### "Je ne sais pas par où commencer"

→ `GETTING_STARTED.md`

### "J'ai une erreur"

→ `TROUBLESHOOTING.md` (chercher votre erreur)

### "Je veux comprendre comment ça marche"

→ `README.md` (architecture) + `docker-compose.yml` (config)

### "Je veux un guide pas à pas"

→ `DEPLOYMENT.md`

### "J'ai besoin d'une commande"

→ `QUICK_REFERENCE.md`

### "Je veux connaître la structure"

→ `PROJECT_STRUCTURE.md`

### "Je veux les détails de configuration"

→ `.env.template`

---

## 📊 Vue d'ensemble

```
┌─────────────────────────────────────────┐
│   ODOO BACKUP/RESTORE INFRASTRUCTURE    │
├─────────────────────────────────────────┤
│  📦 Docker                              │
│  ├─ Odoo 17                            │
│  └─ PostgreSQL 15                       │
├─────────────────────────────────────────┤
│  💾 Backup                              │
│  ├─ PostgreSQL dump                    │
│  ├─ Filestore archive                  │
│  └─ Addons archive                     │
├─────────────────────────────────────────┤
│  ☁️  Storage                            │
│  └─ Cloudflare R2 (S3)                 │
├─────────────────────────────────────────┤
│  🔄 Restore                             │
│  ├─ Télécharger depuis R2              │
│  └─ Restaurer complètement             │
└─────────────────────────────────────────┘
```

---

## 🔗 Liens rapides

**Documentation**
- [GETTING_STARTED.md](GETTING_STARTED.md) - Démarrage rapide
- [README.md](README.md) - Vue d'ensemble
- [DEPLOYMENT.md](DEPLOYMENT.md) - Installation complète
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Commandes
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Dépannage
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - Structure

**Configuration**
- [docker-compose.yml](docker-compose.yml) - Docker Compose
- [config/odoo.conf](config/odoo.conf) - Configuration Odoo
- [.env.example](.env.example) - Template simple
- [.env.template](.env.template) - Template documenté

**Scripts**
- [scripts/setup.sh](scripts/setup.sh) - Installation
- [scripts/backup.sh](scripts/backup.sh) - Sauvegarde
- [scripts/restore.sh](scripts/restore.sh) - Restauration
- [quickstart.sh](quickstart.sh) - Démarrage rapide

---

## ✅ Checklist de lecture

- [ ] `GETTING_STARTED.md` (5 min)
- [ ] `README.md` (10 min)
- [ ] `docker-compose.yml` (5 min)
- [ ] `DEPLOYMENT.md` (15 min)
- [ ] `QUICK_REFERENCE.md` (3 min)
- [ ] `TROUBLESHOOTING.md` (optionnel, 15 min)
- [ ] `PROJECT_STRUCTURE.md` (optionnel, 5 min)

**Temps total recommandé** : 45 minutes

---

## 🎯 Prochaines étapes

1. **Lire** `GETTING_STARTED.md`
2. **Exécuter** `./scripts/setup.sh`
3. **Accéder** http://localhost
4. **Tester** `./scripts/backup.sh`
5. **Vérifier** backups sur R2

---

**Bienvenue ! Bon déploiement 🚀**

---

*Dernière mise à jour : Décembre 2025*  
*Version : 1.0.0*
