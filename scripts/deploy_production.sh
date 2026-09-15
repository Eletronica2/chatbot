#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/.env.production}"
PROJECT_NAME="${PROJECT_NAME:-atende-prod}"
COMPOSE_FILE="$ROOT/docker-compose.production.yml"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/atende-ai}"
DEPLOYED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing production environment file: $ENV_FILE" >&2
  exit 1
fi

chmod 600 "$ENV_FILE"
compose=(docker compose -p "$PROJECT_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

echo "Validating Compose configuration"
"${compose[@]}" config --quiet

mysql_container="$("${compose[@]}" ps -q mysql 2>/dev/null || true)"
if [[ -n "$mysql_container" ]] && docker inspect -f '{{.State.Running}}' "$mysql_container" 2>/dev/null | grep -qx true; then
  echo "Creating pre-deploy MySQL backup"
  mysql_root_password="$("${compose[@]}" exec -T mysql printenv MYSQL_ROOT_PASSWORD)"
  mysql_database="$("${compose[@]}" exec -T mysql printenv MYSQL_DATABASE)"
  MYSQL_ROOT_PASSWORD="$mysql_root_password" \
    MYSQL_DATABASE="$mysql_database" \
    CONTAINER="$mysql_container" \
    OUT_DIR="$BACKUP_DIR" \
    "$ROOT/scripts/backup_mysql.sh" >/dev/null
  unset mysql_root_password
fi

echo "Building production images"
"${compose[@]}" build

echo "Starting production stack"
"${compose[@]}" up -d

services=(mysql flow-engine ai-engine backend-api whatsapp-gateway)
deadline=$((SECONDS + 240))
while (( SECONDS < deadline )); do
  all_healthy=true
  for service in "${services[@]}"; do
    container="$("${compose[@]}" ps -q "$service")"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container")"
    if [[ "$health" != "healthy" ]]; then
      all_healthy=false
      break
    fi
  done
  if [[ "$all_healthy" == true ]]; then
    break
  fi
  sleep 5
done

"${compose[@]}" ps
for service in "${services[@]}"; do
  container="$("${compose[@]}" ps -q "$service")"
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container")"
  if [[ "$health" != "healthy" ]]; then
    echo "Service did not become healthy: $service ($health)" >&2
    exit 1
  fi
done

curl --fail --silent --show-error http://127.0.0.1:8080/health >/dev/null

deployed_commit="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'source-copy')"
printf 'DEPLOYED_COMMIT=%s\nDEPLOYED_AT=%s\n' "$deployed_commit" "$DEPLOYED_AT"
