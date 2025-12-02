#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check .env
if [ ! -f "$ENV_FILE" ]; then
    log_error ".env file not found"
    echo "cp $PROJECT_ROOT/.env.example $ENV_FILE"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

echo ""
echo "🚀 SETUP ODOO BACKUP/RESTORE"
echo "════════════════════════════════════════════"
echo ""

# Install Docker if needed
if ! command -v docker &> /dev/null; then
    log_info "Installing Docker..."
    sudo apt-get update && sudo apt-get install -y docker.io docker-compose-plugin
    sudo usermod -aG docker "$USER"
fi

# Install AWS CLI if needed
if ! command -v aws &> /dev/null; then
    log_info "Installing AWS CLI..."
    sudo apt-get install -y awscli
fi

# Configure AWS for R2
log_info "Configuring AWS CLI..."
mkdir -p ~/.aws

cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = ${CF_R2_ACCESS_KEY_ID}
aws_secret_access_key = ${CF_R2_SECRET_ACCESS_KEY}
EOF
chmod 600 ~/.aws/credentials

cat > ~/.aws/config <<EOF
[default]
region = auto
s3 =
    endpoint_url = ${CF_R2_ENDPOINT}
EOF
chmod 644 ~/.aws/config

# Create backup dir
mkdir -p "$PROJECT_ROOT/backup"

# Start Docker
log_info "Starting Docker containers..."
cd "$PROJECT_ROOT"
docker-compose pull 2>/dev/null
docker-compose up -d

# Wait for PostgreSQL - get container name
POSTGRES_CONTAINER=$(docker ps --format "table {{.Names}}\t{{.Image}}" | grep -i postgres | awk '{print $1}' | head -1)
if [ -z "$POSTGRES_CONTAINER" ]; then
    for name in odoo-db odoo-postgres postgres; do
        if docker ps --format "{{.Names}}" | grep -q "^${name}$"; then
            POSTGRES_CONTAINER="$name"
            break
        fi
    done
fi

for i in {1..30}; do
    if [ ! -z "$POSTGRES_CONTAINER" ] && docker exec "$POSTGRES_CONTAINER" pg_isready -U "${POSTGRES_USER}" &>/dev/null; then
        log_info "PostgreSQL ready ✓"
        break
    fi
    sleep 2
done

sleep 5

# Setup cron
log_info "Setting up cron backup..."
CRON_SCHEDULE="${BACKUP_SCHEDULE:-0 2 */5 * *}"
BACKUP_SCRIPT="$PROJECT_ROOT/scripts/backup.sh"

if ! crontab -l 2>/dev/null | grep -q "$BACKUP_SCRIPT"; then
    (crontab -l 2>/dev/null || true; echo "$CRON_SCHEDULE $BACKUP_SCRIPT >> /var/log/odoo-backup.log 2>&1") | crontab -
fi

# Make scripts executable
chmod +x "$PROJECT_ROOT/scripts"/*.sh

echo ""
echo "✅ SETUP COMPLETE"
echo "════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Backup:   bash scripts/backup.sh"
echo "  2. Restore:  bash scripts/restore.sh <backup-name>"
echo ""
docker-compose ps
echo ""
