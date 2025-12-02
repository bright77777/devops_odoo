#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
        log_info "PostgreSQL ready ✓"
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Minimal setup: only what's necessary to run odoo-app (odoo:19) and odoo-db (postgres:15)

if [ ! -f "$ENV_FILE" ]; then
    log_error ".env not found in $PROJECT_ROOT"
    log_info "Create it from .env.example and set POSTGRES_USER/PASSWORD/DB"
    exit 1
fi

set -a; source "$ENV_FILE"; set +a

echo
echo "🚀 SETUP ODOO (minimal)"

# Install docker if missing
if ! command -v docker >/dev/null 2>&1; then
    log_info "Docker not found — installing docker.io"
    sudo apt-get update -y
    sudo apt-get install -y docker.io
    log_info "Docker installed"
fi

# Use docker-compose (keep it minimal and match user's docker-compose.yml)
log_info "Starting containers with docker-compose..."
cd "$PROJECT_ROOT"
docker compose pull 2>/dev/null || docker-compose pull 2>/dev/null || true
docker compose up -d || docker-compose up -d

# Wait for PostgreSQL service to be healthy
log_info "Waiting for PostgreSQL to be healthy..."
for i in $(seq 1 30); do
    # look for container named odoo-db (as in docker-compose file)
    if docker ps --format '{{.Names}} {{.Status}}' | grep -E '^odoo-db' >/dev/null 2>&1; then
        if docker inspect --format '{{.State.Health.Status}}' odoo-db 2>/dev/null | grep -q healthy; then
            log_info "PostgreSQL healthy"
            break
        fi
    fi
    sleep 2
done

log_info "Setup complete. Run 'docker ps' to verify containers."

echo "  2. Restore:  bash scripts/restore.sh <backup-name>"
echo ""
docker-compose ps
echo ""
