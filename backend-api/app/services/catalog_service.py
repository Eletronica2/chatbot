"""Catalog Service – per-tenant categories and products (price, variants, availability)."""
from __future__ import annotations

import asyncio
import json
from datetime import datetime
from typing import Any, Dict, List, Optional

import pymysql

from app.db.mysql import MySQLDatabase

MAX_VARIANTS = 20


class CatalogError(ValueError):
    pass


class CatalogNotFound(LookupError):
    pass


def _iso(value: Any) -> str:
    return value.isoformat() if isinstance(value, datetime) else str(value or "")


def _clean_name(value: Any, field: str, limit: int) -> str:
    name = " ".join(str(value or "").split())
    if not name:
        raise CatalogError(f"{field} é obrigatório")
    if len(name) > limit:
        raise CatalogError(f"{field} aceita no máximo {limit} caracteres")
    return name


def _clean_price(value: Any, field: str = "price_cents") -> int:
    try:
        cents = int(value)
    except (TypeError, ValueError) as exc:
        raise CatalogError(f"{field} deve ser um inteiro em centavos") from exc
    if cents < 0 or cents > 10_000_000:
        raise CatalogError(f"{field} fora do intervalo permitido")
    return cents


def normalize_variants(raw: Any) -> List[Dict[str, Any]]:
    if not raw:
        return []
    if not isinstance(raw, list) or len(raw) > MAX_VARIANTS:
        raise CatalogError(f"variants deve ser uma lista com até {MAX_VARIANTS} opções")
    seen: set[str] = set()
    variants: List[Dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            raise CatalogError("cada variante precisa de name e price_cents")
        name = _clean_name(item.get("name"), "nome da variante", 80)
        if name.lower() in seen:
            raise CatalogError(f"variante repetida: {name}")
        seen.add(name.lower())
        variants.append({"name": name, "price_cents": _clean_price(item.get("price_cents"), "preço da variante")})
    return variants


def _product_row(row: Dict[str, Any]) -> Dict[str, Any]:
    raw_variants = row.get("variants")
    variants = json.loads(raw_variants) if isinstance(raw_variants, str) else (raw_variants or [])
    return {
        "id": int(row["id"]),
        "category_id": int(row["category_id"]) if row.get("category_id") is not None else None,
        "category_name": row.get("category_name"),
        "name": row["name"],
        "description": row.get("description") or "",
        "price_cents": int(row["price_cents"]) if row.get("price_cents") is not None else None,
        "variants": variants,
        "available": bool(row.get("available")),
        "sort_order": int(row.get("sort_order") or 0),
        "updated_at": _iso(row.get("updated_at")),
    }


def _category_row(row: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": int(row["id"]),
        "name": row["name"],
        "sort_order": int(row.get("sort_order") or 0),
        "active": bool(row.get("active")),
        "product_count": int(row.get("product_count") or 0),
    }


class CatalogService:
    def __init__(self, database: MySQLDatabase) -> None:
        self.db = database

    # ── categories ────────────────────────────────────────────────────────────

    def _list_categories(self, tenant_pk: int) -> List[Dict[str, Any]]:
        rows = self.db.fetch_all(
            "SELECT c.id, c.name, c.sort_order, c.active, COUNT(p.id) AS product_count "
            "FROM catalog_categories c LEFT JOIN catalog_products p ON p.category_id = c.id "
            "WHERE c.tenant_id = %s GROUP BY c.id, c.name, c.sort_order, c.active "
            "ORDER BY c.sort_order, c.name",
            (tenant_pk,),
        )
        return [_category_row(row) for row in rows]

    async def list_categories(self, tenant_key: str) -> List[Dict[str, Any]]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        return await asyncio.to_thread(self._list_categories, tenant_pk)

    async def create_category(self, tenant_key: str, *, name: str, sort_order: int = 0) -> Dict[str, Any]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        clean = _clean_name(name, "nome da categoria", 120)
        try:
            category_id = await self.db.insert_async(
                "INSERT INTO catalog_categories (tenant_id, name, sort_order) VALUES (%s, %s, %s)",
                (tenant_pk, clean, int(sort_order)),
            )
        except pymysql.err.IntegrityError as exc:
            raise CatalogError("já existe uma categoria com esse nome") from exc
        return await self._get_category(tenant_pk, category_id)

    async def update_category(
        self, tenant_key: str, category_id: int, *, name: Optional[str] = None,
        sort_order: Optional[int] = None, active: Optional[bool] = None,
    ) -> Dict[str, Any]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        current = await self._get_category(tenant_pk, category_id)
        try:
            await self.db.execute_async(
                "UPDATE catalog_categories SET name = %s, sort_order = %s, active = %s WHERE id = %s AND tenant_id = %s",
                (
                    _clean_name(name, "nome da categoria", 120) if name is not None else current["name"],
                    int(sort_order) if sort_order is not None else current["sort_order"],
                    1 if (current["active"] if active is None else active) else 0,
                    category_id, tenant_pk,
                ),
            )
        except pymysql.err.IntegrityError as exc:
            raise CatalogError("já existe uma categoria com esse nome") from exc
        return await self._get_category(tenant_pk, category_id)

    async def delete_category(self, tenant_key: str, category_id: int) -> Dict[str, Any]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        current = await self._get_category(tenant_pk, category_id)
        await self.db.execute_async(
            "DELETE FROM catalog_categories WHERE id = %s AND tenant_id = %s", (category_id, tenant_pk)
        )
        return current

    async def _get_category(self, tenant_pk: int, category_id: int) -> Dict[str, Any]:
        row = await self.db.fetch_one_async(
            "SELECT c.id, c.name, c.sort_order, c.active, "
            "(SELECT COUNT(*) FROM catalog_products p WHERE p.category_id = c.id) AS product_count "
            "FROM catalog_categories c WHERE c.id = %s AND c.tenant_id = %s",
            (category_id, tenant_pk),
        )
        if not row:
            raise CatalogNotFound("categoria não encontrada")
        return _category_row(row)

    # ── products ──────────────────────────────────────────────────────────────

    _PRODUCT_SELECT = (
        "SELECT p.id, p.category_id, c.name AS category_name, p.name, p.description, p.price_cents, "
        "p.variants, p.available, p.sort_order, p.updated_at "
        "FROM catalog_products p LEFT JOIN catalog_categories c ON c.id = p.category_id "
    )

    def _list_products(self, tenant_pk: int, only_available: bool) -> List[Dict[str, Any]]:
        where = "WHERE p.tenant_id = %s" + (" AND p.available = 1 AND (c.id IS NULL OR c.active = 1)"
                                            if only_available else "")
        rows = self.db.fetch_all(
            self._PRODUCT_SELECT + where + " ORDER BY COALESCE(c.sort_order, 999999), c.name, p.sort_order, p.name",
            (tenant_pk,),
        )
        return [_product_row(row) for row in rows]

    async def list_products(self, tenant_key: str, *, only_available: bool = False) -> List[Dict[str, Any]]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        return await asyncio.to_thread(self._list_products, tenant_pk, only_available)

    async def _get_product(self, tenant_pk: int, product_id: int) -> Dict[str, Any]:
        row = await self.db.fetch_one_async(
            self._PRODUCT_SELECT + "WHERE p.id = %s AND p.tenant_id = %s", (product_id, tenant_pk)
        )
        if not row:
            raise CatalogNotFound("produto não encontrado")
        return _product_row(row)

    async def _check_category(self, tenant_pk: int, category_id: Optional[int]) -> None:
        if category_id is not None:
            await self._get_category(tenant_pk, int(category_id))

    @staticmethod
    def _validate_pricing(price_cents: Optional[int], variants: List[Dict[str, Any]]) -> None:
        if price_cents is None and not variants:
            raise CatalogError("informe o preço ou ao menos uma variante com preço")

    async def create_product(self, tenant_key: str, data: Dict[str, Any]) -> Dict[str, Any]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        name = _clean_name(data.get("name"), "nome do produto", 160)
        price = _clean_price(data["price_cents"]) if data.get("price_cents") is not None else None
        variants = normalize_variants(data.get("variants"))
        self._validate_pricing(price, variants)
        category_id = data.get("category_id")
        await self._check_category(tenant_pk, category_id)
        try:
            product_id = await self.db.insert_async(
                "INSERT INTO catalog_products (tenant_id, category_id, name, description, price_cents, variants, "
                "available, sort_order) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
                (
                    tenant_pk, category_id, name, (data.get("description") or "").strip()[:500] or None, price,
                    json.dumps(variants, ensure_ascii=False) if variants else None,
                    1 if data.get("available", True) else 0, int(data.get("sort_order") or 0),
                ),
            )
        except pymysql.err.IntegrityError as exc:
            raise CatalogError("já existe um produto com esse nome") from exc
        return await self._get_product(tenant_pk, product_id)

    async def update_product(self, tenant_key: str, product_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
        """Partial update: only keys present in ``data`` change."""
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        current = await self._get_product(tenant_pk, product_id)
        name = _clean_name(data["name"], "nome do produto", 160) if "name" in data else current["name"]
        if "price_cents" in data:
            price = _clean_price(data["price_cents"]) if data["price_cents"] is not None else None
        else:
            price = current["price_cents"]
        variants = normalize_variants(data["variants"]) if "variants" in data else current["variants"]
        self._validate_pricing(price, variants)
        category_id = data["category_id"] if "category_id" in data else current["category_id"]
        await self._check_category(tenant_pk, category_id)
        description = (data.get("description") or "").strip()[:500] if "description" in data else current["description"]
        available = bool(data["available"]) if "available" in data else current["available"]
        sort_order = int(data.get("sort_order") or 0) if "sort_order" in data else current["sort_order"]
        try:
            await self.db.execute_async(
                "UPDATE catalog_products SET category_id = %s, name = %s, description = %s, price_cents = %s, "
                "variants = %s, available = %s, sort_order = %s WHERE id = %s AND tenant_id = %s",
                (
                    category_id, name, description or None, price,
                    json.dumps(variants, ensure_ascii=False) if variants else None,
                    1 if available else 0, sort_order, product_id, tenant_pk,
                ),
            )
        except pymysql.err.IntegrityError as exc:
            raise CatalogError("já existe um produto com esse nome") from exc
        return await self._get_product(tenant_pk, product_id)

    async def delete_product(self, tenant_key: str, product_id: int) -> Dict[str, Any]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        current = await self._get_product(tenant_pk, product_id)
        await self.db.execute_async(
            "DELETE FROM catalog_products WHERE id = %s AND tenant_id = %s", (product_id, tenant_pk)
        )
        return current
