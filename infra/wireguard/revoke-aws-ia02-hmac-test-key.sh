#!/usr/bin/env bash
# Remove only the temporary Bella smoke identity from the AWS AI Engine configuration.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Execute manual e explicitamente com sudo." >&2; exit 1; }

ROOT=/opt/atende-ai
ENV_FILE=$ROOT/.env.production
COMPOSE=$ROOT/docker-compose.production.yml
PROJECT=atende-prod
CONTAINER=atende-prod-ai-engine-1
BUNDLE=/home/ec2-user/ia02-wireguard/hmac-test-credentials.json
BACKUP_ROOT=/var/backups/atende-ai-ia02
TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP=$BACKUP_ROOT/hmac-revoke-$TS

[[ -r $BUNDLE && -f $ENV_FILE && -f $COMPOSE ]] || { echo "Bundle/configuração ausente." >&2; exit 1; }
[[ $(stat -c %a "$BUNDLE") == 600 ]] || { echo "Bundle deve ter modo 600." >&2; exit 1; }
install -d -m 700 "$BACKUP"
cp -p "$ENV_FILE" "$BACKUP/.env.production"
chmod 600 "$BACKUP/.env.production"

python3 - "$BUNDLE" "$ENV_FILE" <<'PY'
import json, os, stat, sys, tempfile
bundle_path, env_path = sys.argv[1:]
bundle = json.load(open(bundle_path, encoding="utf-8"))
matches = [k for k in bundle.get("keys", []) if k.get("tenants") == ["pizzaria_bella_massa"]
           and set(k.get("scopes", [])) == {"respond", "knowledge:read", "knowledge:write"}]
if len(matches) != 1: raise SystemExit("Bundle Bella não corresponde à identidade temporária esperada.")
key_id = matches[0]["key_id"]
lines = open(env_path, encoding="utf-8").read().splitlines()
values = {}
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        name, value = line.split("=", 1); values[name] = value.strip().strip("\"'")
enabled = values.get("LOCAL_AI_ENABLED", "false").lower()
if enabled not in ("false", "0", "no", ""):
    raise SystemExit("LOCAL_AI_ENABLED não está false; abortando sem alteração.")
current_id = values.get("LOCAL_AI_KEY_ID", "")
if current_id not in ("", key_id):
    raise SystemExit("Outra identidade está configurada; preservando e abortando.")
if current_id == "" and values.get("LOCAL_AI_SECRET_B64"):
    raise SystemExit("Segredo configurado sem identidade correspondente; abortando para revisão.")
remove = {"LOCAL_AI_KEY_ID", "LOCAL_AI_SECRET_B64"}
if current_id == key_id and values.get("LOCAL_AI_BASE_URL") == "http://10.77.0.2:8100":
    remove.add("LOCAL_AI_BASE_URL")
new_lines = [line for line in lines if not any(line.startswith(name + "=") for name in remove)]
st = os.stat(env_path); fd, tmp = tempfile.mkstemp(prefix=".ia02-revoke-", dir=os.path.dirname(env_path), text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines) + "\n"); f.flush(); os.fsync(f.fileno())
    os.chmod(tmp, stat.S_IMODE(st.st_mode)); os.chown(tmp, st.st_uid, st.st_gid); os.replace(tmp, env_path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
os.chmod(env_path, 0o600)
print("AWS_TEMP_KEY_REMOVED=" + str(current_id == key_id))
print("LOCAL_AI_ENABLED=" + values.get("LOCAL_AI_ENABLED", "false"))
PY

rollback() {
  set +e
  cp -p "$BACKUP/.env.production" "$ENV_FILE"
  docker compose -p "$PROJECT" -f "$COMPOSE" --env-file "$ENV_FILE" up --no-build -d --no-deps --force-recreate ai-engine
  echo "Rollback de configuração executado; backup=$BACKUP"
}

cd "$ROOT"
if ! docker compose -p "$PROJECT" -f "$COMPOSE" --env-file "$ENV_FILE" up --no-build -d --no-deps --force-recreate ai-engine; then
  rollback; exit 1
fi
healthy=0
for _ in $(seq 1 36); do
  state=$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || true)
  if [[ $state == healthy ]]; then healthy=1; break; fi
  sleep 5
