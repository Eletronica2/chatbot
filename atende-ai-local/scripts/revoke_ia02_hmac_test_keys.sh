#!/usr/bin/env bash
# Remove only the temporary IA-02 test identities from local SERVICE_KEYS_JSON.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Execute manual e explicitamente com sudo." >&2; exit 1; }

ROOT=/opt/atende-ai-local
ENV_FILE=$ROOT/.env
BUNDLE=/home/atendeai/ia02-wireguard/hmac-test-credentials.json
COMPOSE=$ROOT/docker-compose.yml
PROJECT=atende-ai-local
CONTAINER=atende-ai-local-ai-api-1
BACKUP_ROOT=/var/backups/atende-ai-local
TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP=$BACKUP_ROOT/ia02-hmac-revoke-$TS

[[ -r $BUNDLE && -f $ENV_FILE && -f $COMPOSE ]] || { echo "Bundle/configuração ausente." >&2; exit 1; }
[[ $(stat -c %a "$BUNDLE") == 600 ]] || { echo "Bundle deve ter modo 600." >&2; exit 1; }
install -d -m 700 "$BACKUP"
cp -p "$ENV_FILE" "$BACKUP/.env"
chmod 600 "$BACKUP/.env"

# Edit exactly the three IDs in the test bundle; preserve every other service key and .env setting.
python3 - "$BUNDLE" "$ENV_FILE" <<'PY'
import json, os, shlex, stat, sys, tempfile
bundle_path, env_path = sys.argv[1:]
with open(bundle_path, encoding="utf-8") as f:
    bundle = json.load(f)
keys = bundle.get("keys", [])
expected = {
    ("pizzaria_bella_massa", frozenset({"respond", "knowledge:read", "knowledge:write"})),
    ("pastelaria_do_ze", frozenset({"respond", "knowledge:read", "knowledge:write"})),
    ("pizzaria_bella_massa", frozenset({"respond"})),
}
observed = {(k.get("tenants", [None])[0], frozenset(k.get("scopes", []))) for k in keys}
if len(keys) != 3 or observed != expected:
    raise SystemExit("Bundle não corresponde às três identidades IA-02 esperadas.")
ids = {k["key_id"] for k in keys}
lines = open(env_path, encoding="utf-8").read().splitlines()
raw = next((line.split("=", 1)[1].strip() for line in lines if line.startswith("SERVICE_KEYS_JSON=")), "[]")
if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
    raw = raw[1:-1]
current = json.loads(raw or "[]")
removed = [k for k in current if k.get("key_id") in ids]
if len({k.get("key_id") for k in removed}) not in (0, 3):
    raise SystemExit("Configuração parcial detectada; abortando para revisão manual.")
