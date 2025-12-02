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

# Validate arguments
if [ $# -eq 0 ]; then
    log_error "Usage: $0 <backup-name-or-file>"
    log_info ""
    log_info "Examples:"
    log_info "  $0 odoo_backup_2025-12-01_10-30-45"
    log_info "  $0 odoo_backup_2025-12-01_10-30-45.tar.gz"
    log_info ""
    log_info "Available local backups:"
    if [ -d "$BACKUP_DIR" ]; then
        ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || log_warn "No local backups found"
    else
        log_warn "Backup directory not found"
    fi
    exit 1
fi

BACKUP_NAME="$1"

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    log_error ".env file not found at $ENV_FILE"
    exit 1
fi

# Load environment variables
set -a
source "$ENV_FILE"
set +a

log_info "=========================================="
log_info "Starting Odoo Restore"
log_info "=========================================="
log_info "Backup name: $BACKUP_NAME"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Determine if backup is local or needs to be downloaded from R2
BACKUP_FILE=""
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

if [ -f "$BACKUP_DIR/$BACKUP_NAME" ]; then
    BACKUP_FILE="$BACKUP_DIR/$BACKUP_NAME"
    log_info "Using local backup file"
elif [ -f "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" ]; then
    BACKUP_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
    log_info "Using local backup file"
else
    log_info "Backup not found locally, attempting to download from R2..."
    
    # Try to download from R2
    R2_FILE="${BACKUP_NAME}"
    if [[ ! "$R2_FILE" == *.tar.gz ]]; then
        R2_FILE="${R2_FILE}.tar.gz"
    fi
    
    S3_PATH="s3://${CF_R2_BUCKET}/${R2_FILE}"
    BACKUP_FILE="$TEMP_DIR/$R2_FILE"
    
    if aws s3 cp "$S3_PATH" "$BACKUP_FILE" --region auto; then
        log_info "Backup downloaded from R2 ✓"
    else
        log_error "Could not find backup locally or on R2: $BACKUP_NAME"
        exit 1
    fi
fi

if [ ! -f "$BACKUP_FILE" ]; then
    log_error "Backup file not found: $BACKUP_FILE"
    exit 1
fi

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
log_info "Backup file: $BACKUP_FILE (Size: $BACKUP_SIZE)"

# Extract backup archive
log_info "Extracting backup archive..."
EXTRACT_DIR="$TEMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"

tar xzf "$BACKUP_FILE" -C "$EXTRACT_DIR"

# Find the backup directory inside the archive
BACKUP_CONTENT_DIR=$(ls -d "$EXTRACT_DIR"/odoo_backup_* 2>/dev/null | head -1)
if [ -z "$BACKUP_CONTENT_DIR" ]; then
    log_error "Invalid backup format: could not find backup directory"
    exit 1
fi

log_info "Backup extracted ✓"

# Find backup components
DUMP_FILE=$(ls "$BACKUP_CONTENT_DIR"/odoo_db_*.dump 2>/dev/null | head -1)
FILESTORE_TAR=$(ls "$BACKUP_CONTENT_DIR"/odoo_filestore_*.tar.gz 2>/dev/null | head -1)
ADDONS_TAR=$(ls "$BACKUP_CONTENT_DIR"/addons_*.tar.gz 2>/dev/null | head -1)
METADATA_FILE="$BACKUP_CONTENT_DIR/backup.info"

if [ -z "$DUMP_FILE" ]; then
    log_error "Database dump not found in backup"
    exit 1
fi

log_info "Backup components found:"
log_info "  Database: $(basename "$DUMP_FILE")"
[ -f "$FILESTORE_TAR" ] && log_info "  Filestore: $(basename "$FILESTORE_TAR")"
[ -f "$ADDONS_TAR" ] && log_info "  Addons: $(basename "$ADDONS_TAR")"

# Display backup metadata if available
if [ -f "$METADATA_FILE" ]; then
    log_info "Backup information:"
    grep "^BACKUP_DATE\|^BACKUP_NAME\|^TOTAL_SIZE" "$METADATA_FILE" | sed 's/^/  /'
fi

# Step 1: Stop Odoo container (keep PostgreSQL running)
log_info "Stopping Odoo application..."
docker-compose -f "$PROJECT_ROOT/docker-compose.yml" stop odoo

log_warn "⚠ IMPORTANT: This will drop and recreate the database!"
read -p "Continue with restore? (yes/no): " -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
    log_error "Restore cancelled by user"
    docker-compose -f "$PROJECT_ROOT/docker-compose.yml" start odoo
    exit 1
fi

# Step 2: Drop and recreate database
log_info "Dropping existing database..."
docker-compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres \
    dropdb -U "${POSTGRES_USER}" "${POSTGRES_DB}" || true

log_info "Creating new database..."
docker-compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres \
    createdb -U "${POSTGRES_USER}" "${POSTGRES_DB}"

# Step 3: Restore PostgreSQL database
log_info "Restoring PostgreSQL database..."
docker-compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres \
    pg_restore -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -v < "$DUMP_FILE"

log_info "Database restored ✓"

# Step 4: Restore filestore
if [ -f "$FILESTORE_TAR" ]; then
    log_info "Restoring Odoo filestore..."
    
    # Clear existing filestore
    docker run --rm --volumes-from odoo-web alpine rm -rf /var/lib/odoo/*
    
    # Extract filestore
    docker run --rm \
        --volumes-from odoo-web \
        -v "$FILESTORE_TAR:/backup/filestore.tar.gz" \
        alpine tar xzf /backup/filestore.tar.gz -C /var/lib/odoo
    
    log_info "Filestore restored ✓"
else
    log_warn "No filestore found in backup"
fi

# Step 5: Restore addons
if [ -f "$ADDONS_TAR" ]; then
    log_info "Restoring addons..."
    
    # Clear existing addons (keep only extracted)
    rm -rf "$PROJECT_ROOT/addons"/*
    
    # Extract addons to temporary directory
    tar xzf "$ADDONS_TAR" -C "$PROJECT_ROOT"
    
    log_info "Addons restored ✓"
else
    log_warn "No addons found in backup"
fi

# Step 6: Start containers
log_info "Starting containers..."
docker-compose -f "$PROJECT_ROOT/docker-compose.yml" start

# Wait for services to be healthy
log_info "Waiting for services to be healthy..."
for i in {1..30}; do
    if docker-compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres \
        pg_isready -U "${POSTGRES_USER}" > /dev/null 2>&1; then
        log_info "PostgreSQL is healthy ✓"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "PostgreSQL failed to start"
        exit 1
    fi
    sleep 2
done

log_info "Waiting for Odoo to start..."
sleep 10

# Final status
log_info "=========================================="
log_info "✓ Restore completed successfully!"
log_info "=========================================="
log_info "Your Odoo instance has been restored from:"
log_info "  $BACKUP_NAME"
log_info ""
log_info "Next steps:"
log_info "1. Access Odoo at: http://localhost"
log_info "2. Log in with your restored credentials"
log_info "3. Verify your data is intact"
log_info ""
log_info "Docker status:"
docker-compose -f "$PROJECT_ROOT/docker-compose.yml" ps
