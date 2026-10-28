"""Order Service – structured order creation (prices from the catalog), status machine and history."""
from __future__ import annotations

import asyncio
from datetime import datetime
from typing import Any, Dict, List, Optional

import pymysql

from app.db.mysql import MySQLDatabase
from app.domain import orders as order_domain

MAX_ITEMS = 30
MAX_QUANTITY = 50


class OrderError(ValueError):
    pass


class OrderNotFound(LookupError):
    pass


class OrderConflict(RuntimeError):
    pass


def _iso(value: Any) -> str:
    return value.isoformat() if isinstance(value, datetime) else str(value or "")


def _order_row(row: Dict[str, Any]) -> Dict[str, Any]:
    status = str(row["status"])
    fulfillment = str(row["fulfillment"])
    return {
        "id": int(row["id"]),
        "order_number": int(row["order_number"]),
        "status": status,
        "status_label": order_domain.STATUS_LABELS.get(status, status),
        "allowed_next": order_domain.allowed_next(status, fulfillment),
        "customer_name": row.get("customer_name") or "",
        "customer_phone": row["customer_phone"],
        "phone_number_id": row.get("phone_number_id") or "",
        "fulfillment": fulfillment,
        "address": row.get("address") or "",
        "notes": row.get("notes") or "",
        "subtotal_cents": int(row.get("subtotal_cents") or 0),
        "total_cents": int(row.get("total_cents") or 0),
        "source": row.get("source") or "whatsapp",
        "session_id": row.get("session_id") or "",
        "item_count": int(row.get("item_count") or 0),
        "created_at": _iso(row.get("created_at")),
        "updated_at": _iso(row.get("updated_at")),
    }


