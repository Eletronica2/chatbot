"""HMAC service-to-service authentication (AWS AI Engine -> Local AI API).

Canonical string (newline separated):
    METHOD, PATH, X-AA-Timestamp, X-AA-Nonce, X-AA-Tenant, X-AA-Request-Id, sha256(body) hex
Signature: hex(HMAC-SHA256(secret, canonical)).

The tenant is part of the signature, so it cannot be swapped in transit, and it must be one of the
tenants the key is authorized for. Timestamps outside the skew window and reused nonces are rejected.
"""

import base64
import hashlib
import hmac
import json
import re
import time
from dataclasses import dataclass
from datetime import datetime, timezone

from app.domain.models import TENANT_PATTERN

_TENANT_RE = re.compile(TENANT_PATTERN)
_NONCE_RE = re.compile(r"^[A-Za-z0-9_\-]{16,64}$")
_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9_\-:.]{1,64}$")

HEADER_KEY_ID = "x-aa-key-id"
HEADER_TIMESTAMP = "x-aa-timestamp"
HEADER_NONCE = "x-aa-nonce"
HEADER_TENANT = "x-aa-tenant"
HEADER_REQUEST_ID = "x-aa-request-id"
HEADER_SIGNATURE = "x-aa-signature"


class ServiceAuthError(Exception):
    def __init__(self, status: int, code: str):
        super().__init__(code)
        self.status = status
        self.code = code


@dataclass(frozen=True)
class ServiceKey:
    key_id: str
    secret: bytes
    tenants: frozenset[str]
    scopes: frozenset[str]
    not_after: float | None

    def usable(self, now: float) -> bool:
        return self.not_after is None or now <= self.not_after


def canonical_string(method: str, path: str, timestamp: str, nonce: str, tenant: str, request_id: str, body: bytes) -> str:
    return "\n".join([method.upper(), path, timestamp, nonce, tenant, request_id, hashlib.sha256(body).hexdigest()])


def sign(secret: bytes, method: str, path: str, timestamp: str, nonce: str, tenant: str, request_id: str, body: bytes) -> str:
    msg = canonical_string(method, path, timestamp, nonce, tenant, request_id, body).encode("utf-8")
    return hmac.new(secret, msg, hashlib.sha256).hexdigest()


def parse_keys(raw: str) -> dict[str, ServiceKey]:
    """SERVICE_KEYS_JSON: [{"key_id","secret_b64","tenants":[...],"scopes":[...],"not_after":"ISO-8601"|null}]"""
    keys: dict[str, ServiceKey] = {}
    for item in json.loads(raw or "[]"):
        secret = base64.b64decode(item["secret_b64"])
        if len(secret) < 32:
            raise ValueError(f"segredo da chave {item['key_id']} curto demais (mínimo 32 bytes)")
        if "*" in item["tenants"]:
            raise ValueError(f"chave {item['key_id']}: tenants devem ser listados explicitamente")
        not_after = item.get("not_after")
        keys[item["key_id"]] = ServiceKey(
            key_id=item["key_id"],
            secret=secret,
            tenants=frozenset(item["tenants"]),
            scopes=frozenset(item["scopes"]),
            not_after=datetime.fromisoformat(not_after).astimezone(timezone.utc).timestamp() if not_after else None,
        )
    return keys


class NonceCache:
    """Remembers nonces for the skew window; bounded so it cannot grow without limit."""

    def __init__(self, ttl_s: float, max_entries: int = 200_000):
        self.ttl_s = ttl_s
        self.max_entries = max_entries
        self._seen: dict[str, float] = {}

    def check_and_add(self, key: str, now: float) -> bool:
        if len(self._seen) >= self.max_entries:
            self._seen = {k: exp for k, exp in self._seen.items() if exp > now}
            if len(self._seen) >= self.max_entries:
                return False
        exp = self._seen.get(key)
        if exp is not None and exp > now:
            return False
        self._seen[key] = now + self.ttl_s
        return True


class ServiceVerifier:
    def __init__(self, keys: dict[str, ServiceKey], max_skew_s: float = 30.0):
        self.keys = keys
        self.max_skew_s = max_skew_s
        self.nonces = NonceCache(ttl_s=max_skew_s * 2 + 5)

    def verify(self, *, method: str, path: str, headers, body: bytes, scope: str, now: float | None = None) -> tuple[ServiceKey, str, str]:
        now = time.time() if now is None else now
        key_id = headers.get(HEADER_KEY_ID, "")
        ts = headers.get(HEADER_TIMESTAMP, "")
        nonce = headers.get(HEADER_NONCE, "")
        tenant = headers.get(HEADER_TENANT, "")
        request_id = headers.get(HEADER_REQUEST_ID, "")
        signature = headers.get(HEADER_SIGNATURE, "")
        if not all((key_id, ts, nonce, tenant, request_id, signature)):
            raise ServiceAuthError(401, "signature_missing")
        key = self.keys.get(key_id)
        if key is None:
            raise ServiceAuthError(401, "key_unknown")
        if not key.usable(now):
            raise ServiceAuthError(401, "key_expired")
        try:
            ts_value = int(ts)
        except ValueError:
            raise ServiceAuthError(401, "timestamp_invalid") from None
        if abs(now - ts_value) > self.max_skew_s:
            raise ServiceAuthError(401, "timestamp_expired")
        if not _NONCE_RE.match(nonce) or not _REQUEST_ID_RE.match(request_id) or not _TENANT_RE.match(tenant):
            raise ServiceAuthError(400, "header_invalid")
        expected = sign(key.secret, method, path, ts, nonce, tenant, request_id, body)
        if not hmac.compare_digest(expected, signature.lower()):
            raise ServiceAuthError(401, "signature_invalid")
        if not self.nonces.check_and_add(f"{key_id}:{nonce}", now):
            raise ServiceAuthError(401, "replay_detected")
        if scope not in key.scopes:
            raise ServiceAuthError(403, "scope_forbidden")
        if tenant not in key.tenants:
            raise ServiceAuthError(403, "tenant_forbidden")
        return key, tenant, request_id
