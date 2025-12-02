#!/usr/bin/env bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
BACKUP_DIR="$PROJECT_ROOT/backup"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    log_error ".env file not found at $ENV_FILE"
    exit 1
fi

# Load environment variables
set -a
source "$ENV_FILE"
set +a

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Generate timestamp
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="odoo_backup_${TIMESTAMP}"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

log_info "=========================================="
log_info "Starting Odoo Backup"
log_info "=========================================="
log_info "Backup name: $BACKUP_NAME"
log_info "Backup path: $BACKUP_PATH"

# Create temporary backup directory
mkdir -p "$BACKUP_PATH"

# Step 1: Backup PostgreSQL database
log_info "Backing up PostgreSQL database..."
DUMP_FILE="$BACKUP_PATH/odoo_db_${TIMESTAMP}.dump"

docker-compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres \
    pg_dump -U "${POSTGRES_USER}" -F c "${POSTGRES_DB}" > "$DUMP_FILE"

if [ -f "$DUMP_FILE" ]; then
    DUMP_SIZE=$(du -h "$DUMP_FILE" | cut -f1)
    log_info "PostgreSQL database backed up ✓ (Size: $DUMP_SIZE)"
else
    log_error "Failed to backup PostgreSQL database"
    exit 1
fi

# Step 2: Backup Odoo filestore
log_info "Backing up Odoo filestore..."
FILESTORE_TAR="$BACKUP_PATH/odoo_filestore_${TIMESTAMP}.tar.gz"

docker run --rm \
    --volumes-from odoo-web \
    -v "$BACKUP_PATH:/backup" \
    alpine tar czf "/backup/$(basename "$FILESTORE_TAR")" \
    -C /var/lib/odoo .

if [ -f "$FILESTORE_TAR" ]; then
    TAR_SIZE=$(du -h "$FILESTORE_TAR" | cut -f1)
    log_info "Odoo filestore backed up ✓ (Size: $TAR_SIZE)"
else
    log_error "Failed to backup Odoo filestore"
    exit 1
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

if aws s3 cp "$BACKUP_ARCHIVE" "$S3_PATH" --region auto; then
    log_info "Backup uploaded to R2 ✓"
    log_info "R2 Path: $S3_PATH"
else
    log_error "Failed to upload backup to R2"
    rm -rf "$BACKUP_PATH"
    rm -f "$BACKUP_ARCHIVE"
    exit 1
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
