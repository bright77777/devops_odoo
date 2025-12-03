#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

clear
echo ""
echo "🚀 ODOO INFRASTRUCTURE SETUP"
echo "════════════════════════════════════════════"
echo ""

# Check prerequisites
log_step "Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { log_error "Docker not installed"; exit 1; }
command -v docker compose >/dev/null 2>&1 || { log_error "Docker Compose not installed"; exit 1; }
log_info "Docker: $(docker --version)"
log_info "Docker Compose: $(docker compose version)"

# Create .env if not exists
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    log_step "Creating .env file from template..."
    if [ -f "$PROJECT_ROOT/.env.example" ]; then
        cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
        log_info ".env created - PLEASE CONFIGURE IT BEFORE CONTINUING!"
        echo ""
        echo "Edit .env and set:"
        echo "  - POSTGRES_PASSWORD"
        echo "  - ODOO_ADMIN_PASSWORD"
        echo "  - CF_R2_* credentials (if using R2)"
        echo ""
        exit 0
    else
        log_error ".env.example not found"
        exit 1
    fi
fi

# Load environment
set -a
source "$PROJECT_ROOT/.env"
set +a

# Create directories
log_step "Creating directory structure..."
mkdir -p "$PROJECT_ROOT/addons"
mkdir -p "$PROJECT_ROOT/config"
mkdir -p "$PROJECT_ROOT/backup"
log_info "Directories created"

# Create odoo.conf if not exists
if [ ! -f "$PROJECT_ROOT/config/odoo.conf" ]; then
    log_step "Creating default Odoo configuration..."
    cat > "$PROJECT_ROOT/config/odoo.conf" <<EOF
[options]
addons_path = /mnt/extra-addons
data_dir = /var/lib/odoo
admin_passwd = ${ODOO_ADMIN_PASSWORD:-admin}
db_host = db
db_port = 5432
db_user = ${POSTGRES_USER:-odoo}
db_password = ${POSTGRES_PASSWORD:-odoo}
workers = ${ODOO_WORKERS:-4}
max_cron_threads = 2
limit_time_cpu = ${ODOO_TIMEOUT:-600}
limit_time_real = ${ODOO_TIMEOUT:-600}
limit_memory_soft = 2147483648
limit_memory_hard = 2684354560
log_level = info
EOF
    log_info "odoo.conf created"
fi

# Check R2 configuration
if [ -z "$CF_R2_ENDPOINT" ] || [ -z "$CF_R2_BUCKET" ] || [ -z "$CF_R2_ACCESS_KEY_ID" ] || [ -z "$CF_R2_SECRET_ACCESS_KEY" ]; then
    log_info "⚠️  R2 not configured - backups will be local only"
else
    log_step "Testing R2 connection..."
    if AWS_ACCESS_KEY_ID="$CF_R2_ACCESS_KEY_ID" \
       AWS_SECRET_ACCESS_KEY="$CF_R2_SECRET_ACCESS_KEY" \
       aws s3 ls "s3://${CF_R2_BUCKET}" --endpoint-url "$CF_R2_ENDPOINT" >/dev/null 2>&1; then
        log_info "R2 connection successful ✓"
    else
        log_error "R2 connection failed - check credentials"
        echo "Continuing without R2..."
    fi
fi

# Stop existing containers
if docker ps -a --format '{{.Names}}' | grep -q "odoo"; then
    log_step "Stopping existing containers..."
    cd "$PROJECT_ROOT"
    docker compose down
    log_info "Containers stopped"
fi

# Start services
log_step "Starting Odoo infrastructure..."
cd "$PROJECT_ROOT"
docker compose up -d

# Wait for services
log_step "Waiting for services to be ready..."
for i in {1..30}; do
    if docker exec odoo-db pg_isready -U "${POSTGRES_USER:-odoo}" >/dev/null 2>&1; then
        log_info "PostgreSQL ready ✓"
        break
    fi
    sleep 2
done

for i in {1..60}; do
    if curl -s http://localhost:8069/web/database/selector >/dev/null 2>&1; then
        log_info "Odoo ready ✓"
        break
    fi
    sleep 2
done

# Make scripts executable
chmod +x "$SCRIPT_DIR/backup.sh"
chmod +x "$SCRIPT_DIR/restore.sh"

echo ""
echo "════════════════════════════════════════════"
echo "✅ SETUP COMPLETE"
echo "════════════════════════════════════════════"
echo ""
echo "Odoo is running at: http://localhost:8069"
echo ""
echo "Available commands:"
echo "  ./scripts/backup.sh   - Create backup"
echo "  ./scripts/restore.sh  - Restore from backup"
echo ""
echo "Database info:"
echo "  Host: localhost:5432"
echo "  User: ${POSTGRES_USER:-odoo}"
echo "  Database: ${POSTGRES_DB:-odoo}"
echo ""