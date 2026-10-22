#!/usr/bin/env bash
# Manual, reversible provisioning of a short-lived, tenant-scoped IA-02 smoke key.
# Run on the EC2 host with sudo after the bundle has been staged over authenticated SSH.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Execute manual e explicitamente com sudo." >&2; exit 1; }
ROOT=/opt/atende-ai
BUNDLE=/home/ec2-user/ia02-wireguard/hmac-test-credentials.json
ENV_FILE=$ROOT/.env.production
COMPOSE=$ROOT/docker-compose.production.yml
TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP=/var/backups/atende-ai-ia02/hmac-$TS

[[ -r $BUNDLE ]] || { echo "Bundle de credenciais ausente ou ilegível." >&2; exit 1; }
[[ $(stat -c %a "$BUNDLE") == 600 ]] || { echo "Bundle deve ter modo 600." >&2; exit 1; }
[[ -f $ENV_FILE && -f $COMPOSE ]] || { echo "Configuração Compose de produção ausente." >&2; exit 1; }
docker compose version >/dev/null
PROJECT=atende-prod

install -d -m 700 "$BACKUP"
cp -p "$ENV_FILE" "$BACKUP/.env.production"
chmod 600 "$BACKUP/.env.production"
echo "BACKUP=$BACKUP"

python3 - "$BUNDLE" "$ENV_FILE" <<'PY'
import base64, json, os, stat, sys, tempfile
bundle_path, env_path = sys.argv[1:]
with open(bundle_path, encoding="utf-8") as f:
    keys = json.load(f).get("keys", [])
matches = [k for k in keys if k.get("tenants") == ["pizzaria_bella_massa"]
           and set(k.get("scopes", [])) == {"respond", "knowledge:read", "knowledge:write"}]
if len(matches) != 1:
    raise SystemExit("A credencial AWS deve ficar limitada ao tenant de fixture Bella Massa.")
key = matches[0]
if len(base64.b64decode(key["secret_b64"], validate=True)) < 32:
    raise SystemExit("Credencial de teste não possui 256 bits.")
values = {}
lines = []
for line in open(env_path, encoding="utf-8"):
    if "=" in line and not line.lstrip().startswith("#"):
        name, value = line.rstrip("\n").split("=", 1)
        values[name] = value.strip().strip("\"'")
    lines.append(line.rstrip("\n"))
if values.get("LOCAL_AI_ENABLED", "false").lower() not in ("false", "0", "no", ""):
    raise SystemExit("LOCAL_AI_ENABLED já está ativo; abortando sem alteração.")
updates = {
    "LOCAL_AI_ENABLED": "false",
    "LOCAL_AI_BASE_URL": "http://10.77.0.2:8100",
    "LOCAL_AI_KEY_ID": key["key_id"],
    "LOCAL_AI_SECRET_B64": key["secret_b64"],
}
kept = [line for line in lines if not any(line.startswith(name + "=") for name in updates)]
new = "\n".join(kept + [f"{name}={value}" for name, value in updates.items()]) + "\n"
st = os.stat(env_path)
fd, tmp = tempfile.mkstemp(prefix=".ia02-hmac-", dir=os.path.dirname(env_path), text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(new)
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, stat.S_IMODE(st.st_mode))
    os.chown(tmp, st.st_uid, st.st_gid)
    os.replace(tmp, env_path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
os.chmod(env_path, 0o600)
print("AWS_TEST_KEY_ID=" + key["key_id"])
print("AWS_TEST_KEY_TENANT=pizzaria_bella_massa")
print("LOCAL_AI_ENABLED=false")
PY

cd "$ROOT"
if ! docker compose -p "$PROJECT" -f "$COMPOSE" --env-file "$ENV_FILE" up --no-build -d --no-deps --force-recreate ai-engine; then
  cp -p "$BACKUP/.env.production" "$ENV_FILE"
  docker compose -p "$PROJECT" -f "$COMPOSE" --env-file "$ENV_FILE" up --no-build -d --no-deps --force-recreate ai-engine || true
  echo "Falha ao recriar somente ai-engine; .env.production restaurado de $BACKUP" >&2
  exit 1
fi

healthy=0
for _ in $(seq 1 36); do
  state=$(docker inspect --format '{{.State.Health.Status}}' atende-prod-ai-engine-1 2>/dev/null || true)
  if [[ $state == healthy ]]; then healthy=1; break; fi
  sleep 5
done
if [[ $healthy != 1 ]]; then
  cp -p "$BACKUP/.env.production" "$ENV_FILE"
  docker compose -p "$PROJECT" -f "$COMPOSE" --env-file "$ENV_FILE" up --no-build -d --no-deps --force-recreate ai-engine || true
  echo "Healthcheck do ai-engine falhou; .env.production restaurado de $BACKUP" >&2
  exit 1
fi

docker exec atende-prod-ai-engine-1 python -c 'from app.config.settings import settings; assert settings.LOCAL_AI_ENABLED is False; assert settings.LOCAL_AI_BASE_URL == "http://10.77.0.2:8100"; assert settings.LOCAL_AI_KEY_ID and settings.LOCAL_AI_SECRET_B64 and len(settings.LOCAL_AI_SECRET_B64) >= 40; print("AI_ENGINE_HEALTHY=true LOCAL_AI_ENABLED=false HMAC_CONFIGURED=true")'
echo "Rollback manual: cp '$BACKUP/.env.production' '$ENV_FILE' && cd '$ROOT' && docker compose -p '$PROJECT' -f '$COMPOSE' --env-file '$ENV_FILE' up --no-build -d --no-deps --force-recreate ai-engine"
