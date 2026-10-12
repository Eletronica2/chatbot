#!/usr/bin/env bash
# Qdrant snapshot backup (non-destructive). Copies the snapshot out of the container and verifies its checksum.
# NOTE: the destination lives on the same physical disk; copy BACKUP_DIR to external storage for real protection.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

COLLECTION=${COLLECTION:-atende_knowledge}
BACKUP_DIR=${BACKUP_DIR:-/var/backups/atende-ai-local/qdrant}
KEEP=${KEEP:-7}
sudo mkdir -p "$BACKUP_DIR"

q() { docker compose exec -T ai-api python -c "
import httpx,os,sys
r=httpx.request(sys.argv[1],'http://qdrant:6333'+sys.argv[2],headers={'api-key':os.environ['QDRANT_API_KEY']},timeout=600)
r.raise_for_status(); sys.stdout.write(r.text)" "$@"; }

points=$(q GET "/collections/$COLLECTION" | jq '.result.points_count')
snap=$(q POST "/collections/$COLLECTION/snapshots?wait=true" | jq -r '.result.name')
checksum=$(q GET "/collections/$COLLECTION/snapshots" | jq -r --arg n "$snap" '.result[] | select(.name==$n) | .checksum')
cid=$(docker compose ps -q qdrant)
sudo docker cp "$cid:/qdrant/snapshots/$COLLECTION/$snap" "$BACKUP_DIR/$snap"
actual=$(sudo sha256sum "$BACKUP_DIR/$snap" | cut -d' ' -f1)
[[ "$actual" == "$checksum" ]] || { echo "checksum divergente: $actual != $checksum"; exit 1; }
echo "{\"collection\":\"$COLLECTION\",\"snapshot\":\"$snap\",\"points\":$points,\"sha256\":\"$actual\",\"created_at\":\"$(date -Is)\"}" \
  | sudo tee "$BACKUP_DIR/$snap.json"

# Keep only the newest $KEEP snapshots inside Qdrant and on disk.
q GET "/collections/$COLLECTION/snapshots" | jq -r '.result | sort_by(.creation_time) | reverse | .['"$KEEP"':][] .name' |
  while read -r old; do q DELETE "/collections/$COLLECTION/snapshots/$old" >/dev/null; done
ls -1t "$BACKUP_DIR"/*.snapshot 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r f; do sudo rm -f "$f" "$f.json"; done
echo "backup ok: $BACKUP_DIR/$snap"
