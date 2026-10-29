"""Dry-run check of the Orders module inside the backend container: schema, default toggle, catalog and a simulated
order conversation (dry_run=True: no order is written, nothing is sent). Optional flow YAML on stdin also checks which
knowledge documents a publish would change on the local AI (manifest read only; no sync is sent).

    docker compose ... exec -T backend-api python -c "$(cat backend-api/scripts/orders_dry_run.py)" pizzaria_bella_massa \
        < flow-engine/app/flows/tenants/pizzaria_bella_massa/atendimento_pizzaria_delivery.yaml
"""
import asyncio
import hashlib
import sys

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.services.catalog_service import CatalogService
from app.services.flow_knowledge import build_documents
from app.services.knowledge_sync_service import KnowledgeSyncService
from app.services.order_assistant import OrderAssistant
from app.services.order_service import OrderService
from app.services.tenant_settings_service import TenantSettingsService

CHATS = [
    ["quero 2 calabresas grandes e uma coca lata", "não", "retirada", "Teste", "sim"],
    # order #2 (28/10) replayed, then the address and pending fee as they now work
    ["quero fazer um pedido",
     "Mussarela, calabresa e quatro queijos. Quero também uma coca 2 litros. E uma de prestígio.",
     "Média", "Grande", "Pequena", "Broto", "Média", "Quero um suco natural", "Laranja",
     "Substitui a coca por guaraná", "Entrega", "Sepetiba, Jardim espírito santo", "266", "Uberlândia",
     "Teste", "sim"],
    ["quero fazer um pedido", "quero 4 pizzas de quatro queijos broto", "Quero só uma", "dois refrigerantes de 2L",
     "Antartica", "Adiciona também um Guaraná 2 litros", "Tira a Coca", "não", "retirada", "Teste", "não"],
]


class NoWrites(OrderService):
    async def create(self, *args, **kwargs):  # pragma: no cover - guard
        raise AssertionError("dry run must not create orders")


async def main(tenant: str, flow_yaml: str) -> None:
    db = MySQLDatabase(settings.DATABASE_URL)
    tables = {r["t"] for r in db.fetch_all(
        "SELECT table_name AS t FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name IN "
        "('catalog_categories','catalog_products','orders','order_items','order_status_history')")}
    print("tables:", sorted(tables))
    enabled = db.fetch_one("SELECT COUNT(*) AS n FROM tenant_settings WHERE orders_enabled = 1")
    print("tenants with orders_enabled=1:", int(enabled["n"]))
    catalog = CatalogService(db)
    products = await catalog.list_products(tenant)
    print("catalog products:", len(products), "available:", sum(1 for p in products if p["available"]))
    assistant = OrderAssistant(catalog, NoWrites(db, catalog))
    for chat in CHATS:
        context = {}
        for text in chat:
            result = await assistant.handle(tenant_id=tenant, text=text, context=context,
                                            customer_phone="5500000000000", phone_number_id=None, session_id=None,
                                            dry_run=True)
            print(f"> {text}\n< {(result.reply if result else None)!r}")
            context = {"order_draft": result.draft} if result else context
    orders = db.fetch_one("SELECT COUNT(*) AS n FROM orders o JOIN tenants t ON t.id = o.tenant_id "
                          "WHERE t.external_key = %s", (tenant,))
    print("orders in DB for tenant:", int(orders["n"]))
    if flow_yaml.strip():
        documents, retired = build_documents(flow_yaml)
        sync = KnowledgeSyncService(settings.AI_ENGINE_URL, settings.INTERNAL_API_KEY, TenantSettingsService(db))
        import httpx

        async with httpx.AsyncClient(timeout=30) as client:
            manifest = await sync._manifest(client, tenant)
        for doc in documents:
            current = manifest.get(doc["document_id"]) or {}
            digest = hashlib.sha256(doc["content"].encode()).hexdigest()
            state = "unchanged" if current.get("content_hash") == digest and current.get("status") == "active" else "would_upsert"
            print("knowledge:", doc["document_id"], f"v{current.get('version')}", state)
        for doc_id in retired:
            print("knowledge retire:", doc_id, (manifest.get(doc_id) or {}).get("status", "absent"))


asyncio.run(main(sys.argv[1], sys.stdin.read() if not sys.stdin.isatty() else ""))