def price_items(products: List[Dict[str, Any]], items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Resolve requested items against the tenant catalog; the price always comes from the catalog."""
    if not items:
        raise OrderError("o pedido precisa de ao menos um item")
    if len(items) > MAX_ITEMS:
        raise OrderError(f"o pedido aceita no máximo {MAX_ITEMS} itens")
    by_id = {int(p["id"]): p for p in products}
    priced: List[Dict[str, Any]] = []
    for item in items:
        product = by_id.get(int(item.get("product_id") or 0))
        if not product or not product.get("available"):
            raise OrderError("produto indisponível ou inexistente no catálogo")
        try:
            quantity = int(item["quantity"] if item.get("quantity") is not None else 1)
        except (TypeError, ValueError) as exc:
            raise OrderError("quantidade inválida") from exc
        if not 1 <= quantity <= MAX_QUANTITY:
            raise OrderError(f"quantidade deve ficar entre 1 e {MAX_QUANTITY}")
        variant_name = (item.get("variant_name") or "").strip() or None
        variants = product.get("variants") or []
        if variants:
            match = next((v for v in variants if variant_name and v["name"].lower() == variant_name.lower()), None)
            if not match:
                raise OrderError(f"escolha uma opção válida para {product['name']}")
            variant_name, unit = match["name"], int(match["price_cents"])
        else:
            if product.get("price_cents") is None:
                raise OrderError(f"{product['name']} está sem preço no catálogo")
            variant_name, unit = None, int(product["price_cents"])
        priced.append({
            "product_id": int(product["id"]),
            "product_name": product["name"],
            "variant_name": variant_name,
            "unit_price_cents": unit,
            "quantity": quantity,
            "line_total_cents": unit * quantity,
        })
    return priced


class OrderService:
    def __init__(self, database: MySQLDatabase, catalog_service: Any) -> None:
        self.db = database
        self.catalog = catalog_service

    _ORDER_SELECT = (
        "SELECT o.id, o.order_number, o.status, o.customer_name, o.customer_phone, o.phone_number_id, "
        "o.fulfillment, o.address, o.notes, o.subtotal_cents, o.total_cents, o.source, o.session_id, "
        "o.created_at, o.updated_at, "
        "(SELECT COALESCE(SUM(i.quantity), 0) FROM order_items i WHERE i.order_id = o.id) AS item_count "
        "FROM orders o "
    )

    # ── creation ──────────────────────────────────────────────────────────────

    async def create(
        self,
        tenant_key: str,
        *,
        customer_phone: str,
        fulfillment: str,
        items: List[Dict[str, Any]],
        idempotency_key: str,
        customer_name: str = "",
        address: str = "",
        notes: str = "",
        phone_number_id: str = "",
        session_id: Optional[str] = None,
        source: str = "whatsapp",
        actor_type: str = "assistant",
        actor_user_id: Optional[str] = None,
        actor_name: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Create an order once per ``idempotency_key``; returns the existing order on replays."""
        if fulfillment not in order_domain.FULFILLMENTS:
            raise OrderError("forma de atendimento deve ser entrega ou retirada")
        phone = "".join(ch for ch in str(customer_phone or "") if ch.isdigit())
        if not 8 <= len(phone) <= 15:
            raise OrderError("telefone do cliente inválido")
        address = " ".join(str(address or "").split())[:500]
        if fulfillment == "entrega" and len(address) < 5:
            raise OrderError("endereço de entrega é obrigatório")
        key = str(idempotency_key or "").strip()[:120]
        if not key:
            raise OrderError("idempotency_key é obrigatório")
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        enabled = await self.db.fetch_one_async(
            "SELECT orders_enabled FROM tenant_settings WHERE tenant_id = %s", (tenant_pk,)
        )
        if not enabled or not enabled.get("orders_enabled"):
            raise OrderError("o módulo Pedidos está desativado para esta empresa")
        existing = await self._find_by_key(tenant_pk, key)
        if existing:
            return {**existing, "created": False}

        products = await self.catalog.list_products(tenant_key)
        priced = price_items(products, items)
        subtotal = sum(i["line_total_cents"] for i in priced)

        def _insert() -> int:
            for _ in range(3):
                try:
                    with self.db.transaction() as conn:
                        with conn.cursor() as cursor:
                            cursor.execute(
                                "SELECT COALESCE(MAX(order_number), 0) + 1 AS next_number FROM orders "
                                "WHERE tenant_id = %s FOR UPDATE",
                                (tenant_pk,),
                            )
                            number = int((cursor.fetchone() or {}).get("next_number") or 1)
                            cursor.execute(
                                "INSERT INTO orders (tenant_id, order_number, status, customer_name, customer_phone, "
                                "phone_number_id, fulfillment, address, notes, subtotal_cents, total_cents, source, "
                                "session_id, idempotency_key) "
                                "VALUES (%s, %s, 'novo', %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                                (
                                    tenant_pk, number, (customer_name or "").strip()[:160] or None, phone,
                                    (phone_number_id or "")[:64] or None, fulfillment,
                                    address if fulfillment == "entrega" else None,
                                    (notes or "").strip()[:500] or None, subtotal, subtotal, source[:32],
                                    session_id, key,
                                ),
                            )
                            order_id = int(cursor.lastrowid)
                            cursor.executemany(
                                "INSERT INTO order_items (order_id, product_id, product_name, variant_name, "
                                "unit_price_cents, quantity, line_total_cents) VALUES (%s, %s, %s, %s, %s, %s, %s)",
                                [
                                    (order_id, i["product_id"], i["product_name"], i["variant_name"],
                                     i["unit_price_cents"], i["quantity"], i["line_total_cents"])
                                    for i in priced
                                ],
                            )
                            cursor.execute(
                                "INSERT INTO order_status_history (order_id, from_status, to_status, actor_type, "
                                "actor_user_id, actor_name, note) VALUES (%s, NULL, 'novo', %s, %s, %s, %s)",
                                (order_id, actor_type, actor_user_id, actor_name, "Pedido criado"),
                            )
                    return order_id
                except pymysql.err.IntegrityError as exc:
                    if "uq_orders_idempotency" in str(exc):
                        return 0
                    if "uq_orders_number" not in str(exc):
                        raise
            raise OrderConflict("não foi possível numerar o pedido, tente novamente")

        order_id = await asyncio.to_thread(_insert)
        if not order_id:
            existing = await self._find_by_key(tenant_pk, key)
            return {**(existing or {}), "created": False}
        order = await self._get(tenant_pk, order_id)
        return {**order, "created": True}

    async def _find_by_key(self, tenant_pk: int, key: str) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one_async(
            self._ORDER_SELECT + "WHERE o.tenant_id = %s AND o.idempotency_key = %s", (tenant_pk, key)
        )
        return _order_row(row) if row else None

    # ── reads ─────────────────────────────────────────────────────────────────

    async def list(
        self, tenant_key: str, *, status: Optional[str] = None, active_only: bool = False, limit: int = 100,
    ) -> List[Dict[str, Any]]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        where, params = ["o.tenant_id = %s"], [tenant_pk]
        if status:
            if status not in order_domain.STATUS_LABELS:
                raise OrderError("status inválido")
            where.append("o.status = %s")
            params.append(status)
        elif active_only:
            where.append("o.status NOT IN ('entregue', 'retirado', 'cancelado')")
        rows = await self.db.fetch_all_async(
            self._ORDER_SELECT + "WHERE " + " AND ".join(where) + " ORDER BY o.created_at DESC, o.id DESC LIMIT %s",
            (*params, max(1, min(int(limit), 300))),
        )
        return [_order_row(row) for row in rows]

    async def _get(self, tenant_pk: int, order_id: int) -> Dict[str, Any]:
        row = await self.db.fetch_one_async(
            self._ORDER_SELECT + "WHERE o.id = %s AND o.tenant_id = %s", (order_id, tenant_pk)
        )
        if not row:
            raise OrderNotFound("pedido não encontrado")
        return _order_row(row)

    async def get(self, tenant_key: str, order_id: int) -> Dict[str, Any]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        order = await self._get(tenant_pk, order_id)
        items = await self.db.fetch_all_async(
            "SELECT product_id, product_name, variant_name, unit_price_cents, quantity, line_total_cents "
            "FROM order_items WHERE order_id = %s ORDER BY id",
            (order_id,),
        )
        history = await self.db.fetch_all_async(
            "SELECT id, from_status, to_status, actor_type, actor_name, note, notification_status, created_at "
            "FROM order_status_history WHERE order_id = %s ORDER BY created_at, id",
            (order_id,),
        )
        order["items"] = [
            {**item, "product_id": item.get("product_id"), "variant_name": item.get("variant_name") or ""}
            for item in items
        ]
        order["history"] = [
            {
                "id": int(h["id"]),
                "from_status": h.get("from_status"),
                "to_status": h["to_status"],
                "to_label": order_domain.STATUS_LABELS.get(h["to_status"], h["to_status"]),
                "actor_type": h["actor_type"],
                "actor_name": h.get("actor_name") or "",
                "note": h.get("note") or "",
                "notification_status": h.get("notification_status") or "",
                "created_at": _iso(h.get("created_at")),
            }
            for h in history
        ]
        return order

    # ── status ────────────────────────────────────────────────────────────────

    async def update_status(
        self,
        tenant_key: str,
        order_id: int,
        target: str,
        *,
        actor_type: str = "user",
        actor_user_id: Optional[str] = None,
        actor_name: Optional[str] = None,
        note: str = "",
    ) -> tuple[Dict[str, Any], int, str]:
        """Apply one allowed transition. Returns (order, history_id, previous_status)."""
        if target not in order_domain.STATUS_LABELS:
            raise OrderError("status inválido")
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        current = await self._get(tenant_pk, order_id)
        previous = current["status"]
        if not order_domain.can_transition(previous, target, current["fulfillment"]):
            raise OrderError(
                f"não é possível ir de {order_domain.STATUS_LABELS.get(previous, previous)} para "
                f"{order_domain.STATUS_LABELS[target]}"
            )

        def _apply() -> int:
            with self.db.transaction() as conn:
                with conn.cursor() as cursor:
                    changed = cursor.execute(
                        "UPDATE orders SET status = %s WHERE id = %s AND tenant_id = %s AND status = %s",
                        (target, order_id, tenant_pk, previous),
                    )
                    if not changed:
                        return 0
                    cursor.execute(
                        "INSERT INTO order_status_history (order_id, from_status, to_status, actor_type, "
                        "actor_user_id, actor_name, note) VALUES (%s, %s, %s, %s, %s, %s, %s)",
                        (order_id, previous, target, actor_type, actor_user_id, (actor_name or "")[:160] or None,
                         (note or "").strip()[:300] or None),
                    )
                    return int(cursor.lastrowid)

        history_id = await asyncio.to_thread(_apply)
        if not history_id:
            raise OrderConflict("o pedido foi alterado por outra pessoa; atualize e tente novamente")
        return await self._get(tenant_pk, order_id), history_id, previous

    async def record_notification(self, history_id: int, status: str, message_id: Optional[str] = None) -> None:
        await self.db.execute_async(
            "UPDATE order_status_history SET notification_status = %s, notification_message_id = %s WHERE id = %s",
            (status[:32], (message_id or "")[:120] or None, history_id),
        )

    async def latest_for_customer(self, tenant_key: str, customer_phone: str) -> Optional[Dict[str, Any]]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        phone = "".join(ch for ch in str(customer_phone or "") if ch.isdigit())
        row = await self.db.fetch_one_async(
            self._ORDER_SELECT + "WHERE o.tenant_id = %s AND o.customer_phone = %s ORDER BY o.id DESC LIMIT 1",
            (tenant_pk, phone),
        )
        return _order_row(row) if row else None
