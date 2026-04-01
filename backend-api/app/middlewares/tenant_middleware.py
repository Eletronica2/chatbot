"""Middleware that attaches tenant information to the request state"""
from __future__ import annotations

from typing import Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response


class TenantMiddleware(BaseHTTPMiddleware):
    """Extracts the tenant identifier from headers"""

    def __init__(self, app, header_name: str = "x-tenant-id", default_tenant: str = "default"):
        super().__init__(app)
        self.header_name = header_name.lower()
        self.default_tenant = default_tenant

    async def dispatch(self, request: Request, call_next: Callable[[Request], Response]) -> Response:
        tenant_id = request.headers.get(self.header_name, self.default_tenant)
        request.state.tenant_id = tenant_id
        return await call_next(request)

