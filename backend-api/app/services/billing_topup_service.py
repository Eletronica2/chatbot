"""Top-up purchases (operational packs and campaign credits). Granted exactly once."""
from __future__ import annotations

import uuid
from datetime import datetime
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

from app.db.mysql import MySQLDatabase
from app.domain.billing_v2 import BillingMode, UnitType
from app.services.billing_catalog_service import BillingCatalogService
from app.services.billing_gate import BillingGate


class BillingTopupService:
    def __init__(self, database: MySQLDatabase, catalog: BillingCatalogService, gate: BillingGate):
        self.database = database
        self.catalog = catalog
        self.gate = gate

    def create_purchase(self, tenant_pk: int, *, item_code: str, units: int | None, actor_id: str | None) -> dict[str, Any]:
        item = self.catalog.get_item(item_code)
        if not item or item["status"] != "active":
            raise ValueError("Item de catálogo indisponível")
        config = self.gate.get_config(tenant_pk)
        if item["kind"] == "topup_operational":
            if not config["is_v2_plan"]:
                raise ValueError("Pacotes operacionais exigem plano do catálogo V2")
            unit_type = UnitType.OPERATIONAL.value
            qty = int(item["operational_units"] or 0)
            unit_price = (Decimal(item["price"]) / Decimal(qty)).quantize(Decimal("0.000001"))
            total = Decimal(item["price"])
        elif item["kind"] == "marketing_unit":
            if config["effective_mode"] != BillingMode.SOLUTION_PARTNER.value:
                raise ValueError("No modo cliente direto as tarifas Meta são cobradas pela Meta; créditos não se aplicam")
            sizes = (item.get("metadata") or {}).get("pack_sizes") or [100, 500, 1000, 5000]
            qty = int(units or 0)
            if qty not in sizes:
                raise ValueError(f"Pacote de créditos inválido; opções: {sizes}")
            unit_type = UnitType.MARKETING.value
            unit_price = Decimal(item["price"])
            total = (unit_price * qty).quantize(Decimal("0.01"), ROUND_HALF_UP)
        else:
            raise ValueError("Item não é um pacote adicional")
        if qty <= 0:
            raise ValueError("Quantidade inválida")
        purchase_id = str(uuid.uuid4())
        self.database.execute(
            """
            INSERT INTO billing_topup_purchases
                (id, tenant_id, catalog_item_code, unit_type, units, unit_price, total_amount, currency,
                 catalog_version, status, provider, created_by_user_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'BRL', %s, 'pending', 'stripe_test', %s)
            """,
            (purchase_id, tenant_pk, item["code"], unit_type, qty, unit_price, total, item["catalog_version"], actor_id),
        )
        return self.get_purchase(purchase_id)

    def attach_session(self, purchase_id: str, session_id: str) -> None:
        self.database.execute(
            "UPDATE billing_topup_purchases SET provider_session_id=%s WHERE id=%s AND provider_session_id IS NULL",
            (session_id, purchase_id),
        )

    def get_purchase(self, purchase_id: str) -> dict[str, Any] | None:
        row = self.database.fetch_one("SELECT * FROM billing_topup_purchases WHERE id=%s", (purchase_id,))
        return self._serialize(row) if row else None

    def list_purchases(self, tenant_pk: int, limit: int = 50) -> list[dict[str, Any]]:
        rows = self.database.fetch_all(
            "SELECT * FROM billing_topup_purchases WHERE tenant_id=%s ORDER BY created_at DESC LIMIT %s",
            (tenant_pk, int(limit)),
        )
        return [self._serialize(r) for r in rows]

    def mark_paid_and_grant(
        self,
        purchase_id: str,
        *,
        provider_payment_id: str | None,
        actor_id: str | None,
        reason: str,
        expected_tenant_pk: int | None = None,
        expected_total: Decimal | None = None,
    ) -> dict[str, Any]:
        """Idempotent: a second webhook/admin call returns created=False and grants nothing."""
        with self.database.transaction() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM billing_topup_purchases WHERE id=%s FOR UPDATE", (purchase_id,))
                purchase = cur.fetchone()
                if not purchase:
                    raise LookupError("Compra não encontrada")
                if expected_tenant_pk is not None and int(purchase["tenant_id"]) != int(expected_tenant_pk):
                    raise ValueError("Compra não pertence a este tenant")
                if expected_total is not None and Decimal(str(purchase["total_amount"])) != expected_total:
                    raise ValueError("Valor pago diverge do valor da compra")
                if purchase["status"] == "granted":
                    return {"created": False, "purchase_id": purchase_id, "status": "granted"}
                now = datetime.utcnow()
                grant = self.gate.grant(
                    int(purchase["tenant_id"]),
                    unit_type=purchase["unit_type"],
                    units=int(purchase["units"]),
                    source="topup",
                    grant_key=f"purchase:{purchase_id}",
                    expires_at=None,
                    catalog_item_code=purchase["catalog_item_code"],
                    purchase_id=purchase_id,
                    actor_id=actor_id,
                    reason=reason,
                    amount=Decimal(str(purchase["total_amount"])),
                    cursor=cur,
                )
                cur.execute(
                    """
                    UPDATE billing_topup_purchases
                    SET status='granted', paid_at=COALESCE(paid_at, %s), granted_at=%s,
                        provider_payment_id=COALESCE(%s, provider_payment_id)
                    WHERE id=%s
                    """,
                    (now, now, provider_payment_id, purchase_id),
                )
                return {"created": bool(grant.get("created")), "purchase_id": purchase_id, "status": "granted", "bucket_id": grant.get("bucket_id")}

    @staticmethod
    def _serialize(row: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": row["id"],
            "catalog_item_code": row["catalog_item_code"],
            "unit_type": row["unit_type"],
            "units": int(row["units"]),
            "unit_price": str(row["unit_price"]),
            "total_amount": str(Decimal(str(row["total_amount"])).quantize(Decimal("0.01"))),
            "currency": row["currency"],
            "catalog_version": row["catalog_version"],
            "status": row["status"],
            "provider": row["provider"],
            "created_at": row.get("created_at"),
            "paid_at": row.get("paid_at"),
            "granted_at": row.get("granted_at"),
        }
