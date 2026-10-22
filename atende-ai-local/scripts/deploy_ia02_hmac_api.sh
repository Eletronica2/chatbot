#!/usr/bin/env bash
# Manual, reversible deployment of the IA-02 HMAC API source to the local Ubuntu host.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Execute manual e explicitamente com sudo." >&2; exit 1; }
ROOT=/opt/atende-ai-local
SOURCE=/home/atendeai/ia02-wireguard/ai-api-source.tar.gz
BUNDLE=/home/atendeai/ia02-wireguard/hmac-test-credentials.json
ENV_FILE=$ROOT/.env
COMPOSE=$ROOT/docker-compose.yml
PROJECT=atende-ai-local
CONTAINER=atende-ai-local-ai-api-1
IMAGE=atende-ai-local/ai-api:0.1.0
TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP=/var/backups/atende-ai-local/ia02-api-$TS
OLD_DIR=$ROOT/.ia02-ai-api-old-$TS
STAGE=$ROOT/.ia02-ai-api-stage-$TS

[[ -r $SOURCE && -r $BUNDLE && -f $ENV_FILE && -f $COMPOSE ]] || {
  echo "Fonte, bundle, Compose ou .env ausente." >&2; exit 1;
}
[[ $(stat -c %a "$BUNDLE") == 600 ]] || { echo "Bundle deve ter modo 600." >&2; exit 1; }
install -d -m 700 "$BACKUP"
chmod 600 "$ENV_FILE"
cp -p "$ENV_FILE" "$BACKUP/.env"
tar -czf "$BACKUP/ai-api-before.tar.gz" -C "$ROOT" ai-api
chmod 600 "$BACKUP/ai-api-before.tar.gz" "$BACKUP/.env"

old_image=$(docker image inspect --format '{{.Id}}' "$IMAGE")
docker image tag "$old_image" "atende-ai-local/ai-api:rollback-$TS"
mkdir -m 700 "$STAGE"
tar -xzf "$SOURCE" -C "$STAGE"
[[ -f $STAGE/ai-api/app/security/service_auth.py ]] || {
  echo "Pacote não contém o autenticador HMAC esperado." >&2; exit 1;
}
grep -q '"/v1/knowledge/sync"' "$STAGE/ai-api/app/api/routes.py" || {
  echo "Pacote não contém a rota versionada de sync." >&2; exit 1;
}

rollback() {
  set +e
  if [[ -d $OLD_DIR ]]; then
    rm -rf "$ROOT/ai-api"
    mv "$OLD_DIR" "$ROOT/ai-api"
  fi
  docker image tag "$old_image" "$IMAGE"
  docker compose -p "$PROJECT" -f "$COMPOSE" up --no-build -d --no-deps --force-recreate ai-api
  echo "Rollback aplicado; backup=$BACKUP"
}

mv "$ROOT/ai-api" "$OLD_DIR"
mv "$STAGE/ai-api" "$ROOT/ai-api"
if ! docker compose -p "$PROJECT" -f "$COMPOSE" build ai-api; then
  rollback
  exit 1
fi
if ! docker compose -p "$PROJECT" -f "$COMPOSE" up --no-build -d --no-deps --force-recreate ai-api; then
  rollback
  exit 1
fi

ready=0
for _ in $(seq 1 36); do
  if curl -fsS --max-time 3 http://127.0.0.1:8100/health >/dev/null; then ready=1; break; fi
  sleep 5
done
if [[ $ready != 1 ]]; then
  rollback
  exit 1
fi

expected_key_id=$(python3 - "$BUNDLE" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    keys = json.load(f)["keys"]
matches = [k for k in keys if k.get("tenants") == ["pizzaria_bella_massa"]
           and set(k.get("scopes", [])) == {"respond", "knowledge:read", "knowledge:write"}]
if len(matches) != 1:
    raise SystemExit("Bundle Bella inválido.")
print(matches[0]["key_id"])
PY
)
if ! docker exec "$CONTAINER" python -c 'import os,sys,json; from app.security.service_auth import parse_keys; keys=parse_keys(os.environ.get("SERVICE_KEYS_JSON","[]")); expected=sys.argv[1]; assert expected in keys; print("HMAC_KEY_MATCH=true")' "$expected_key_id"; then
  rollback
  exit 1
fi
if ! docker exec "$CONTAINER" python -c 'import httpx; p=httpx.get("http://127.0.0.1:8100/openapi.json",timeout=5).json().get("paths",{}); assert "/v1/knowledge/sync" in p and "/v1/knowledge/manifest" in p; print("HMAC_API_ROUTES=true")'; then
  rollback
  exit 1
fi

mv "$OLD_DIR" "$BACKUP/ai-api-before"
rmdir "$STAGE"
echo "LOCAL_AI_API=healthy HMAC_KEY_MATCH=true HMAC_API_ROUTES=true LOCAL_AI_ENABLED_unchanged=true"
echo "BACKUP=$BACKUP"
echo "Rollback manual: cp '$BACKUP/.env' '$ENV_FILE' && rm -rf '$ROOT/ai-api' && tar -xzf '$BACKUP/ai-api-before.tar.gz' -C '$ROOT' && docker image tag '$old_image' '$IMAGE' && cd '$ROOT' && docker compose -p '$PROJECT' -f '$COMPOSE' up --no-build -d --no-deps --force-recreate ai-api"
