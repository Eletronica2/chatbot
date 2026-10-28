"""Keeps the local AI knowledge base in sync with published flows and the orders catalog.

Talks to the ai-engine internal proxy (/ai/local/knowledge/*), which signs requests to the local AI with HMAC.
Only documents whose content hash changed are sent; versions increase monotonically per document.
"""
from __future__ import annotations

import asyncio
import hashlib
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

import httpx

from app.domain import orders as order_domain
from app.services.flow_knowledge import build_documents

logger = logging.getLogger(__name__)

BATCH = 20
CATALOG_DOCUMENT_ID = "catalogo-pedidos"


def catalog_document(tenant_name: str, products: List[Dict[str, Any]]) -> Dict[str, str]:
    groups: Dict[str, List[str]] = {}
    unavailable: List[str] = []
    for product in products:
        if not product.get("available"):
            unavailable.append(product["name"])
            continue
        if product.get("variants"):
            price = ", ".join(f"{v['name']} {order_domain.money(v['price_cents'])}" for v in product["variants"])
        else:
            price = order_domain.money(product.get("price_cents") or 0)
        groups.setdefault(product.get("category_name") or "Outros", []).append(f"- {product['name']}: {price}")
    title = f"Cardápio para pedidos {tenant_name}".strip()
    parts = [f"# {title}", "Produtos disponíveis para pedido pelo WhatsApp (preços do cadastro da loja)."]
    for category, lines in groups.items():
        parts.append(f"## {category}\n" + "\n".join(lines))
    if unavailable:
        parts.append("Indisponíveis no momento: " + ", ".join(unavailable) + ".")
    parts.append("Para pedir, o cliente informa itens, quantidade, entrega ou retirada e confirma o resumo com SIM.")
    return {"document_id": CATALOG_DOCUMENT_ID, "title": title, "content": "\n\n".join(parts) + "\n"}


class KnowledgeSyncService:
    def __init__(self, base_url: str, internal_api_key: str, tenant_settings_service: Any, timeout: float = 60.0):
        self.base_url = base_url.rstrip("/")
        self.headers = {"x-internal-api-key": internal_api_key}
        self.tenant_settings = tenant_settings_service
        self.timeout = timeout
        self._tasks: set[asyncio.Task] = set()

    async def _local_ai_enabled(self, tenant_id: str) -> bool:
        settings = await self.tenant_settings.get_or_create(tenant_id)
        return bool(settings.local_ai_enabled)

    async def _manifest(self, client: httpx.AsyncClient, tenant_id: str) -> Dict[str, Dict[str, Any]]:
        response = await client.get(f"{self.base_url}/ai/local/knowledge/manifest", params={"tenant_id": tenant_id},
                                    headers=self.headers)
        response.raise_for_status()
        return {doc["document_id"]: doc for doc in (response.json() or {}).get("documents") or []}

    async def sync(
        self, tenant_id: str, documents: List[Dict[str, str]], retire: Optional[List[str]] = None, *, reason: str,
    ) -> Dict[str, Any]:
        """Upsert changed documents and delete retired ones. Returns a content-free summary."""
        if not await self._local_ai_enabled(tenant_id):
            return {"status": "skipped", "reason": "local_ai_disabled"}
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        summary: Dict[str, Any] = {"status": "ok", "reason": reason, "unchanged": 0, "results": []}
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            manifest = await self._manifest(client, tenant_id)
            operations: List[Dict[str, Any]] = []
            for doc in documents:
                digest = hashlib.sha256(doc["content"].encode("utf-8")).hexdigest()
                current = manifest.get(doc["document_id"])
                if current and current.get("status") == "active" and current.get("content_hash") == digest:
                    summary["unchanged"] += 1
                    continue
                operations.append({
                    "op": "upsert", "document_id": doc["document_id"], "version": int((current or {}).get("version") or 0) + 1,
                    "title": doc["title"], "content": doc["content"], "content_hash": digest, "updated_at": now,
                    "status": "active", "content_type": "markdown",
                })
            for doc_id in retire or []:
                current = manifest.get(doc_id)
                if current and current.get("status") != "deleted":
                    operations.append({"op": "delete", "document_id": doc_id,
                                       "version": int(current.get("version") or 0) + 1, "updated_at": now,
                                       "status": "deleted"})
            for start in range(0, len(operations), BATCH):
                response = await client.post(
                    f"{self.base_url}/ai/local/knowledge/sync", headers=self.headers,
                    json={"tenant_id": tenant_id, "request_id": f"{reason}-{tenant_id}-{now}-{start}"[:120],
                          "operations": operations[start:start + BATCH]},
                )
                response.raise_for_status()
                summary["results"].extend(
                    {"document_id": r.get("document_id"), "result": r.get("result"), "version": r.get("version")}
                    for r in (response.json() or {}).get("results") or []
                )
        return summary

    async def sync_flow(self, tenant_id: str, yaml_content: str) -> Dict[str, Any]:
        documents, retired = build_documents(yaml_content)
        if not documents and not retired:
            return {"status": "skipped", "reason": "flow_without_knowledge_section"}
        return await self.sync(tenant_id, documents, retired, reason="flow-publish")

    async def sync_catalog(self, tenant_id: str, *, tenant_name: str, products: List[Dict[str, Any]],
                           orders_enabled: bool) -> Dict[str, Any]:
        if not orders_enabled:
            return await self.sync(tenant_id, [], [CATALOG_DOCUMENT_ID], reason="catalog-disabled")
        return await self.sync(tenant_id, [catalog_document(tenant_name, products)], reason="catalog")

    def schedule(self, coro: Any, *, label: str, on_done: Any = None) -> None:
        """Run a sync in the background so publishing never waits on the local AI."""
        async def _runner() -> None:
            try:
                result = await coro
            except Exception as exc:
                logger.warning("knowledge_sync_failed label=%s error=%s", label, type(exc).__name__)
                result = {"status": "failed", "error": type(exc).__name__}
            else:
                logger.info("knowledge_sync label=%s status=%s changed=%s unchanged=%s", label, result.get("status"),
                            len(result.get("results") or []), result.get("unchanged", 0))
            if on_done is not None:
                try:
                    await on_done(result)
                except Exception:
                    logger.exception("knowledge_sync_callback_failed label=%s", label)

        task = asyncio.create_task(_runner())
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)
