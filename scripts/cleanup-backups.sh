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

echo ""
echo "🧹 CLEANUP OLD BACKUPS"
echo "════════════════════════════════════════════"
echo ""

# Default: keep 4 backups
BACKUP_KEEP_COUNT=${BACKUP_KEEP_COUNT:-4}
log_info "Retention policy: Keep last ${BACKUP_KEEP_COUNT} backups"
echo ""

# Cleanup local backups
log_step "Cleaning local backups..."
TOTAL_LOCAL=$(ls -t "$BACKUP_DIR"/odoo_backup_*.tar.gz 2>/dev/null | wc -l)

if [ "$TOTAL_LOCAL" -eq 0 ]; then
    log_info "No local backups found"
elif [ "$TOTAL_LOCAL" -le "$BACKUP_KEEP_COUNT" ]; then
    log_info "Local backups: $TOTAL_LOCAL (keeping all, limit is ${BACKUP_KEEP_COUNT})"
else
    BACKUPS_TO_DELETE=$(ls -t "$BACKUP_DIR"/odoo_backup_*.tar.gz 2>/dev/null | tail -n +$((BACKUP_KEEP_COUNT + 1)))
    DELETED_COUNT=0
    
    while IFS= read -r BACKUP_FILE; do
        if [ ! -z "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
            log_info "Deleting: $(basename "$BACKUP_FILE")"
            rm -f "$BACKUP_FILE"
            DELETED_COUNT=$((DELETED_COUNT + 1))
        fi
    done <<< "$BACKUPS_TO_DELETE"
    
    log_info "Deleted $DELETED_COUNT local backup(s), kept last ${BACKUP_KEEP_COUNT}"
fi

echo ""

# Cleanup R2 backups
if [ -z "$CF_R2_BUCKET" ] || [ "$CF_R2_BUCKET" == "your-bucket-name" ]; then
    log_warn "R2 not configured, skipping R2 cleanup"
else
    log_step "Cleaning R2 backups..."
    
    # Get list of backups sorted by date (newest first)
    BACKUPS_LIST=$(AWS_ACCESS_KEY_ID="$CF_R2_ACCESS_KEY_ID" \
                   AWS_SECRET_ACCESS_KEY="$CF_R2_SECRET_ACCESS_KEY" \
                   aws s3 ls "s3://${CF_R2_BUCKET}/" --endpoint-url "$CF_R2_ENDPOINT" 2>/dev/null | \
                   grep "odoo_backup_.*\.tar\.gz" | \
                   sort -r | \
                   awk '{print $4}') || true
    
    # Count total backups
    TOTAL_R2=$(echo "$BACKUPS_LIST" | grep -c "odoo_backup" 2>/dev/null || echo "0")
    
    if [ "$TOTAL_R2" -eq 0 ]; then
        log_info "No R2 backups found"
    elif [ "$TOTAL_R2" -le "$BACKUP_KEEP_COUNT" ]; then
        log_info "R2 backups: $TOTAL_R2 (keeping all, limit is ${BACKUP_KEEP_COUNT})"
    else
        # Delete old backups (keep only BACKUP_KEEP_COUNT)
        BACKUPS_TO_DELETE=$(echo "$BACKUPS_LIST" | tail -n +$((BACKUP_KEEP_COUNT + 1)))
        DELETED_COUNT=0
        
        while IFS= read -r BACKUP_FILE; do
            if [ ! -z "$BACKUP_FILE" ]; then
                log_info "Deleting from R2: $BACKUP_FILE"
                if AWS_ACCESS_KEY_ID="$CF_R2_ACCESS_KEY_ID" \
                   AWS_SECRET_ACCESS_KEY="$CF_R2_SECRET_ACCESS_KEY" \
                   aws s3 rm "s3://${CF_R2_BUCKET}/${BACKUP_FILE}" \
                   --endpoint-url "$CF_R2_ENDPOINT" 2>/dev/null; then
                    DELETED_COUNT=$((DELETED_COUNT + 1))
                fi
            fi
        done <<< "$BACKUPS_TO_DELETE"
        
        log_info "Deleted $DELETED_COUNT R2 backup(s), kept last ${BACKUP_KEEP_COUNT}"
    fi
fi

echo ""
echo "════════════════════════════════════════════"
echo "✅ CLEANUP COMPLETE"
echo "════════════════════════════════════════════"
echo ""

# Show remaining backups
log_info "Remaining backups:"
echo ""
echo "LOCAL:"
if ls "$BACKUP_DIR"/odoo_backup_*.tar.gz >/dev/null 2>&1; then
    ls -lht "$BACKUP_DIR"/odoo_backup_*.tar.gz | head -n "$BACKUP_KEEP_COUNT" | awk '{print "  " $9 " (" $5 ")"}'
else
    echo "  (none)"
fi

echo ""
if [ ! -z "$CF_R2_BUCKET" ] && [ "$CF_R2_BUCKET" != "your-bucket-name" ]; then
    echo "R2:"
    AWS_ACCESS_KEY_ID="$CF_R2_ACCESS_KEY_ID" \
    AWS_SECRET_ACCESS_KEY="$CF_R2_SECRET_ACCESS_KEY" \
    aws s3 ls "s3://${CF_R2_BUCKET}/" --endpoint-url "$CF_R2_ENDPOINT" 2>/dev/null | \
    grep "odoo_backup_.*\.tar\.gz" | sort -r | head -n "$BACKUP_KEEP_COUNT" | \
    awk '{print "  " $4 " (" $3 " " $2 ")"}' || echo "  (none)"
fi
echo ""