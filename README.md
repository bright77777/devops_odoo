# Odoo Backup & Restore Infrastructure

Simple Docker-based backup and restore system for Odoo with Cloudflare R2 storage.

## 3 Scripts, 3 Steps

### 1. Setup (Initialize Everything)

```bash
bash scripts/setup.sh
```

This installs Docker, AWS CLI, configures R2, starts containers, and sets up cron.

### 2. Backup (Create Backup)

```bash
bash scripts/backup.sh
```

Creates a complete backup (database + filestore + addons) and uploads to R2 (if configured).

Backup file: `backup/odoo_backup_YYYY-MM-DD_HH-MM-SS.tar.gz`

### 3. Restore (Restore from Backup)

```bash
bash scripts/restore.sh odoo_backup_YYYY-MM-DD_HH-MM-SS.tar.gz
```

Restores everything from a backup archive. **Warning:** This will drop and recreate the database.

## Configuration

Create `.env` file from `.env.example`:

```bash
cp .env.example .env
```

Edit `.env` and set:
- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`
- `ODOO_ADMIN_PASSWORD`
- (Optional) `CF_R2_ENDPOINT`, `CF_R2_BUCKET`, `CF_R2_ACCESS_KEY`, `CF_R2_SECRET_KEY`

## How It Works

**setup.sh:**
- Installs Docker & Docker Compose plugin
- Installs AWS CLI for R2
- Configures AWS credentials
- Starts PostgreSQL + Odoo containers
- Sets up daily cron job

**backup.sh:**
- Detects Docker containers automatically
- Dumps PostgreSQL database
- Archives Odoo filestore and addons
- Compresses everything
- Uploads to R2 (if configured, non-blocking)
- Saves locally in `backup/` directory

**restore.sh:**
- Takes a backup archive name
- Extracts from local backup or downloads from R2
- Stops Odoo container
- Drops existing database and creates new one
- Restores database, filestore, and addons
- Restarts containers

## Docker Containers

The system auto-detects your containers:
- **PostgreSQL**: `docker ps -q -f "ancestor=postgres:*"`
- **Odoo**: `docker ps -q -f "ancestor=odoo:*"`

Works with any container names (odoo-web, odoo-app, etc.)

## Troubleshooting

**"Docker containers not found"**

Check if containers are running:
```bash
docker ps
docker compose ps
```

**"R2 upload failed"**

Local backup still succeeds. If R2 isn't configured, just use local backups.

**To view backups:**
```bash
ls -lh backup/
```

**To delete old backups:**
```bash
rm backup/odoo_backup_2025-01-01_*.tar.gz
```

## File Structure

```
devops_odoo/
├── docker-compose.yml
├── .env (create from .env.example)
├── .env.example
├── README.md
├── scripts/
│   ├── setup.sh
│   ├── backup.sh
│   └── restore.sh
└── backup/
    └── odoo_backup_*.tar.gz
```

## Environment Variables (.env)

```
POSTGRES_USER=odoo
POSTGRES_PASSWORD=your-password
POSTGRES_DB=odoo
ODOO_ADMIN_PASSWORD=your-admin-password

# Optional: Cloudflare R2
CF_R2_ENDPOINT=https://your-account.r2.cloudflarestorage.com
CF_R2_BUCKET=your-bucket
CF_R2_ACCESS_KEY=key
CF_R2_SECRET_KEY=secret

# Backup Schedule (cron format)
BACKUP_SCHEDULE=0 2 */5 * *
```

## Cron Automation

Automatic backups are installed by `setup.sh`.

View your cron job:
```bash
crontab -l
```

Disable backups:
```bash
crontab -e
# Comment out the odoo backup line
```

## Full Restore Example

```bash
# List available backups
ls -lh backup/

# Restore from specific backup
bash scripts/restore.sh odoo_backup_2025-01-15_10-30-45.tar.gz
```

That's it! Everything is simple by design.
