#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
BACKUP_DIR="$PROJECT_ROOT/backup"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

[ -f "$ENV_FILE" ] || { log_error ".env not found"; exit 1; }
set -a; source "$ENV_FILE"; set +a

mkdir -p "$BACKUP_DIR"

echo ""
echo "🔄 RESTORE ODOO"
echo "════════════════════════════════════════════"
echo ""

# List available backups
list_backups() {
    echo "Available backups:"
    echo ""
    echo "LOCAL:"
    if ls "$BACKUP_DIR"/*.tar.gz >/dev/null 2>&1; then
        ls -lh "$BACKUP_DIR"/*.tar.gz | awk '{print "  " $9 " (" $5 ")"}'
    else
        echo "  (none)"
    fi
    
    echo ""
    if [ ! -z "$CF_R2_BUCKET" ] && [ "$CF_R2_BUCKET" != "your-bucket-name" ]; then
        echo "CLOUDFLARE R2:"
        if AWS_ACCESS_KEY_ID="$CF_R2_ACCESS_KEY_ID" \
           AWS_SECRET_ACCESS_KEY="$CF_R2_SECRET_ACCESS_KEY" \
           aws s3 ls "s3://${CF_R2_BUCKET}/" --endpoint-url "$CF_R2_ENDPOINT" 2>/dev/null | grep "tar.gz"; then
            :
        else
            echo "  (none or connection failed)"
        fi
    fi
    echo ""
}

# Check arguments
if [ "$1" == "list" ]; then
    list_backups
    exit 0
fi

if [ -z "$1" ]; then
    log_error "Usage: ./restore.sh <backup_name_or_file>"
    echo ""
    echo "Examples:"
    echo "  ./restore.sh odoo_backup_2024-01-15_10-30-00        # From R2"
    echo "  ./restore.sh backup/odoo_backup_2024-01-15.tar.gz   # From local file"
    echo "  ./restore.sh list                                    # List available backups"
    echo ""
    list_backups
    exit 1
fi

BACKUP_INPUT="$1"
BACKUP_FILE=""

# Determine backup source
if [ -f "$BACKUP_INPUT" ]; then
    # Local file
    BACKUP_FILE="$BACKUP_INPUT"
    log_info "Using local backup: $BACKUP_FILE"
elif [ -f "$BACKUP_DIR/$BACKUP_INPUT" ]; then
    # File in backup directory
    BACKUP_FILE="$BACKUP_DIR/$BACKUP_INPUT"
    log_info "Using local backup: $BACKUP_FILE"
elif [ -f "$BACKUP_DIR/${BACKUP_INPUT}.tar.gz" ]; then
    # File without extension
    BACKUP_FILE="$BACKUP_DIR/${BACKUP_INPUT}.tar.gz"
    log_info "Using local backup: $BACKUP_FILE"
else
    # Try R2
    if [ -z "$CF_R2_BUCKET" ] || [ "$CF_R2_BUCKET" == "your-bucket-name" ]; then
        log_error "Backup not found locally and R2 not configured"
        exit 1
    fi
    
    log_step "Downloading from R2..."
    BACKUP_NAME="${BACKUP_INPUT%.tar.gz}"
    BACKUP_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
    
    if ! AWS_ACCESS_KEY_ID="$CF_R2_ACCESS_KEY_ID" \
         AWS_SECRET_ACCESS_KEY="$CF_R2_SECRET_ACCESS_KEY" \
         aws s3 cp "s3://${CF_R2_BUCKET}/${BACKUP_NAME}.tar.gz" "$BACKUP_FILE" \
         --endpoint-url "$CF_R2_ENDPOINT"; then
        log_error "Failed to download from R2"
        exit 1
    fi
    log_info "Downloaded from R2 ✓"
fi

# Confirm restore
echo ""
log_warn "⚠️  WARNING: This will REPLACE all current data!"
echo ""
read -p "Type 'YES' to continue: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    log_info "Restore cancelled"
    exit 0
fi

# Extract backup
TEMP_DIR="$BACKUP_DIR/restore_temp_$$"
mkdir -p "$TEMP_DIR"
log_step "Extracting backup..."
tar xzf "$BACKUP_FILE" -C "$TEMP_DIR"
BACKUP_CONTENT=$(ls "$TEMP_DIR")
BACKUP_PATH="$TEMP_DIR/$BACKUP_CONTENT"

if [ ! -f "$BACKUP_PATH/odoo_db.dump" ]; then
    log_error "Invalid backup: odoo_db.dump not found"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Use fixed container names from docker-compose.yml
POSTGRES_CONTAINER="odoo-db"
ODOO_CONTAINER="odoo-app"

# Check if containers exist and are running
if ! docker ps --format "{{.Names}}" | grep -q "^${POSTGRES_CONTAINER}$"; then
    log_error "Container $POSTGRES_CONTAINER not running"
    log_error "Start infrastructure first with: cd .. && docker compose up -d"
    rm -rf "$TEMP_DIR"
    exit 1
fi

if ! docker ps --format "{{.Names}}" | grep -q "^${ODOO_CONTAINER}$"; then
    log_error "Container $ODOO_CONTAINER not running"
    log_error "Start infrastructure first with: cd .. && docker compose up -d"
    rm -rf "$TEMP_DIR"
    exit 1
fi

log_info "Using containers: DB=$POSTGRES_CONTAINER, App=$ODOO_CONTAINER"

# Stop Odoo
log_step "Stopping Odoo..."
docker stop "$ODOO_CONTAINER" >/dev/null 2>&1 || true

# Drop and recreate database
log_step "Recreating database..."
docker exec "$POSTGRES_CONTAINER" psql -U "${POSTGRES_USER}" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${POSTGRES_DB}' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
docker exec "$POSTGRES_CONTAINER" psql -U "${POSTGRES_USER}" -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" >/dev/null 2>&1 || true
docker exec "$POSTGRES_CONTAINER" psql -U "${POSTGRES_USER}" -c "CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};" >/dev/null 2>&1

# Restore database
log_step "Restoring database..."
docker exec -i "$POSTGRES_CONTAINER" pg_restore -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --no-owner --no-acl < "$BACKUP_PATH/odoo_db.dump"
log_info "Database restored ✓"

# Restore filestore
log_step "Restoring filestore..."
if [ -f "$BACKUP_PATH/odoo_filestore.tar.gz" ]; then
    docker exec -i "$ODOO_CONTAINER" sh -c "rm -rf /var/lib/odoo/* 2>/dev/null; tar xzf - -C /var/lib/odoo" < "$BACKUP_PATH/odoo_filestore.tar.gz"
    log_info "Filestore restored ✓"
fi

# Restore addons
if [ -f "$BACKUP_PATH/odoo_addons.tar.gz" ]; then
    log_step "Restoring addons..."
    tar xzf "$BACKUP_PATH/odoo_addons.tar.gz" -C "$PROJECT_ROOT"
    log_info "Addons restored ✓"
fi

# Start Odoo
log_step "Starting Odoo..."
docker start "$ODOO_CONTAINER"

# Wait for Odoo
log_step "Waiting for Odoo..."
for i in {1..60}; do
    if curl -s http://localhost:8069/web >/dev/null 2>&1; then
        log_info "Odoo ready ✓"
        break
    fi
    sleep 2
done

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "════════════════════════════════════════════"
echo "✅ RESTORE COMPLETE"
echo "════════════════════════════════════════════"
echo ""
echo "Odoo is running at: http://localhost:8069"
echo ""
if [ -f "$BACKUP_PATH/backup.info" ]; then
    echo "Backup info:"
    cat "$BACKUP_PATH/backup.info" | grep -E "DATE|TIMESTAMP"
    echo ""
fi