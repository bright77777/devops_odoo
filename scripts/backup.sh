#!/usr/bin/env bash
set -euo pipefail

# backup.sh
# - dump DB (pg_dump -F c) dans /tmp
# - archive filestore (volume odoo-web-data)
# - archive addons (./addons)
# - pack en tar.gz et upload sur R2 (aws s3)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT/.env"
set -o allexport; [ -f "$ENV_FILE" ] && source "$ENV_FILE"; set +o allexport

TIMESTAMP=$(date +%F_%H-%M-%S)
TMP="/tmp/odoo_backup_$TIMESTAMP"
mkdir -p "$TMP"

POSTGRES_SERVICE="${POSTGRES_SERVICE:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-odoo}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"
ODOO_VOLUME="${ODOO_VOLUME:-odoo-web-data}"
CF_R2_BUCKET="${CF_R2_BUCKET:-}"

echo "[1/4] Dump de la base PostgreSQL (service: $POSTGRES_SERVICE)..."
CONTAINER_ID=$(docker compose ps -q "$POSTGRES_SERVICE")
if [ -n "$CONTAINER_ID" ]; then
  docker exec -t "$CONTAINER_ID" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F c -f /tmp/db.dump || \
    docker exec -t "$CONTAINER_ID" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" > "$TMP/db.sql"
  docker cp "$CONTAINER_ID":/tmp/db.dump "$TMP/" 2>/dev/null || true
fi

echo "[2/4] Archive filestore (volume: $ODOO_VOLUME)..."
docker run --rm -v "$ODOO_VOLUME":/data -v "$TMP":/backup busybox \
  sh -c "tar czf /backup/filestore.tgz -C /data ."

echo "[3/4] Archive addons (si ./addons existe)..."
if [ -d "$ROOT/addons" ]; then
  tar czf "$TMP/addons.tgz" -C "$ROOT" "addons"
fi

echo "[4/4] Création du bundle backup..."
cp -n "$ROOT/docker-compose.yml" "$TMP/" 2>/dev/null || true
[ -f "$ROOT/.env" ] && cp -n "$ROOT/.env" "$TMP/env_snapshot" || true
tar czf /tmp/odoo_backup_${TIMESTAMP}.tar.gz -C "$TMP" .

if [ -n "$CF_R2_BUCKET" ]; then
  echo "[INFO] Upload vers Cloudflare R2 (bucket: $CF_R2_BUCKET)..."
  aws s3 cp /tmp/odoo_backup_${TIMESTAMP}.tar.gz s3://$CF_R2_BUCKET/ || echo "[WARN] Upload échoué"
  echo "[INFO] Upload terminé : s3://$CF_R2_BUCKET/odoo_backup_${TIMESTAMP}.tar.gz"
else
  echo "[INFO] CF_R2_BUCKET non défini — backup local sauvegardé : /tmp/odoo_backup_${TIMESTAMP}.tar.gz"
fi

echo "DONE"
