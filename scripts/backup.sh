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

# Get container names - try multiple ways
POSTGRES_CONTAINER=""
ODOO_CONTAINER=""

# Method 1: By image name
POSTGRES_CONTAINER=$(docker ps --format "{{.Names}}" -f "ancestor=postgres:15*" 2>/dev/null | head -1)
ODOO_CONTAINER=$(docker ps --format "{{.Names}}" -f "ancestor=odoo:*" 2>/dev/null | head -1)

# Method 2: Search by image name pattern in all containers
if [ -z "$POSTGRES_CONTAINER" ]; then
    POSTGRES_CONTAINER=$(docker ps --format "table {{.Names}}\t{{.Image}}" | grep -i postgres | awk '{print $1}' | head -1)
fi

if [ -z "$ODOO_CONTAINER" ]; then
    ODOO_CONTAINER=$(docker ps --format "table {{.Names}}\t{{.Image}}" | grep -i "^odoo" | awk '{print $1}' | head -1)
fi

# Method 3: Common container names
if [ -z "$POSTGRES_CONTAINER" ]; then
    for name in odoo-db odoo-postgres postgres-odoo postgres; do
        if docker ps --format "{{.Names}}" | grep -q "^${name}$"; then
            POSTGRES_CONTAINER="$name"
            break
        fi
    done
fi

if [ -z "$ODOO_CONTAINER" ]; then
    for name in odoo-app odoo-web odoo; do
        if docker ps --format "{{.Names}}" | grep -q "^${name}$"; then
            ODOO_CONTAINER="$name"
            break
        fi
    done
fi

if [ -z "$POSTGRES_CONTAINER" ] || [ -z "$ODOO_CONTAINER" ]; then
    log_error "Could not find Docker containers"
    log_error "PostgreSQL: $POSTGRES_CONTAINER"
    log_error "Odoo: $ODOO_CONTAINER"
    log_error ""
    log_error "Available containers:"
    docker ps --format "table {{.Names}}\t{{.Image}}"
    exit 1
fi

log_info "Found containers: PostgreSQL=$POSTGRES_CONTAINER, Odoo=$ODOO_CONTAINER"

# Backup PostgreSQL
log_info "Backing up database..."
docker exec "$POSTGRES_CONTAINER" pg_dump -U "${POSTGRES_USER}" -F c "${POSTGRES_DB}" > "$BACKUP_PATH/odoo_db.dump"
SIZE=$(du -h "$BACKUP_PATH/odoo_db.dump" | cut -f1)
log_info "Database backed up ($SIZE)"

# Backup filestore
log_info "Backing up filestore..."
docker exec "$ODOO_CONTAINER" tar czf - -C /var/lib/odoo . > "$BACKUP_PATH/odoo_filestore.tar.gz" 2>/dev/null || {
    log_info "No filestore data (normal)"
    tar czf "$BACKUP_PATH/odoo_filestore.tar.gz" -C /tmp --files-from=/dev/null 2>/dev/null
}

# Backup addons
log_info "Backing up addons..."
if [ -d "$PROJECT_ROOT/addons" ]; then
    tar czf "$BACKUP_PATH/odoo_addons.tar.gz" -C "$PROJECT_ROOT" addons
else
    tar czf "$BACKUP_PATH/odoo_addons.tar.gz" -C /tmp --files-from=/dev/null 2>/dev/null
fi

# Create metadata
cat > "$BACKUP_PATH/backup.info" <<EOF
BACKUP_NAME=$BACKUP_NAME
TIMESTAMP=$TIMESTAMP
DATE=$(date)
DATABASE=odoo_db.dump
FILESTORE=odoo_filestore.tar.gz
ADDONS=odoo_addons.tar.gz
EOF

# Compress
log_info "Compressing backup..."
BACKUP_ARCHIVE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
tar czf "$BACKUP_ARCHIVE" -C "$BACKUP_DIR" "$BACKUP_NAME"
rm -rf "$BACKUP_PATH"

ARCHIVE_SIZE=$(du -h "$BACKUP_ARCHIVE" | cut -f1)
log_info "Backup compressed ($ARCHIVE_SIZE)"

# Upload to R2
if [ ! -z "$CF_R2_BUCKET" ] && [ "$CF_R2_BUCKET" != "your-bucket-name" ]; then
    log_info "Uploading to Cloudflare R2..."
    if aws s3 cp "$BACKUP_ARCHIVE" "s3://${CF_R2_BUCKET}/${BACKUP_NAME}.tar.gz" --endpoint-url "$CF_R2_ENDPOINT" 2>&1; then
        log_info "Uploaded to R2 ✓"
    else
        log_error "R2 upload failed (backup still local)"
    fi
else
    log_info "R2 not configured, backup kept locally"
fi

echo ""
log_info "✅ Backup complete: $BACKUP_ARCHIVE"
echo ""
