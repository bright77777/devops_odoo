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

# Minimal setup: use docker-compose at project root (no extra networks)

if [ ! -f "$ENV_FILE" ]; then
  log_error ".env not found in $PROJECT_ROOT"
  log_info "Create it from .env.example and set POSTGRES_USER/PASSWORD/DB"
  exit 1
fi

set -a; source "$ENV_FILE"; set +a

echo
log_info "Starting containers with docker-compose (minimal)"
cd "$PROJECT_ROOT"

# Prefer 'docker compose' when available
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  log_error "Neither 'docker compose' nor 'docker-compose' found. Install Docker Compose first."
  exit 1
fi

# Pull images if possible (quiet), then start
$DC pull 2>/dev/null || true
$DC up -d

# Wait for postgres health (container name: odoo-db)
log_info "Waiting for PostgreSQL (odoo-db) to become healthy..."
for i in $(seq 1 30); do
  if docker ps --format '{{.Names}}' | grep -q '^odoo-db$'; then
    HEALTH=$(docker inspect --format '{{.State.Health.Status}}' odoo-db 2>/dev/null || true)
    if [ "$HEALTH" = "healthy" ]; then
      log_info "PostgreSQL healthy"
      break
    fi
  fi
  sleep 2
done

log_info "Setup finished. Verify with: docker ps && docker-compose ps"

exit 0
