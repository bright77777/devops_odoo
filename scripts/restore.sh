#!/usr/bin/env bash
set -euo pipefail

# restore.sh <backup-file-or-key>
# - si argument est un fichier local, l'utilise
# - sinon télécharge depuis s3://$CF_R2_BUCKET/<key>
# - extrait db.sql/db.dump, filestore.tgz, addons.tgz
# - démarre postgres, attend pg_isready, restaure DB, restaure filestore, restore addons, démarre odoo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT/.env"
[ -f "$ENV_FILE" ] && set -o allexport; source "$ENV_FILE"; set +o allexport

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <backup-file-or-key>"
  exit 1
fi

BACKUP_KEY="$1"
TMP="/tmp/odoo_restore_$(date +%s)"
mkdir -p "$TMP"

CF_R2_BUCKET="${CF_R2_BUCKET:-}"
POSTGRES_SERVICE="${POSTGRES_SERVICE:-postgres}"
ODOO_SERVICE="${ODOO_SERVICE:-odoo}"
ODOO_VOLUME="${ODOO_VOLUME:-odoo-web-data}"
POSTGRES_USER="${POSTGRES_USER:-odoo}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"

# Téléchargement si nécessaire
if [ -f "$BACKUP_KEY" ]; then
  echo "[INFO] Utilisation du backup local: $BACKUP_KEY"
  cp "$BACKUP_KEY" "$TMP/backup.tgz"
else
  if [ -z "$CF_R2_BUCKET" ]; then
    echo "[ERROR] Backup non local et CF_R2_BUCKET non défini."
    exit 1
  fi
  echo "[INFO] Téléchargement depuis R2: s3://$CF_R2_BUCKET/$BACKUP_KEY"
  aws s3 cp "s3://$CF_R2_BUCKET/$BACKUP_KEY" "$TMP/backup.tgz"
fi

echo "[INFO] Extraction..."
tar xzf "$TMP/backup.tgz" -C "$TMP"

echo "⚠️  WARNING: restore va écraser la base et le filestore. Tape 'yes' pour continuer."
read -r CONF
if [ "$CONF" != "yes" ]; then
  echo "[INFO] Abandonné."
  exit 0
fi

# Assurer docker compose up -d postgres
echo "[INFO] Démarrage du service Postgres ($POSTGRES_SERVICE)"
docker compose up -d "$POSTGRES_SERVICE"

# attente pg_isready
echo "[INFO] Attente de Postgres..."
for i in $(seq 1 60); do
  if docker compose exec -T "$POSTGRES_SERVICE" pg_isready -U "$POSTGRES_USER" >/dev/null 2>&1; then
    echo "[INFO] Postgres prêt."
    break
  fi
  sleep 2
done

# RESTORE DB
if [ -f "$TMP/db.sql" ]; then
  echo "[INFO] Restore depuis db.sql..."
  CID=$(docker compose ps -q "$POSTGRES_SERVICE")
  docker cp "$TMP/db.sql" "${CID}":/tmp/db.sql
  docker compose exec -T "$POSTGRES_SERVICE" bash -c "psql -U $POSTGRES_USER -d $POSTGRES_DB -f /tmp/db.sql"
elif [ -f "$TMP/db.dump" ]; then
  echo "[INFO] Restore depuis db.dump (pg_restore)..."
  CID=$(docker compose ps -q "$POSTGRES_SERVICE")
  docker cp "$TMP/db.dump" "${CID}":/tmp/db.dump
  docker compose exec -T "$POSTGRES_SERVICE" bash -c "pg_restore -U $POSTGRES_USER -d $POSTGRES_DB --clean --if-exists /tmp/db.dump"
else
  echo "[WARN] Aucun fichier db trouvé dans l'archive."
fi

# RESTORE filestore -> volume
if [ -f "$TMP/filestore.tgz" ]; then
  echo "[INFO] Restoration filestore dans le volume $ODOO_VOLUME..."
  docker volume inspect "$ODOO_VOLUME" >/dev/null 2>&1 || docker volume create "$ODOO_VOLUME"
  docker run --rm -v "$ODOO_VOLUME":/data -v "$TMP":/backup busybox \
    sh -c "rm -rf /data/* && tar xzf /backup/filestore.tgz -C /data"
else
  echo "[WARN] filestore.tgz absent."
fi

# RESTORE addons
if [ -f "$TMP/addons.tgz" ]; then
  echo "[INFO] Restoration addons -> $ROOT/addons"
  rm -rf "$ROOT/addons" && mkdir -p "$ROOT/addons"
  tar xzf "$TMP/addons.tgz" -C "$ROOT/addons"
fi

# Start Odoo
echo "[INFO] Démarrage du service Odoo ($ODOO_SERVICE)"
docker compose up -d "$ODOO_SERVICE"

echo "[INFO] Restore terminé. Vérifie : docker compose ps && docker compose logs -f $ODOO_SERVICE"
