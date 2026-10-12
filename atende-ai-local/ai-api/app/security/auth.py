import hashlib
import hmac
import json
import re
from dataclasses import dataclass, field
from pathlib import Path

from fastapi import Header, HTTPException, Request

from app.domain.models import TENANT_PATTERN
from app.security.service_auth import HEADER_SIGNATURE, ServiceAuthError, ServiceVerifier

_TENANT_RE = re.compile(TENANT_PATTERN)


@dataclass(frozen=True)
class Principal:
    key_id: str
    tenants: frozenset[str]
    scopes: frozenset[str]


@dataclass
class CredentialStore:
    """Service credentials scoped to tenants. Only SHA-256 hashes of tokens are stored."""

    by_hash: dict[str, Principal] = field(default_factory=dict)

    @classmethod
    def load(cls, path: str) -> "CredentialStore":
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        store = cls()
        for item in data.get("credentials", []):
            digest = item["token_sha256"].lower()
            store.by_hash[digest] = Principal(
                key_id=item["key_id"],
                tenants=frozenset(item["tenants"]),
                scopes=frozenset(item["scopes"]),
            )
        return store

    def authenticate(self, token: str) -> Principal | None:
        digest = hashlib.sha256(token.encode("utf-8")).hexdigest()
        for known, principal in self.by_hash.items():
            if hmac.compare_digest(known, digest):
                return principal
        return None


@dataclass
class TenantRegistry:
    tenants: dict[str, dict]

    @classmethod
    def load(cls, path: str) -> "TenantRegistry":
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        return cls(tenants={t["tenant_id"]: t for t in data.get("tenants", [])})

    def get(self, tenant_id: str) -> dict | None:
        return self.tenants.get(tenant_id)


class AuthError(HTTPException):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(status_code=status, detail={"error_code": code, "message": message})


def resolve_tenant(principal: Principal, requested: str | None, registry: TenantRegistry) -> str:
    """The authenticated identity wins over the tenant declared in the body."""
    if requested is None or requested == "":
        if len(principal.tenants) == 1:
            requested = next(iter(principal.tenants))
        else:
            raise AuthError(400, "tenant_required", "tenant_id obrigatório para esta credencial")
    if not _TENANT_RE.match(requested):
        raise AuthError(400, "tenant_invalid", "tenant_id inválido")
    if requested not in principal.tenants:
        raise AuthError(403, "tenant_forbidden", "credencial sem autorização para este tenant")
    if registry.get(requested) is None:
        raise AuthError(404, "tenant_unknown", "tenant não cadastrado")
    return requested


def require_principal(scope: str):
    async def dependency(request: Request, authorization: str | None = Header(None)) -> Principal:
        if HEADER_SIGNATURE in request.headers:
            verifier: ServiceVerifier = request.app.state.service_verifier
            try:
                key, tenant, request_id = verifier.verify(
                    method=request.method, path=request.url.path, headers=request.headers,
                    body=await request.body(), scope=scope,
                )
            except ServiceAuthError as exc:
                raise AuthError(exc.status, exc.code, "autenticação de serviço recusada") from None
            request.state.key_id = key.key_id
            request.state.signed_request_id = request_id
            return Principal(key_id=key.key_id, tenants=frozenset({tenant}), scopes=key.scopes)

        store: CredentialStore = request.app.state.credentials
        if not authorization or not authorization.lower().startswith("bearer "):
            raise AuthError(401, "credential_missing", "credencial ausente")
        principal = store.authenticate(authorization[7:].strip())
        if principal is None:
            raise AuthError(401, "credential_invalid", "credencial inválida")
        if scope not in principal.scopes:
            raise AuthError(403, "scope_forbidden", f"escopo {scope} não autorizado")
        request.state.key_id = principal.key_id
        return principal

    return dependency
