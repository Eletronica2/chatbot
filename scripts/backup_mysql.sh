#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   MYSQL_ROOT_PASSWORD=... ./scripts/backup_mysql.sh
# Optional: MYSQL_HOST MYSQL_PORT MYSQL_DATABASE OUT_DIR CONTAINER

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/backups}"
CONTAINER="${CONTAINER:-}"
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_DATABASE="${MYSQL_DATABASE:-atenda}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_FILE="$OUT_DIR/${MYSQL_DATABASE}-${STAMP}.sql.gz"

if [[ -z "${MYSQL_ROOT_PASSWORD:-}" ]]; then
  echo "MYSQL_ROOT_PASSWORD is required" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

if [[ -n "$CONTAINER" ]]; then
  docker exec "$CONTAINER" mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --no-create-db "$MYSQL_DATABASE" \
    | gzip > "$OUT_FILE"
else
  mysqldump -h "$MYSQL_HOST" -P "$MYSQL_PORT" -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --no-create-db "$MYSQL_DATABASE" \
    | gzip > "$OUT_FILE"
fi

echo "$OUT_FILE"
