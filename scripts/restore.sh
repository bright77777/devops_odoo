#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
BACKUP_DIR="$PROJECT_ROOT/backup"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

[ $# -eq 0 ] && { log_error "Usage: $0 <backup-name.tar.gz>"; ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || log_info "No backups found"; exit 1; }
[ -f "$ENV_FILE" ] || { log_error ".env not found"; exit 1; }

set -a; source "$ENV_FILE"; set +a

BACKUP_NAME="$1"
BACKUP_FILE="$BACKUP_DIR/$BACKUP_NAME"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo ""
echo "🔄 RESTORE ODOO"
echo "════════════════════════════════════════════"
echo ""

# Get container names
POSTGRES_CONTAINER=$(docker ps -q -f "ancestor=postgres:*" | head -1)
ODOO_CONTAINER=$(docker ps -q -f "ancestor=odoo:*" | head -1)

if [ -z "$POSTGRES_CONTAINER" ] || [ -z "$ODOO_CONTAINER" ]; then
    log_error "Docker containers not found. Run: docker-compose up -d"
    exit 1
fi

# Check/download backup
if [ ! -f "$BACKUP_FILE" ]; then
    if [ ! -z "$CF_R2_BUCKET" ] && [ "$CF_R2_BUCKET" != "your-bucket-name" ]; then
        log_info "Downloading from R2..."
        aws s3 cp "s3://${CF_R2_BUCKET}/${BACKUP_NAME}" "$BACKUP_FILE" --region auto || { log_error "Download failed"; exit 1; }
    else
        log_error "Backup not found: $BACKUP_FILE"
        exit 1
    fi
fi

SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
log_info "Using backup: $BACKUP_FILE ($SIZE)"

# Confirm
echo ""
echo "⚠️  WARNING: This will drop and recreate the database!"
echo ""
read -p "Continue? (yes/no): " -r CONFIRM
[[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]] && { log_error "Restore cancelled"; exit 1; }

# Extract
log_info "Extracting backup..."
tar xzf "$BACKUP_FILE" -C "$TEMP_DIR"
BACKUP_CONTENT_DIR=$(ls -d "$TEMP_DIR"/odoo_backup_* | head -1)
DUMP_FILE="$BACKUP_CONTENT_DIR/odoo_db.dump"
FILESTORE_TAR="$BACKUP_CONTENT_DIR/odoo_filestore.tar.gz"

[ ! -f "$DUMP_FILE" ] && { log_error "Database dump not found in backup"; exit 1; }

# Stop Odoo (keep PostgreSQL running)
log_info "Stopping Odoo..."
docker stop "$ODOO_CONTAINER" || true
sleep 2

# Drop and recreate database
log_info "Dropping database..."
docker exec -T "$POSTGRES_CONTAINER" dropdb -U "${POSTGRES_USER}" "${POSTGRES_DB}" 2>/dev/null || true

log_info "Creating database..."
docker exec -T "$POSTGRES_CONTAINER" createdb -U "${POSTGRES_USER}" "${POSTGRES_DB}"

# Restore database
log_info "Restoring database..."
docker exec -T "$POSTGRES_CONTAINER" pg_restore -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -v < "$DUMP_FILE"
log_info "Database restored ✓"

# Restore filestore
if [ -f "$FILESTORE_TAR" ]; then
    log_info "Restoring filestore..."
    docker exec -T "$ODOO_CONTAINER" rm -rf /var/lib/odoo/* 2>/dev/null || true
    tar xzf "$FILESTORE_TAR" -C "$TEMP_DIR/extract"
    docker cp "$TEMP_DIR/extract/"* "$ODOO_CONTAINER":/var/lib/odoo/ 2>/dev/null || log_info "No filestore data"
fi

# Start Odoo
log_info "Starting Odoo..."
docker start "$ODOO_CONTAINER"
sleep 5

echo ""
log_info "✅ Restore complete!"
echo ""
