#!/usr/bin/env bash
# Non-destructive restore test: uploads the latest host backup into a temporary collection,
# compares it with the live collection and deletes only the temporary collection.
set -euo pipefail
cd "$(dirname "$0")/.."
DIR=/var/backups/atende-ai-local/qdrant
snap=$(sudo ls -1t "$DIR"/*.snapshot | head -1)
meta="$snap.json"
expected=$(sudo jq -r .sha256 "$meta")
actual=$(sudo sha256sum "$snap" | cut -d' ' -f1)
echo "== $(date -Is) backup: $(basename "$snap")"
[[ "$expected" == "$actual" ]] && echo "sha256 OK ($actual)" || { echo "sha256 MISMATCH"; exit 1; }

tmp=/tmp/restore-test.snapshot
sudo cat "$snap" | docker compose exec -T ai-api sh -c "cat > $tmp"
docker compose exec -T -e SNAP="$tmp" ai-api python - <<'EOF'
import os, sys, httpx
u = "http://qdrant:6333"; h = {"api-key": os.environ["QDRANT_API_KEY"]}
live, test = "atende_knowledge", "atende_knowledge_restore_test"
c = httpx.Client(base_url=u, headers=h, timeout=120)
assert test not in [x["name"] for x in c.get("/collections").json()["result"]["collections"]], "test collection already exists"
with open(os.environ["SNAP"], "rb") as f:
    r = c.post(f"/collections/{test}/snapshots/upload", params={"priority": "snapshot", "wait": "true"}, files={"snapshot": f})
print("upload/recover:", r.status_code, r.json().get("status"))

def info(name):
    res = c.get(f"/collections/{name}").json()["result"]
    counts = {t: c.post(f"/collections/{name}/points/count", json={"exact": True, "filter": {"must": [{"key": "tenant_id", "match": {"value": t}}]}}).json()["result"]["count"]
              for t in ("pizzaria_bella_massa", "pastelaria_do_ze")}
    return {"points": res["points_count"], "per_tenant": counts, "metadata": res["config"].get("metadata"),
            "is_tenant": res["payload_schema"]["tenant_id"].get("params", {}).get("is_tenant"),
            "vectors": res["config"]["params"]["vectors"], "sparse": res["config"]["params"].get("sparse_vectors")}

a, b = info(live), info(test)
print("live:    ", a); print("restored:", b)
ok = a == b
try:
    q = c.post(f"/collections/{test}/points/scroll", json={"limit": 1, "with_vector": ["dense"], "filter": {"must": [{"key": "tenant_id", "match": {"value": "pastelaria_do_ze"}}]}}).json()["result"]["points"]
    ok = ok and len(q[0]["vector"]["dense"]) == 768
finally:
    print("delete test collection:", c.delete(f"/collections/{test}").json().get("status"))
print("collections:", [x["name"] for x in c.get("/collections").json()["result"]["collections"]])
os.remove(os.environ["SNAP"])
print("INTEGRITY OK" if ok else "INTEGRITY FAIL")
sys.exit(0 if ok else 1)
EOF
