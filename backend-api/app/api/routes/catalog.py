"""Catalog API: categories and products (price, variants, availability) for the Orders module."""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.access import assert_capability, resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.services.admin_audit_service import AdminAuditService
from app.services.catalog_service import CatalogError, CatalogNotFound, CatalogService
from app.services.dependencies import (
    admin_audit_service_dependency,
    authenticated_user_dependency,
    catalog_service_dependency,
    knowledge_sync_service_dependency,
    tenant_settings_service_dependency,
)
from app.services.knowledge_sync_service import KnowledgeSyncService
from app.services.tenant_settings_service import TenantSettingsService

router = APIRouter(prefix="/api/v1/catalog", tags=["Catalog"])


class CategoryPayload(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=120)
    sort_order: Optional[int] = Field(None, ge=0, le=100000)
    active: Optional[bool] = None


class VariantPayload(BaseModel):
    name: str = Field(..., min_length=1, max_length=80)
    price_cents: int = Field(..., ge=0, le=10_000_000)


class ProductPayload(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=160)
    description: Optional[str] = Field(None, max_length=500)
    category_id: Optional[int] = None
    price_cents: Optional[int] = Field(None, ge=0, le=10_000_000)
    variants: Optional[List[VariantPayload]] = Field(None, max_length=20)
    available: Optional[bool] = None
    sort_order: Optional[int] = Field(None, ge=0, le=100000)


def _http(exc: Exception) -> HTTPException:
    if isinstance(exc, CatalogNotFound):
        return HTTPException(status_code=404, detail=str(exc))
    return HTTPException(status_code=422, detail=str(exc))


async def resync_catalog_knowledge(
    tenant_id: str, catalog: CatalogService, settings_service: TenantSettingsService, knowledge: KnowledgeSyncService,
    audit: AdminAuditService,
) -> None:
    settings = await settings_service.get_or_create(tenant_id)
    if not settings.local_ai_enabled:
        return
    products = await catalog.list_products(tenant_id)

    async def _record(result: Dict[str, Any]) -> None:
        await audit.append(tenant_id=tenant_id, action="knowledge.sync", entity_type="knowledge",
                           entity_key="catalogo-pedidos", summary="Catálogo sincronizado com a IA local",
                           metadata={k: result.get(k) for k in ("status", "reason", "unchanged", "results", "error")})

    knowledge.schedule(
        knowledge.sync_catalog(tenant_id, tenant_name=settings.tenant_name, products=products,
                               orders_enabled=settings.orders_enabled),
        label=f"catalog:{tenant_id}", on_done=_record,
    )


class _Deps:
    def __init__(self, user: AuthenticatedUser, tenant_id: str, catalog: CatalogService,
                 settings_service: TenantSettingsService, knowledge: KnowledgeSyncService,
                 audit: AdminAuditService) -> None:
        self.user = user
        self.tenant_id = tenant_id
        self.catalog = catalog
        self.settings_service = settings_service
        self.knowledge = knowledge
        self.audit = audit

    def require_manage(self) -> None:
        assert_capability(self.user, "canManageCatalog")

    async def changed(self, action: str, entity_type: str, entity: Dict[str, Any], summary: str) -> None:
        await self.audit.append(tenant_id=self.tenant_id, action=action, entity_type=entity_type,
                                entity_key=str(entity.get("id")), summary=summary, actor=self.user,
                                metadata={"name": entity.get("name")})
        await resync_catalog_knowledge(self.tenant_id, self.catalog, self.settings_service, self.knowledge, self.audit)


def catalog_deps(
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    catalog: CatalogService = Depends(catalog_service_dependency),
    settings_service: TenantSettingsService = Depends(tenant_settings_service_dependency),
    knowledge: KnowledgeSyncService = Depends(knowledge_sync_service_dependency),
    audit: AdminAuditService = Depends(admin_audit_service_dependency),
) -> _Deps:
    return _Deps(user, resolve_tenant_scope(user, request), catalog, settings_service, knowledge, audit)


# ── categories ────────────────────────────────────────────────────────────────

@router.get("/categories")
async def list_categories(deps: _Deps = Depends(catalog_deps)) -> List[Dict[str, Any]]:
    return await deps.catalog.list_categories(deps.tenant_id)


@router.post("/categories", status_code=201)
async def create_category(payload: CategoryPayload, deps: _Deps = Depends(catalog_deps)) -> Dict[str, Any]:
    deps.require_manage()
    try:
        category = await deps.catalog.create_category(deps.tenant_id, name=payload.name or "",
                                                      sort_order=payload.sort_order or 0)
    except (CatalogError, CatalogNotFound) as exc:
        raise _http(exc) from exc
    await deps.changed("catalog.category.create", "catalog_category", category, f"Categoria {category['name']} criada")
    return category


@router.patch("/categories/{category_id}")
async def update_category(category_id: int, payload: CategoryPayload, deps: _Deps = Depends(catalog_deps)) -> Dict[str, Any]:
    deps.require_manage()
    try:
        category = await deps.catalog.update_category(deps.tenant_id, category_id, name=payload.name,
                                                      sort_order=payload.sort_order, active=payload.active)
    except (CatalogError, CatalogNotFound) as exc:
        raise _http(exc) from exc
    await deps.changed("catalog.category.update", "catalog_category", category,
                       f"Categoria {category['name']} atualizada")
    return category


@router.delete("/categories/{category_id}")
async def delete_category(category_id: int, deps: _Deps = Depends(catalog_deps)) -> Dict[str, Any]:
    deps.require_manage()
    try:
        category = await deps.catalog.delete_category(deps.tenant_id, category_id)
    except (CatalogError, CatalogNotFound) as exc:
        raise _http(exc) from exc
    await deps.changed("catalog.category.delete", "catalog_category", category, f"Categoria {category['name']} removida")
    return {"ok": True}


# ── products ──────────────────────────────────────────────────────────────────

@router.get("/products")
async def list_products(deps: _Deps = Depends(catalog_deps)) -> List[Dict[str, Any]]:
    return await deps.catalog.list_products(deps.tenant_id)


@router.post("/products", status_code=201)
async def create_product(payload: ProductPayload, deps: _Deps = Depends(catalog_deps)) -> Dict[str, Any]:
    deps.require_manage()
    data = payload.model_dump(exclude_none=True)
    try:
        product = await deps.catalog.create_product(deps.tenant_id, data)
    except (CatalogError, CatalogNotFound) as exc:
        raise _http(exc) from exc
    await deps.changed("catalog.product.create", "catalog_product", product, f"Produto {product['name']} criado")
    return product


@router.patch("/products/{product_id}")
async def update_product(product_id: int, payload: ProductPayload, deps: _Deps = Depends(catalog_deps)) -> Dict[str, Any]:
    deps.require_manage()
    data = payload.model_dump(exclude_unset=True)
    try:
        product = await deps.catalog.update_product(deps.tenant_id, product_id, data)
    except (CatalogError, CatalogNotFound) as exc:
        raise _http(exc) from exc
    await deps.changed("catalog.product.update", "catalog_product", product, f"Produto {product['name']} atualizado")
    return product


@router.delete("/products/{product_id}")
async def delete_product(product_id: int, deps: _Deps = Depends(catalog_deps)) -> Dict[str, Any]:
    deps.require_manage()
    try:
        product = await deps.catalog.delete_product(deps.tenant_id, product_id)
    except (CatalogError, CatalogNotFound) as exc:
        raise _http(exc) from exc
    await deps.changed("catalog.product.delete", "catalog_product", product, f"Produto {product['name']} removido")
    return {"ok": True}
