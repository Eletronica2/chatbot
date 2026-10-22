"""Send versioned knowledge-sync operations to the local AI through the operational HMAC client.

Run inside the ai-engine container, operations JSON on stdin (tenant + operations, max 20 per batch):
    docker compose ... exec -T ai-engine python -c "$(cat scripts/ia03_sync_knowledge.py)" < ops.json
Prints per-document results and the resulting manifest; never prints credentials or document content.
"""
import asyncio
import json
import sys

from app.clients.local_ai_client import LocalAIClient
from app.config.settings import settings


async def main(payload: dict) -> None:
    tenant = payload["tenant_id"]
    client = LocalAIClient(base_url=settings.LOCAL_AI_BASE_URL, key_id=settings.LOCAL_AI_KEY_ID,
                           secret_b64=settings.LOCAL_AI_SECRET_B64, max_attempts=1)
    try:
        result, stats = await client.sync(tenant, f"ia03-sync-{tenant}", payload["operations"])
        for item in result["results"]:
            print("sync:", item["document_id"], item["result"], {k: v for k, v in item.items() if k in ("chunks", "current_version", "chunks_removed")})
        manifest, _ = await client.manifest(tenant, f"ia03-manifest-{tenant}")
        for doc in manifest["documents"]:
            print("manifest:", doc["document_id"], f"v{doc['version']}", doc["status"], f"chunks={doc['chunks']}")
    finally:
        await client.close()


asyncio.run(main(json.load(sys.stdin)))
