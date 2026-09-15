#!/usr/bin/env bash
set -euo pipefail

# Restores a gzip dump into TARGET_DATABASE only.
# The dump must be table-level (scripts/backup_mysql.sh), not a --databases dump.

DUMP="${1:-}"
TARGET_DATABASE="${2:-}"
CONTAINER="${CONTAINER:-}"
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"

if [[ -z "$DUMP" || ! -f "$DUMP" ]]; then
  echo "Usage: $0 <dump.sql.gz> <target_database>" >&2
  exit 1
fi
if [[ -z "$TARGET_DATABASE" ]]; then
  echo "target_database is required" >&2
  exit 1
fi
if [[ -z "${MYSQL_ROOT_PASSWORD:-}" ]]; then
  echo "MYSQL_ROOT_PASSWORD is required" >&2
  exit 1
fi

run_mysql() {
  local args=(-uroot -p"$MYSQL_ROOT_PASSWORD")
  if [[ -n "$CONTAINER" ]]; then
    docker exec -i "$CONTAINER" mysql "${args[@]}" "$@"
  else
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" "${args[@]}" "$@"
  fi
}

run_mysql -e "CREATE DATABASE IF NOT EXISTS \`$TARGET_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
gunzip -c "$DUMP" | run_mysql "$TARGET_DATABASE"
echo "Restored $DUMP into $TARGET_DATABASE"
