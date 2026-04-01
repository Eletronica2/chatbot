"""Authentication endpoints for the admin panel."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.domain.auth import AuthTokenResponse, AuthenticatedUser
from app.services.auth_service import AuthService
from app.services.dependencies import (
    auth_service_dependency,
    authenticated_user_dependency,
    tenant_user_service_dependency,
)
from app.services.tenant_user_service import TenantUserService

router = APIRouter(prefix="/api/v1/auth", tags=["Auth"])


class LoginPayload(BaseModel):
    email: str = Field(..., min_length=3)
    password: str = Field(..., min_length=3)


class TokenPasswordPayload(BaseModel):
    token: str = Field(..., min_length=12)
    new_password: str = Field(..., min_length=6)


@router.post("/login", response_model=AuthTokenResponse)
async def login(
    payload: LoginPayload,
    auth_service: AuthService = Depends(auth_service_dependency),
) -> AuthTokenResponse:
    result = await auth_service.login(
        email=payload.email.strip().lower(),
        password=payload.password,
    )
    if result is None:
        raise HTTPException(status_code=401, detail="Email ou senha invalidos")
    return result


@router.get("/me", response_model=AuthenticatedUser)
async def me(user: AuthenticatedUser = Depends(authenticated_user_dependency)) -> AuthenticatedUser:
    return user


@router.post("/complete-invite", response_model=AuthenticatedUser)
async def complete_invite(
    payload: TokenPasswordPayload,
    service: TenantUserService = Depends(tenant_user_service_dependency),
) -> AuthenticatedUser:
    try:
        user = await service.complete_invite(
            token=payload.token,
            new_password=payload.new_password,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return AuthenticatedUser(
        user_id=user.user_id,
        tenant_id=user.tenant_id,
        email=user.email,
        display_name=user.display_name,
        role=user.role,
        status=user.status,
        created_at=user.created_at,
        last_login_at=user.last_login_at,
    )


@router.post("/reset-password/confirm", response_model=AuthenticatedUser)
async def confirm_reset_password(
    payload: TokenPasswordPayload,
    service: TenantUserService = Depends(tenant_user_service_dependency),
) -> AuthenticatedUser:
    try:
        user = await service.complete_password_reset(
            token=payload.token,
            new_password=payload.new_password,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return AuthenticatedUser(
        user_id=user.user_id,
        tenant_id=user.tenant_id,
        email=user.email,
        display_name=user.display_name,
        role=user.role,
        status=user.status,
        created_at=user.created_at,
        last_login_at=user.last_login_at,
    )

