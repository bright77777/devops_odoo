#!/usr/bin/env bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    log_error ".env file not found at $ENV_FILE"
    log_info "Please copy .env.example to .env and fill in the values:"
    log_info "  cp $PROJECT_ROOT/.env.example $ENV_FILE"
    exit 1
fi

# Load environment variables
set -a
source "$ENV_FILE"
set +a

log_info "=========================================="
log_info "Odoo Backup/Restore Setup Starting"
log_info "=========================================="
log_info "Project Root: $PROJECT_ROOT"
log_info "Environment: $ENV_FILE"

# Step 1: Check system prerequisites
log_info "Checking system prerequisites..."
if ! command -v docker &> /dev/null; then
    log_warn "Docker not found, installing..."
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo usermod -aG docker "$USER"
    log_info "Docker installed. You may need to logout/login or use 'newgrp docker'"
fi

if ! command -v docker-compose &> /dev/null; then
    log_warn "Docker Compose not found, installing..."
    sudo apt-get install -y docker-compose-plugin
fi

if ! command -v aws &> /dev/null; then
    log_warn "AWS CLI not found, installing..."
    sudo apt-get install -y awscli
fi

log_info "All prerequisites installed ✓"

# Step 2: Configure AWS CLI for Cloudflare R2
log_info "Configuring AWS CLI for Cloudflare R2..."

mkdir -p ~/.aws

# Configure AWS credentials
cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = ${CF_R2_ACCESS_KEY_ID}
aws_secret_access_key = ${CF_R2_SECRET_ACCESS_KEY}
EOF

chmod 600 ~/.aws/credentials

# Configure AWS config
if [ ! -f ~/.aws/config ]; then
    cat > ~/.aws/config <<EOF
[default]
region = auto
output = json
s3 =
  endpoint_url = ${CF_R2_ENDPOINT}
EOF
else
    # Ensure R2 endpoint is configured
    if ! grep -q "endpoint_url" ~/.aws/config; then
        echo "" >> ~/.aws/config
        echo "[default]" >> ~/.aws/config
        echo "s3 =" >> ~/.aws/config
        echo "  endpoint_url = ${CF_R2_ENDPOINT}" >> ~/.aws/config
    fi
fi

log_info "AWS CLI configured for Cloudflare R2 ✓"

# Step 3: Create directories
log_info "Creating required directories..."
mkdir -p "$PROJECT_ROOT/backup"
log_info "Backup directory created ✓"

# Step 4: Verify R2 connectivity
log_info "Verifying Cloudflare R2 connectivity..."
if aws s3 ls "s3://${CF_R2_BUCKET}" --region auto > /dev/null 2>&1; then
    log_info "R2 bucket accessible ✓"
else
    log_warn "Could not verify R2 bucket. Check credentials in .env file."
fi

# Step 5: Start Docker containers
log_info "Starting Docker containers..."
cd "$PROJECT_ROOT"
docker-compose pull
docker-compose up -d

# Wait for services to be healthy
log_info "Waiting for services to be healthy..."
for i in {1..30}; do
    if docker-compose exec -T postgres pg_isready -U "${POSTGRES_USER}" > /dev/null 2>&1; then
        log_info "PostgreSQL is healthy ✓"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "PostgreSQL failed to start"
        exit 1
    fi
    sleep 2
done

log_info "Waiting for Odoo to start (this may take a moment)..."
sleep 10

# Step 6: Setup cron job for automated backups
log_info "Setting up automated backup cron job..."

CRON_SCHEDULE="${BACKUP_SCHEDULE:-0 2 */5 * *}"
BACKUP_SCRIPT="$PROJECT_ROOT/scripts/backup.sh"
CRON_CMD="$CRON_SCHEDULE $BACKUP_SCRIPT >> /var/log/odoo-backup.log 2>&1"
CRON_COMMENT="# Odoo automated backup"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "$BACKUP_SCRIPT"; then
    log_warn "Backup cron job already exists"
else
    # Add new cron job
    (crontab -l 2>/dev/null || true; echo "$CRON_COMMENT"; echo "$CRON_CMD") | crontab -
    log_info "Backup cron job installed ✓"
fi

# Create log file with proper permissions
sudo touch /var/log/odoo-backup.log
sudo chmod 666 /var/log/odoo-backup.log

log_info "Cron configured to run: $CRON_SCHEDULE"

# Step 7: Make scripts executable
log_info "Making scripts executable..."
chmod +x "$PROJECT_ROOT/scripts/backup.sh"
chmod +x "$PROJECT_ROOT/scripts/restore.sh"
log_info "Scripts are now executable ✓"

# Step 8: Display final status
log_info "=========================================="
log_info "✓ Setup completed successfully!"
log_info "=========================================="
log_info ""
log_info "Next steps:"
log_info "1. Access Odoo at: http://localhost"
log_info "2. Manual backup: $PROJECT_ROOT/scripts/backup.sh"
log_info "3. View logs: tail -f /var/log/odoo-backup.log"
log_info ""
log_info "Docker status:"
docker-compose ps

log_info ""
log_info "Your system is ready for backup and restore operations!"
