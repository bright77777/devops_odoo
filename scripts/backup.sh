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
docker exec -T "$POSTGRES_CONTAINER" pg_dump -U "${POSTGRES_USER}" -F c "${POSTGRES_DB}" > "$BACKUP_PATH/odoo_db.dump"
SIZE=$(du -h "$BACKUP_PATH/odoo_db.dump" | cut -f1)
log_info "Database backed up ($SIZE)"

# Backup filestore
log_info "Backing up filestore..."
docker exec -T "$ODOO_CONTAINER" tar czf - -C /var/lib/odoo . > "$BACKUP_PATH/odoo_filestore.tar.gz" 2>/dev/null || {
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
DATABASE=$(basename "$BACKUP_PATH")/odoo_db.dump
FILESTORE=$(basename "$BACKUP_PATH")/odoo_filestore.tar.gz
ADDONS=$(basename "$BACKUP_PATH")/odoo_addons.tar.gz
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
    if aws s3 cp "$BACKUP_ARCHIVE" "s3://${CF_R2_BUCKET}/${BACKUP_NAME}.tar.gz" --region auto 2>&1; then
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

# Step 2: Backup Odoo filestore
log_info "Backing up Odoo filestore..."
FILESTORE_TAR="$BACKUP_PATH/odoo_filestore_${TIMESTAMP}.tar.gz"

# Try to backup filestore from container
docker exec -T "$ODOO_CONTAINER" tar czf - -C /var/lib/odoo . > "$FILESTORE_TAR" 2>/dev/null || {
    log_warn "Could not backup filestore from container, will create empty archive"
    tar czf "$FILESTORE_TAR" -C /tmp --files-from=/dev/null 2>/dev/null || true
}

if [ -f "$FILESTORE_TAR" ] && [ -s "$FILESTORE_TAR" ]; then
    TAR_SIZE=$(du -h "$FILESTORE_TAR" | cut -f1)
    log_info "Odoo filestore backed up ✓ (Size: $TAR_SIZE)"
else
    log_warn "Filestore backup is empty or failed (this might be normal if no files)"
fi

# Step 3: Backup addons folder
log_info "Backing up addons folder..."
ADDONS_TAR="$BACKUP_PATH/addons_${TIMESTAMP}.tar.gz"

if [ -d "$PROJECT_ROOT/addons" ]; then
    tar czf "$ADDONS_TAR" -C "$PROJECT_ROOT" addons
    ADDONS_SIZE=$(du -h "$ADDONS_TAR" | cut -f1)
    log_info "Addons folder backed up ✓ (Size: $ADDONS_SIZE)"
else
    log_warn "No addons folder found, creating empty archive"
    tar czf "$ADDONS_TAR" -C /tmp --files-from=/dev/null
fi

# Step 4: Create metadata file
log_info "Creating backup metadata..."
METADATA_FILE="$BACKUP_PATH/backup.info"

cat > "$METADATA_FILE" <<EOF
BACKUP_NAME=$BACKUP_NAME
BACKUP_TIMESTAMP=$TIMESTAMP
BACKUP_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
ODOO_DB=${POSTGRES_DB}
DATABASE_DUMP=$(basename "$DUMP_FILE")
FILESTORE_TAR=$(basename "$FILESTORE_TAR")
ADDONS_TAR=$(basename "$ADDONS_TAR")
TOTAL_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
EOF

log_info "Backup metadata created ✓"

# Step 5: Compress backup directory
log_info "Compressing backup package..."
BACKUP_ARCHIVE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"

tar czf "$BACKUP_ARCHIVE" -C "$BACKUP_DIR" "$BACKUP_NAME"

if [ -f "$BACKUP_ARCHIVE" ]; then
    ARCHIVE_SIZE=$(du -h "$BACKUP_ARCHIVE" | cut -f1)
    log_info "Backup package compressed ✓ (Size: $ARCHIVE_SIZE)"
else
    log_error "Failed to compress backup package"
    exit 1
fi

# Step 6: Upload to Cloudflare R2
log_info "Uploading backup to Cloudflare R2..."

S3_PATH="s3://${CF_R2_BUCKET}/${BACKUP_NAME}.tar.gz"

# Check if R2 credentials are configured
if [ -z "$CF_R2_BUCKET" ] || [ "$CF_R2_BUCKET" = "your-bucket-name" ]; then
    log_warn "R2 bucket not configured, skipping upload"
    log_info "To enable R2 upload, fill in .env with your R2 credentials"
else
    if aws s3 cp "$BACKUP_ARCHIVE" "$S3_PATH" --region auto 2>&1; then
        log_info "Backup uploaded to R2 ✓"
        log_info "R2 Path: $S3_PATH"
    else
        log_error "Failed to upload backup to R2"
        log_warn "Keeping local backup: $BACKUP_ARCHIVE"
        log_warn "You can retry upload manually: aws s3 cp $BACKUP_ARCHIVE $S3_PATH --region auto"
    fi
fi

# Step 7: Clean up local backup directory (keep only the archive)
log_info "Cleaning up temporary files..."
rm -rf "$BACKUP_PATH"
log_info "Temporary files removed ✓"

# Step 8: Cleanup old backups (keep only last 30 days)
log_info "Cleaning up old backups..."
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}
CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" +%s)

for backup_file in "$BACKUP_DIR"/*.tar.gz; do
    if [ -f "$backup_file" ]; then
        FILE_DATE=$(date -r "$backup_file" +%s)
        if [ "$FILE_DATE" -lt "$CUTOFF_DATE" ]; then
            log_info "Removing old backup: $(basename "$backup_file")"
            rm -f "$backup_file"
        fi
    fi
done

# Also cleanup old backups from R2
log_info "Cleaning up old backups from R2..."
aws s3 ls "s3://${CF_R2_BUCKET}/" --recursive --region auto | while read -r date time size file; do
    FILE_DATE=$(date -d "$date $time" +%s 2>/dev/null || echo 0)
    if [ "$FILE_DATE" -lt "$CUTOFF_DATE" ]; then
        log_debug "Removing old R2 backup: $file"
        aws s3 rm "s3://${CF_R2_BUCKET}/$file" --region auto || true
    fi
done

log_info "Old backups cleaned up ✓"

# Final status
log_info "=========================================="
log_info "✓ Backup completed successfully!"
log_info "=========================================="
log_info "Backup file: $BACKUP_ARCHIVE"
log_info "Archive size: $ARCHIVE_SIZE"
log_info "R2 location: $S3_PATH"
log_info ""
log_info "Backup details saved to: $BACKUP_ARCHIVE"