done
if [[ $healthy != 1 ]]; then rollback; exit 1; fi
if ! docker exec "$CONTAINER" python -c 'from app.config.settings import settings; assert settings.LOCAL_AI_ENABLED is False; assert not settings.LOCAL_AI_KEY_ID and not settings.LOCAL_AI_SECRET_B64; print("AI_ENGINE_HEALTHY=true LOCAL_AI_ENABLED=false HMAC_TEST_KEY_ABSENT=true")'; then
  rollback; exit 1
fi

# Verify the old test key can no longer authenticate over the private VPN path.
cat "$BUNDLE" | docker exec -i "$CONTAINER" python -c 'import base64,hashlib,hmac,json,secrets,sys,time,httpx; b=json.load(sys.stdin); k=next(x for x in b["keys"] if x.get("tenants")==["pizzaria_bella_massa"] and set(x.get("scopes",[]))=={"respond","knowledge:read","knowledge:write"}); tenant=k["tenants"][0]; path="/v1/knowledge/search"; rid="revoke-check-"+secrets.token_hex(4); body=b"{\"query\":\"revocation check\",\"top_k\":1}"; ts=str(int(time.time())); nonce=secrets.token_urlsafe(18); canonical="\n".join(["POST",path,ts,nonce,tenant,rid,hashlib.sha256(body).hexdigest()]).encode(); sig=hmac.new(base64.b64decode(k["secret_b64"]),canonical,hashlib.sha256).hexdigest(); headers={"content-type":"application/json","x-aa-key-id":k["key_id"],"x-aa-timestamp":ts,"x-aa-nonce":nonce,"x-aa-tenant":tenant,"x-aa-request-id":rid,"x-aa-signature":sig}; r=httpx.post("http://10.77.0.2:8100"+path,content=body,headers=headers,timeout=10); d=r.json(); code=(d.get("detail") or {}).get("error_code","") if isinstance(d,dict) else ""; assert r.status_code==401 and code=="key_unknown",f"unexpected status/error: {r.status_code}/{code}"; print("OLD_TEST_KEY_REJECTED=true error=key_unknown")' || { rollback; exit 1; }

# Sanitize only AWS .env.production rollback snapshots containing this test identity.
python3 - "$BUNDLE" "$BACKUP_ROOT" <<'PY'
import json, os, stat, sys, tempfile
bundle_path, root = sys.argv[1:]
keys = json.load(open(bundle_path, encoding="utf-8"))["keys"]
ids = {k["key_id"] for k in keys}
changed = 0
from pathlib import Path
root = Path(root)
for path in root.glob("hmac-*/.env.production"):
    lines = path.read_text(encoding="utf-8").splitlines(); values = {}
    for line in lines:
        if "=" in line and not line.lstrip().startswith("#"):
            name, value = line.split("=", 1); values[name] = value.strip().strip("\"'")
    if values.get("LOCAL_AI_KEY_ID") not in ids: continue
    new_lines = [line for line in lines if not line.startswith(("LOCAL_AI_KEY_ID=", "LOCAL_AI_SECRET_B64="))]
    if values.get("LOCAL_AI_BASE_URL") == "http://10.77.0.2:8100":
        new_lines = [line for line in new_lines if not line.startswith("LOCAL_AI_BASE_URL=")]
    st = path.stat(); fd, tmp = tempfile.mkstemp(prefix=".ia02-scrub-", dir=str(path.parent), text=True)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines) + "\n"); f.flush(); os.fsync(f.fileno())
    os.chmod(tmp, stat.S_IMODE(st.st_mode)); os.chown(tmp, st.st_uid, st.st_gid); os.replace(tmp, path)
    changed += 1
print("AWS_ENV_BACKUPS_SANITIZED=" + str(changed))
PY

rm -f "$BUNDLE" /home/ec2-user/ia02-wireguard/ia02_hmac_smoke.py
echo "AWS_HMAC_TEST_KEY=revoked; private API returned 401 key_unknown"
echo "AI_ENGINE_HEALTHY=true LOCAL_AI_ENABLED=false"
echo "BACKUP=$BACKUP"