remaining = [k for k in current if k.get("key_id") not in ids]
new_value = shlex.quote(json.dumps(remaining, separators=(",", ":")))
new_lines = [line for line in lines if not line.startswith("SERVICE_KEYS_JSON=")]
new_lines.append("SERVICE_KEYS_JSON=" + new_value)
st = os.stat(env_path)
fd, tmp = tempfile.mkstemp(prefix=".ia02-revoke-", dir=os.path.dirname(env_path), text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines) + "\n")
        f.flush(); os.fsync(f.fileno())
    os.chmod(tmp, stat.S_IMODE(st.st_mode)); os.chown(tmp, st.st_uid, st.st_gid)
    os.replace(tmp, env_path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
os.chmod(env_path, 0o600)
print("TEMP_TEST_KEYS_REMOVED=" + str(len(removed)))
print("OTHER_SERVICE_KEYS_PRESERVED=" + str(len(remaining)))
PY

rollback() {
  set +e
  cp -p "$BACKUP/.env" "$ENV_FILE"
  docker compose -p "$PROJECT" -f "$COMPOSE" up --no-build -d --no-deps --force-recreate ai-api
  echo "Rollback de configuração executado; backup=$BACKUP"
}

cd "$ROOT"
if ! docker compose -p "$PROJECT" -f "$COMPOSE" up --no-build -d --no-deps --force-recreate ai-api; then
  rollback; exit 1
fi
ready=0
for _ in $(seq 1 36); do
  if curl -fsS --max-time 3 http://127.0.0.1:8100/health >/dev/null; then ready=1; break; fi
  sleep 5
done
if [[ $ready != 1 ]]; then rollback; exit 1; fi
curl -fsS --max-time 20 http://127.0.0.1:8100/ready | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r.get("ready") is True; print("LOCAL_AI_READY=true")' || { rollback; exit 1; }

# Verify the retired Bella key is unknown (not merely expired), without exposing its secret.
cat "$BUNDLE" | docker exec -i "$CONTAINER" python -c 'import base64,hashlib,hmac,json,secrets,sys,time,httpx; b=json.load(sys.stdin); k=next(x for x in b["keys"] if x.get("tenants")==["pizzaria_bella_massa"] and set(x.get("scopes",[]))=={"respond","knowledge:read","knowledge:write"}); tenant=k["tenants"][0]; path="/v1/knowledge/search"; rid="revoke-check-"+secrets.token_hex(4); body=b"{\"query\":\"revocation check\",\"top_k\":1}"; ts=str(int(time.time())); nonce=secrets.token_urlsafe(18); canonical="\n".join(["POST",path,ts,nonce,tenant,rid,hashlib.sha256(body).hexdigest()]).encode(); sig=hmac.new(base64.b64decode(k["secret_b64"]),canonical,hashlib.sha256).hexdigest(); headers={"content-type":"application/json","x-aa-key-id":k["key_id"],"x-aa-timestamp":ts,"x-aa-nonce":nonce,"x-aa-tenant":tenant,"x-aa-request-id":rid,"x-aa-signature":sig}; r=httpx.post("http://127.0.0.1:8100"+path,content=body,headers=headers,timeout=10); d=r.json(); code=(d.get("detail") or {}).get("error_code","") if isinstance(d,dict) else ""; assert r.status_code==401 and code=="key_unknown",f"unexpected status/error: {r.status_code}/{code}"; print("OLD_TEST_KEY_REJECTED=true error=key_unknown")' || { rollback; exit 1; }
docker exec "$CONTAINER" python -c 'import time; from app.security.service_auth import NonceCache; c=NonceCache(30); now=time.time(); assert c.check_and_add("ia02-replay-audit",now); assert not c.check_and_add("ia02-replay-audit",now); print("REPLAY_PROTECTION_CODE=active")' || { rollback; exit 1; }

# Scrub only these temporary identities from protected .env rollback snapshots; retain all other settings/keys.
python3 - "$BUNDLE" "$BACKUP_ROOT" <<'PY'
import json, os, shlex, stat, sys, tempfile
from pathlib import Path
bundle_path, root = sys.argv[1:]
ids = {k["key_id"] for k in json.load(open(bundle_path, encoding="utf-8"))["keys"]}
changed = 0
root = Path(root)
candidates = list(root.glob("ia02-api-*/.env")) + list(root.glob("ia02-hmac-revoke-*/.env"))
for path in candidates:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
        idx = next((i for i, line in enumerate(lines) if line.startswith("SERVICE_KEYS_JSON=")), None)
        if idx is None: continue
        raw = lines[idx].split("=", 1)[1].strip()
        if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'": raw = raw[1:-1]
        current = json.loads(raw or "[]")
        remaining = [item for item in current if item.get("key_id") not in ids]
        if len(remaining) == len(current): continue
        st = path.stat(); lines[idx] = "SERVICE_KEYS_JSON=" + shlex.quote(json.dumps(remaining, separators=(",", ":")))
        fd, tmp = tempfile.mkstemp(prefix=".ia02-scrub-", dir=str(path.parent), text=True)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n"); f.flush(); os.fsync(f.fileno())
        os.chmod(tmp, stat.S_IMODE(st.st_mode)); os.chown(tmp, st.st_uid, st.st_gid); os.replace(tmp, path)
        changed += 1
    except (OSError, ValueError, StopIteration, KeyError, TypeError) as exc:
        raise SystemExit(f"Falha ao verificar snapshot {path}: {type(exc).__name__}")
print("BACKUP_ENV_SNAPSHOTS_SANITIZED=" + str(changed))
PY

# Remove only the staged bundle and source archive created for this test/deployment.
rm -f "$BUNDLE" /home/atendeai/ia02-wireguard/ai-api-source.tar.gz
echo "LOCAL_HMAC_TEST_KEYS=revoked; old Bella key returned 401 key_unknown"
echo "WIREGUARD_OLLAMA_QDRANT_PRESERVED=true"
echo "BACKUP=$BACKUP"
