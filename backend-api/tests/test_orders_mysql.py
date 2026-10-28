"""Orders module against a disposable MySQL (BILLING_V2_TEST_DATABASE_URL); never production."""
import asyncio
import os
import uuid

import pytest

DB_URL = os.environ.get("BILLING_V2_TEST_DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DB_URL, reason="BILLING_V2_TEST_DATABASE_URL not set")

if DB_URL:
    from app.db.mysql import MySQLDatabase
    from app.services.catalog_service import CatalogError, CatalogService
    from app.services.order_service import OrderConflict, OrderError, OrderService
    from app.services.tenant_settings_service import TenantSettingsService


def _run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


@pytest.fixture(scope="module")
def db():
    database = MySQLDatabase(DB_URL)
    database.bootstrap(default_tenant_key="default", default_tenant_name="Default", default_tenant_email="d@example.com")
    return database


def _tenant(db):
    key = f"orders-{uuid.uuid4().hex[:10]}"
    db.insert("INSERT INTO tenants (external_key, name, email, plan, status) VALUES (%s, %s, %s, 'starter', 'active')",
              (key, f"Tenant {key}", f"{key}@example.com"))
    return key


@pytest.fixture()
def services(db):
    catalog = CatalogService(db)
    return catalog, OrderService(db, catalog)


def _seed(catalog, tenant):
    category = _run(catalog.create_category(tenant, name="Pizzas"))
    pizza = _run(catalog.create_product(tenant, {
        "name": "Calabresa", "category_id": category["id"],
        "variants": [{"name": "Broto", "price_cents": 4290}, {"name": "Grande", "price_cents": 6290}]}))
    drink = _run(catalog.create_product(tenant, {"name": "Água", "price_cents": 400}))
    return pizza, drink


def test_orders_disabled_by_default(db):
    tenant = _tenant(db)
    assert _run(TenantSettingsService(db).get_or_create(tenant)).orders_enabled is False
    updated = _run(TenantSettingsService(db).update(tenant, orders_enabled=True))
    assert updated.orders_enabled is True


def test_create_is_idempotent_numbered_and_priced_from_catalog(db, services):
    catalog, orders = services
    tenant = _tenant(db)
    pizza, drink = _seed(catalog, tenant)
    items = [{"product_id": pizza["id"], "variant_name": "grande", "quantity": 2, "unit_price_cents": 1},
             {"product_id": drink["id"], "quantity": 1}]
    first = _run(orders.create(tenant, customer_phone="+55 34 99999-0000", fulfillment="retirada", items=items,
                               idempotency_key="draft:a", customer_name="Ana"))
    again = _run(orders.create(tenant, customer_phone="5534999990000", fulfillment="retirada", items=items,
                               idempotency_key="draft:a"))
    second = _run(orders.create(tenant, customer_phone="5534999990000", fulfillment="entrega", items=items[:1],
                                idempotency_key="draft:b", address="Rua A, 10, Centro"))
    assert first["created"] and not again["created"] and again["id"] == first["id"]
    assert first["total_cents"] == 2 * 6290 + 400 and first["order_number"] == 1 and second["order_number"] == 2
    detail = _run(orders.get(tenant, first["id"]))
    assert [i["unit_price_cents"] for i in detail["items"]] == [6290, 400]
    assert detail["history"][0]["to_status"] == "novo" and detail["customer_phone"] == "5534999990000"
    with pytest.raises(OrderError):
        _run(orders.create(tenant, customer_phone="5534999990000", fulfillment="entrega", items=items[:1],
                           idempotency_key="draft:c"))


def test_status_machine_history_and_tenant_isolation(db, services):
    catalog, orders = services
    tenant, other = _tenant(db), _tenant(db)
    pizza, _ = _seed(catalog, tenant)
    order = _run(orders.create(tenant, customer_phone="5534999990000", fulfillment="retirada",
                               items=[{"product_id": pizza["id"], "variant_name": "Broto", "quantity": 1}],
                               idempotency_key="draft:x"))
    with pytest.raises(OrderError):
        _run(orders.update_status(tenant, order["id"], "saiu_para_entrega"))
    for status in ("confirmado", "em_preparo", "pronto_para_retirada", "retirado"):
        updated, history_id, _ = _run(orders.update_status(tenant, order["id"], status, actor_name="Loja"))
        _run(orders.record_notification(history_id, "not_requested"))
    assert updated["status"] == "retirado" and updated["allowed_next"] == []
    history = _run(orders.get(tenant, order["id"]))["history"]
    assert [h["to_status"] for h in history] == ["novo", "confirmado", "em_preparo", "pronto_para_retirada", "retirado"]
    with pytest.raises(LookupError):
        _run(orders.get(other, order["id"]))
    with pytest.raises(LookupError):
        _run(orders.update_status(other, order["id"], "cancelado"))
    assert _run(orders.list(other)) == []
    assert _run(catalog.list_products(other)) == []


def test_unavailable_product_and_duplicate_names_are_rejected(db, services):
    catalog, orders = services
    tenant = _tenant(db)
    pizza, _ = _seed(catalog, tenant)
    with pytest.raises(CatalogError):
        _run(catalog.create_product(tenant, {"name": "Calabresa", "price_cents": 1}))
    _run(catalog.update_product(tenant, pizza["id"], {"available": False}))
    with pytest.raises(OrderError):
        _run(orders.create(tenant, customer_phone="5534999990000", fulfillment="retirada",
                           items=[{"product_id": pizza["id"], "variant_name": "Broto", "quantity": 1}],
                           idempotency_key="draft:y"))


def test_concurrent_status_change_conflicts(db, services):
    catalog, orders = services
    tenant = _tenant(db)
    _, drink = _seed(catalog, tenant)
    order = _run(orders.create(tenant, customer_phone="5534999990000", fulfillment="retirada",
                               items=[{"product_id": drink["id"], "quantity": 1}], idempotency_key="draft:z"))
    db.execute("UPDATE orders SET status = 'cancelado' WHERE id = %s", (order["id"],))
    original_get = orders._get

    async def stale_get(tenant_pk, order_id):
        row = await original_get(tenant_pk, order_id)
        return {**row, "status": "novo"}

    orders._get = stale_get
    with pytest.raises(OrderConflict):
        _run(orders.update_status(tenant, order["id"], "confirmado"))
