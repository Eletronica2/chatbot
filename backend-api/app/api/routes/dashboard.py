"""Role-aware dashboard overview endpoint."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Request

from app.api.access import resolve_tenant_scope
from app.domain.auth import AuthenticatedUser
from app.domain.dashboard_metrics import DashboardOverview
from app.services.dashboard_service import DashboardService
from app.services.dependencies import (
    authenticated_user_dependency,
    dashboard_service_dependency,
)

router = APIRouter(prefix="/api/v1/dashboard", tags=["Dashboard"])


@router.get("/overview", response_model=DashboardOverview)
async def get_dashboard_overview(
    request: Request,
    user: AuthenticatedUser = Depends(authenticated_user_dependency),
    dashboard_service: DashboardService = Depends(dashboard_service_dependency),
) -> DashboardOverview:
    target_tenant_id = resolve_tenant_scope(user, request)
    return await dashboard_service.build_overview(
        user=user,
        requested_tenant_id=target_tenant_id,
    )

