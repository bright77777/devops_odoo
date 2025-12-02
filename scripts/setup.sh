#!/usr/bin/env bash
set -euo pipefail

# Setup script adapté à ton docker-compose.yml
# - Installe docker/docker-compose/awscli si manquant
# - Configure aws cli pour Cloudflare R2 si variables présentes
# - Pull et demarre les services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT/.env"

if [ -f "$ENV_FILE" ]; then
  set -o allexport
  # shellcheck disable=SC1091
  source "$ENV_FILE"
  set +o allexport
else
  echo "[WARN] .env non trouvé dans $ENV_FILE — utiliser les valeurs par défaut si présentes."
fi

echo "[INFO] Vérification des binaires docker / docker compose / aws..."
if ! command -v docker >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y docker.io
fi

# docker compose peut être disponible via plugin (docker compose) ou binaire
if ! docker compose version >/dev/null 2>&1; then
  sudo apt install -y docker-compose-plugin || true
fi

if ! command -v aws >/dev/null 2>&1; then
  sudo snap install aws-cli --classic || true
fi

# Configure AWS CLI for Cloudflare R2 (si variables présentes)
if [ -n "${CF_R2_ACCESS_KEY_ID:-}" ] && [ -n "${CF_R2_SECRET_ACCESS_KEY:-}" ] && [ -n "${CF_R2_ENDPOINT:-}" ]; then
  mkdir -p "$HOME/.aws"
  cat > "$HOME/.aws/credentials" <<EOF
[default]
aws_access_key_id = ${CF_R2_ACCESS_KEY_ID}
aws_secret_access_key = ${CF_R2_SECRET_ACCESS_KEY}
EOF
  cat > "$HOME/.aws/config" <<EOF
[default]
region = auto
s3 =
  endpoint_url = ${CF_R2_ENDPOINT}
EOF
  echo "[INFO] AWS CLI configuré pour Cloudflare R2."
fi

# Pull et démarrage
echo "[INFO] docker compose pull"
docker compose pull

echo "[INFO] docker compose up -d"
docker compose up -d

# Wait for Postgres to be ready
POSTGRES_SERVICE="${POSTGRES_SERVICE:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-odoo}"

echo "[INFO] Attente de Postgres ($POSTGRES_SERVICE) ..."
for i in $(seq 1 60); do
  if docker compose exec -T "$POSTGRES_SERVICE" pg_isready -U "$POSTGRES_USER" >/dev/null 2>&1; then
    echo "[INFO] Postgres est prêt."
    break
  fi
  sleep 2
done

echo "[INFO] Setup terminé. Consulte : docker compose ps && docker compose logs -f ${POSTGRES_SERVICE}"
