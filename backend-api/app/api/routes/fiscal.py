"""Fiscal document endpoints — stub when provider is not configured."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Request

from app.api.access import assert_capability, resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.services.dependencies import (
    authenticated_user_dependency,
    fiscal_provider_dependency,
)
from app.services.fiscal_provider import FiscalProvider

router = APIRouter(prefix="/api/v1/fiscal", tags=["Fiscal"])


@router.get("/documents")
async def list_fiscal_documents(
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    provider: FiscalProvider = Depends(fiscal_provider_dependency),
) -> dict[str, Any]:
    assert_capability(user, "canManageBilling")
    tenant_id = resolve_tenant_scope(user, request)
    documents = await provider.list_documents(tenant_id)
    if not provider.configured:
        return {
            "configured": False,
            "provider": provider.provider_name,
            "documents": [],
            "message": (
                "Provedor fiscal não configurado. "
                "Nenhuma nota fiscal será inventada até FISCAL_PROVIDER estar pronto."
            ),
        }
    return {
        "configured": True,
        "provider": provider.provider_name,
        "documents": documents,
    }
