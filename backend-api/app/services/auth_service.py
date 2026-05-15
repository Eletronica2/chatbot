"""Authentication and tenant access helpers for the admin panel."""
from __future__ import annotations

from dataclasses import dataclass

from fastapi import HTTPException, Request, status

from app.config.settings import Settings
from app.domain.auth import AuthTokenResponse, AuthenticatedUser
from app.repositories.user_repository import UserRepository
from app.security.jwt_tools import create_access_token, decode_access_token, hash_password, verify_password


@dataclass(slots=True)
class AuthContext:
    user: AuthenticatedUser
    access_token: str


class AuthService:
    def __init__(self, user_repository: UserRepository, settings: Settings):
        self.user_repository = user_repository
        self.settings = settings

    async def ensure_default_user(self) -> None:
        await self.user_repository.ensure_user(
            tenant_id=self.settings.DEFAULT_TENANT_ID,
            email=self.settings.DEFAULT_ADMIN_EMAIL,
            display_name=self.settings.DEFAULT_ADMIN_NAME,
            password_hash=hash_password(self.settings.DEFAULT_ADMIN_PASSWORD),
            role=self.settings.DEFAULT_ADMIN_ROLE,
        )

    async def login(self, *, email: str, password: str) -> AuthTokenResponse | None:
        row = await self.user_repository.get_by_email(email)
        if row is None or row.get("status") != "active":
            return None
        if not verify_password(password, str(row.get("password_hash") or "")):
            return None
        await self.user_repository.touch_last_login(email)
        user = AuthenticatedUser(
            user_id=str(row.get("id")),
            tenant_id=str(row.get("tenant_id") or self.settings.DEFAULT_TENANT_ID),
            email=str(row.get("email") or email),
            display_name=str(row.get("display_name") or email.split("@")[0]),
            role=str(row.get("role") or "owner"),
            status=str(row.get("status") or "active"),
            created_at=row.get("created_at"),
            last_login_at=row.get("last_login_at"),
        )
        token = create_access_token(
            {
                "sub": user.user_id,
                "tenant_id": user.tenant_id,
                "email": user.email,
                "display_name": user.display_name,
                "role": user.role,
            },
            secret_key=self.settings.APP_SECRET_KEY,
            expires_in_minutes=self.settings.JWT_EXPIRES_MINUTES,
        )
        return AuthTokenResponse(
            access_token=token,
            expires_in=self.settings.JWT_EXPIRES_MINUTES * 60,
            user=user,
        )

    def authenticate_request(self, request: Request, *, required: bool = True) -> AuthenticatedUser | None:
        header = request.headers.get("authorization", "")
        # logger.info(f"AUTH: Authenticating request to {request.url.path}. Header present: {bool(header)}")
        if not header.lower().startswith("bearer "):
            if required:
                import logging
                logging.getLogger("app.services.auth_service").warning(f"AUTH: Missing or invalid header for {request.url.path}: {header[:15]}...")
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Authentication required")
            return None
        token = header.split(" ", 1)[1].strip()
        try:
            payload = decode_access_token(token, secret_key=self.settings.APP_SECRET_KEY)
        except Exception as exc:
            import logging
            logging.getLogger("app.services.auth_service").error(f"AUTH: Token decode failed for {request.url.path}: {exc}")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token") from exc
        user = AuthenticatedUser(
            user_id=str(payload.get("sub") or ""),
            tenant_id=str(payload.get("tenant_id") or self.settings.DEFAULT_TENANT_ID),
            email=str(payload.get("email") or ""),
            display_name=str(payload.get("display_name") or payload.get("email") or ""),
            role=str(payload.get("role") or "owner"),
            status="active",
        )
        request.state.user = user
        request.state.tenant_id = user.tenant_id
        return user

    def assert_internal_api_key(self, request: Request) -> None:
        provided = request.headers.get("x-internal-api-key", "")
        if not provided or provided != self.settings.INTERNAL_API_KEY:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Internal access denied")

