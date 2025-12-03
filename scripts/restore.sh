#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
BACKUP_DIR="$PROJECT_ROOT/backup"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

[ -f "$ENV_FILE" ] || { log_error ".env not found"; exit 1; }
set -a; source "$ENV_FILE"; set +a

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="odoo_backup_${TIMESTAMP}"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
mkdir -p "$BACKUP_PATH"

echo ""
echo "🔄 BACKUP ODOO"
echo "════════════════════════════════════════════"
echo ""

# Find containers
POSTGRES_CONTAINER=$(docker ps --format "{{.Names}}" -f "ancestor=postgres:15" 2>/dev/null | head -1)
ODOO_CONTAINER=$(docker ps --format "{{.Names}}" -f "ancestor=odoo:19.0" 2>/dev/null | head -1)

if [ -z "$POSTGRES_CONTAINER" ]; then
    POSTGRES_CONTAINER="odoo-db"
fi
if [ -z "$ODOO_CONTAINER" ]; then
    ODOO_CONTAINER="odoo-app"
fi

if ! docker ps --format "{{.Names}}" | grep -q "^${POSTGRES_CONTAINER}$"; then
    log_error "Container $POSTGRES_CONTAINER not running"
    log_error ""
    log_error "Available containers:"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    exit 1
fi

log_info "Using containers: DB=$POSTGRES_CONTAINER, App=$ODOO_CONTAINER"

# Backup database
log_step "Backing up database..."
docker exec "$POSTGRES_CONTAINER" pg_dump -U "${POSTGRES_USER}" -F c "${POSTGRES_DB}" > "$BACKUP_PATH/odoo_db.dump"
DB_SIZE=$(du -h "$BACKUP_PATH/odoo_db.dump" | cut -f1)
log_info "Database backed up ($DB_SIZE)"

# Backup filestore
log_step "Backing up filestore..."
if docker exec "$ODOO_CONTAINER" test -d /var/lib/odoo 2>/dev/null; then
    docker exec "$ODOO_CONTAINER" tar czf - -C /var/lib/odoo . 2>/dev/null > "$BACKUP_PATH/odoo_filestore.tar.gz" || {
        log_info "No filestore data"
        tar czf "$BACKUP_PATH/odoo_filestore.tar.gz" -C /tmp --files-from=/dev/null 2>/dev/null
    }
    FS_SIZE=$(du -h "$BACKUP_PATH/odoo_filestore.tar.gz" | cut -f1)
    log_info "Filestore backed up ($FS_SIZE)"
else
    tar czf "$BACKUP_PATH/odoo_filestore.tar.gz" -C /tmp --files-from=/dev/null 2>/dev/null
    log_info "No filestore found"
fi

# Backup addons
log_step "Backing up addons..."
if [ -d "$PROJECT_ROOT/addons" ] && [ "$(ls -A $PROJECT_ROOT/addons 2>/dev/null)" ]; then
    tar czf "$BACKUP_PATH/odoo_addons.tar.gz" -C "$PROJECT_ROOT" addons
    ADDONS_SIZE=$(du -h "$BACKUP_PATH/odoo_addons.tar.gz" | cut -f1)
    log_info "Addons backed up ($ADDONS_SIZE)"
else
    tar czf "$BACKUP_PATH/odoo_addons.tar.gz" -C /tmp --files-from=/dev/null 2>/dev/null
    log_info "No custom addons"
fi

# Create metadata
cat > "$BACKUP_PATH/backup.info" <<EOF
BACKUP_NAME=$BACKUP_NAME
TIMESTAMP=$TIMESTAMP
DATE=$(date)
DATABASE=odoo_db.dump
FILESTORE=odoo_filestore.tar.gz
ADDONS=odoo_addons.tar.gz
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_DB=${POSTGRES_DB}
EOF

# Compress
log_step "Compressing backup..."
BACKUP_ARCHIVE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
tar czf "$BACKUP_ARCHIVE" -C "$BACKUP_DIR" "$BACKUP_NAME"
rm -rf "$BACKUP_PATH"

ARCHIVE_SIZE=$(du -h "$BACKUP_ARCHIVE" | cut -f1)
log_info "Backup compressed: $ARCHIVE_SIZE"

# Upload to R2
if [ ! -z "$CF_R2_BUCKET" ] && [ "$CF_R2_BUCKET" != "your-bucket-name" ]; then
    log_step "Uploading to Cloudflare R2..."
    
    if AWS_ACCESS_KEY_ID="$CF_R2_ACCESS_KEY_ID" \
       AWS_SECRET_ACCESS_KEY="$CF_R2_SECRET_ACCESS_KEY" \
       aws s3 cp "$BACKUP_ARCHIVE" "s3://${CF_R2_BUCKET}/${BACKUP_NAME}.tar.gz" \
       --endpoint-url "$CF_R2_ENDPOINT" 2>&1; then
        log_info "Uploaded to R2 ✓"
    else
        log_error "R2 upload failed (backup still available locally)"
    fi
else
    log_info "R2 not configured - backup kept locally only"
fi

# Cleanup old backups
if [ ! -z "$BACKUP_RETENTION_DAYS" ] && [ "$BACKUP_RETENTION_DAYS" -gt 0 ]; then
    log_step "Cleaning old local backups (>${BACKUP_RETENTION_DAYS} days)..."
    find "$BACKUP_DIR" -name "odoo_backup_*.tar.gz" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true
    
    if [ ! -z "$CF_R2_BUCKET" ] && [ "$CF_R2_BUCKET" != "your-bucket-name" ]; then
        log_step "Cleaning old R2 backups (>${BACKUP_RETENTION_DAYS} days)..."
        CUTOFF_DATE=$(date -d "${BACKUP_RETENTION_DAYS} days ago" +%Y-%m-%d 2>/dev/null || date -v-${BACKUP_RETENTION_DAYS}d +%Y-%m-%d 2>/dev/null)
        
        AWS_ACCESS_KEY_ID="$CF_R2_ACCESS_KEY_ID" \
        AWS_SECRET_ACCESS_KEY="$CF_R2_SECRET_ACCESS_KEY" \
        aws s3 ls "s3://${CF_R2_BUCKET}/" --endpoint-url "$CF_R2_ENDPOINT" 2>/dev/null | \
        grep "odoo_backup_" | \
        while read -r line; do
            FILENAME=$(echo "$line" | awk '{print $4}')
            FILE_DATE=$(echo "$FILENAME" | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
            if [ ! -z "$FILE_DATE" ] && [ "$FILE_DATE" \< "$CUTOFF_DATE" ]; then
                AWS_ACCESS_KEY_ID="$CF_R2_ACCESS_KEY_ID" \
                AWS_SECRET_ACCESS_KEY="$CF_R2_SECRET_ACCESS_KEY" \
                aws s3 rm "s3://${CF_R2_BUCKET}/${FILENAME}" --endpoint-url "$CF_R2_ENDPOINT" 2>/dev/null || true
            fi
        done
    fi
fi

echo ""
echo "════════════════════════════════════════════"
echo "✅ BACKUP COMPLETE"
echo "════════════════════════════════════════════"
echo ""
echo "Backup: $BACKUP_ARCHIVE"
echo "Size: $ARCHIVE_SIZE"
echo ""
echo "To restore:"
echo "  ./scripts/restore.sh $BACKUP_NAME"
echo ""