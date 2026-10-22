#!/usr/bin/env bash
# Manual, reversible provisioning of short-lived IA-02 test credentials.
# Run on the local Ubuntu host with sudo after the bundle has been staged over SSH.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Execute manual e explicitamente com sudo." >&2; exit 1; }
ROOT=/opt/atende-ai-local
BUNDLE=/home/atendeai/ia02-wireguard/hmac-test-credentials.json
ENV_FILE=$ROOT/.env
TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP=/var/backups/atende-ai-local/ia02-hmac-$TS

[[ -r $BUNDLE ]] || { echo "Bundle de credenciais ausente ou ilegível." >&2; exit 1; }
[[ $(stat -c %a "$BUNDLE") == 600 ]] || { echo "Bundle deve ter modo 600." >&2; exit 1; }
[[ -f $ENV_FILE ]] || { echo "Arquivo .env não encontrado." >&2; exit 1; }
command -v docker >/dev/null && docker compose version >/dev/null

install -d -m 700 "$BACKUP"
cp -p "$ENV_FILE" "$BACKUP/.env"
chmod 600 "$BACKUP/.env"
echo "BACKUP=$BACKUP"

python3 - "$BUNDLE" "$ENV_FILE" <<'PY'
import json, os, shlex, stat, sys, tempfile
bundle_path, env_path = sys.argv[1:]
with open(bundle_path, encoding="utf-8") as f:
    bundle = json.load(f)
keys = bundle.get("keys")
if not isinstance(keys, list) or len(keys) < 3:
    raise SystemExit("Esperadas as credenciais de teste por tenant e a credencial negativa.")
expected = {
    "pizzaria_bella_massa": {"respond", "knowledge:read", "knowledge:write"},
    "pastelaria_do_ze": {"respond", "knowledge:read", "knowledge:write"},
}
by_id = {k.get("key_id"): k for k in keys if isinstance(k, dict)}
selected = {}
for tenant, scopes in expected.items():
    matches = [k for k in keys if k.get("tenants") == [tenant] and set(k.get("scopes", [])) == scopes]
    if len(matches) != 1:
        raise SystemExit("Esperada exatamente uma credencial full-scope restrita a cada tenant de fixture.")
    selected[matches[0]["key_id"]] = matches[0]
readonly = [k for k in keys if k.get("tenants") == ["pizzaria_bella_massa"]
            and set(k.get("scopes", [])) == {"respond"}]
if len(readonly) != 1 or len(keys) != 3:
    raise SystemExit("Esperada uma credencial read-only e três chaves de teste no total.")
selected[readonly[0]["key_id"]] = readonly[0]
for key_id, key in selected.items():
    tenant = key["tenants"][0]
    import base64
    secret = base64.b64decode(key.get("secret_b64", ""), validate=True)
    if len(secret) < 32:
        raise SystemExit("Credencial de teste não possui 256 bits.")
old = open(env_path, encoding="utf-8").read()
lines = old.splitlines()
existing = []
kept = []
for line in lines:
    if line.startswith("SERVICE_KEYS_JSON="):
        raw = line.split("=", 1)[1].strip()
        if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
            raw = raw[1:-1]
        if raw:
            existing = json.loads(raw)
    else:
        kept.append(line)
merged = {item["key_id"]: item for item in existing}
merged.update(selected)
value = shlex.quote(json.dumps(list(merged.values()), separators=(",", ":")))
new = "\n".join(kept + ["SERVICE_KEYS_JSON=" + value]) + "\n"
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
print("TEST_KEY_COUNT=" + str(len(selected)))
print("TEST_KEY_TENANTS=pizzaria_bella_massa,pastelaria_do_ze")
print("TEST_KEY_SCOPES=tenant-specific; readonly key included for negative scope test")
PY

cd "$ROOT"
if ! docker compose up -d --no-deps --force-recreate ai-api; then
  cp -p "$BACKUP/.env" "$ENV_FILE"
  docker compose up -d --no-deps --force-recreate ai-api || true
  echo "Falha ao recriar ai-api; .env restaurado de $BACKUP" >&2
  exit 1
fi

ready=0
for _ in $(seq 1 36); do
  if curl -fsS --max-time 3 http://127.0.0.1:8100/health >/dev/null; then ready=1; break; fi
  sleep 5
done
if [[ $ready != 1 ]]; then
  cp -p "$BACKUP/.env" "$ENV_FILE"
  docker compose up -d --no-deps --force-recreate ai-api || true
  echo "Healthcheck local falhou; .env restaurado de $BACKUP" >&2
  exit 1
fi
echo "LOCAL_AI_API=healthy"
echo "LOCAL_AI_ENABLED não se aplica ao servidor local; nenhum tenant real foi habilitado."
echo "Rollback manual: cp '$BACKUP/.env' '$ENV_FILE' && cd '$ROOT' && docker compose up -d --no-deps --force-recreate ai-api"
