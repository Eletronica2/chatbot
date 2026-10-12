"""Client for the local AI server (Atende AI Local) over the private WireGuard tunnel.

Every request is signed (HMAC-SHA256 over method, path, timestamp, nonce, tenant, request_id and body hash),
so the local server can reject forged, replayed or tenant-swapped calls. One overall deadline covers all
attempts; the remaining budget is sent to the server so it stops generating when we stop waiting.
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import logging
import random
import re
import secrets
import time
from dataclasses import dataclass, field
from typing import Any, Dict, Optional

import httpx

logger = logging.getLogger(__name__)

_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9_\-:.]{1,64}$")
MIN_ATTEMPT_S = 2.0
SERVER_MARGIN_S = 0.5


class LocalAIError(Exception):
    def __init__(self, code: str, *, retryable: bool = False, retry_after_s: float | None = None,
                 status: int | None = None):
        super().__init__(code)
        self.code = code
        self.retryable = retryable
        self.retry_after_s = retry_after_s
        self.status = status
        self.stats: "CallStats | None" = None

    def with_stats(self, stats: "CallStats") -> "LocalAIError":
        self.stats = stats
        return self


@dataclass
class CallStats:
    request_id: str
    attempts: int = 0
    errors: list = field(default_factory=list)
    started: float = field(default_factory=time.monotonic)

    @property
    def elapsed_ms(self) -> int:
        return int((time.monotonic() - self.started) * 1000)


def safe_request_id(value: Any) -> str:
    """Stable id per inbound message (retries reuse it, so the server can deduplicate)."""
    raw = str(value or "").strip()
    if raw and _REQUEST_ID_RE.match(raw):
        return raw
    if raw:
        return "m-" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:40]
    return "r-" + secrets.token_hex(16)


def sign(secret: bytes, method: str, path: str, timestamp: str, nonce: str, tenant: str, request_id: str,
         body: bytes) -> str:
    canonical = "\n".join([method.upper(), path, timestamp, nonce, tenant, request_id,
                           hashlib.sha256(body).hexdigest()])
    return hmac.new(secret, canonical.encode("utf-8"), hashlib.sha256).hexdigest()


class CircuitBreaker:
    """Opens after N consecutive connection failures; one probe is allowed after the cooldown."""

    def __init__(self, threshold: int, cooldown_s: float):
        self.threshold = max(1, threshold)
        self.cooldown_s = cooldown_s
        self.failures = 0
        self.open_until = 0.0
        self.opened_total = 0

    def allow(self, now: float | None = None) -> bool:
        return (now or time.monotonic()) >= self.open_until

    def success(self) -> None:
        self.failures = 0
        self.open_until = 0.0

    def failure(self, now: float | None = None) -> None:
        self.failures += 1
        if self.failures >= self.threshold:
            self.open_until = (now or time.monotonic()) + self.cooldown_s
            self.opened_total += 1

    def snapshot(self) -> Dict[str, Any]:
        remaining = max(0.0, self.open_until - time.monotonic())
        return {"state": "open" if remaining > 0 else "closed", "consecutive_failures": self.failures,
                "retry_in_s": round(remaining, 1), "opened_total": self.opened_total}


class LocalAIClient:
    def __init__(self, *, base_url: str, key_id: Optional[str], secret_b64: Optional[str],
                 connect_timeout_s: float = 3.0, total_budget_s: float = 45.0, max_attempts: int = 2,
                 backoff_base_s: float = 0.5, backoff_max_s: float = 4.0, breaker_threshold: int = 3,
                 breaker_cooldown_s: float = 30.0, transport: httpx.AsyncBaseTransport | None = None,
                 sleep=asyncio.sleep):
        self.base_url = base_url.rstrip("/")
        self.key_id = key_id
        self._secret = base64.b64decode(secret_b64) if secret_b64 else None
        self.connect_timeout_s = connect_timeout_s
        self.total_budget_s = total_budget_s
        self.max_attempts = max(1, max_attempts)
        self.backoff_base_s = backoff_base_s
        self.backoff_max_s = backoff_max_s
        self.breaker = CircuitBreaker(breaker_threshold, breaker_cooldown_s)
        self._sleep = sleep
        self._client = httpx.AsyncClient(
            base_url=self.base_url,
            transport=transport,
            limits=httpx.Limits(max_connections=8, max_keepalive_connections=4),
        )

    @property
    def configured(self) -> bool:
        return bool(self.key_id and self._secret and len(self._secret) >= 32)

    async def close(self) -> None:
        await self._client.aclose()

    def _headers(self, method: str, path: str, tenant: str, request_id: str, body: bytes) -> Dict[str, str]:
        ts = str(int(time.time()))
        nonce = secrets.token_urlsafe(18)
        return {
            "content-type": "application/json",
            "x-aa-key-id": self.key_id or "",
            "x-aa-timestamp": ts,
            "x-aa-nonce": nonce,
            "x-aa-tenant": tenant,
            "x-aa-request-id": request_id,
            "x-aa-signature": sign(self._secret or b"", method, path, ts, nonce, tenant, request_id, body),
        }

    def _backoff(self, attempt: int) -> float:
        base = min(self.backoff_max_s, self.backoff_base_s * (2 ** (attempt - 1)))
        return base * random.uniform(0.5, 1.5)

    async def _send(self, method: str, path: str, tenant: str, request_id: str, payload: Dict[str, Any] | None,
                    timeout_s: float, params: Dict[str, str] | None = None) -> httpx.Response:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8") if payload is not None else b""
        headers = self._headers(method, path, tenant, request_id, body)
        timeout = httpx.Timeout(timeout_s, connect=min(self.connect_timeout_s, timeout_s))
        return await self._client.request(method, path, content=body or None, headers=headers, timeout=timeout,
                                          params=params)

    async def call(self, method: str, path: str, *, tenant: str, request_id: str,
                   payload: Dict[str, Any] | None = None, params: Dict[str, str] | None = None,
                   budget_s: float | None = None, deadline_field: bool = False) -> tuple[Dict[str, Any], CallStats]:
        stats = CallStats(request_id=request_id)
        if not self.configured:
            raise LocalAIError("local_ai_not_configured").with_stats(stats)
        deadline = time.monotonic() + (budget_s or self.total_budget_s)
        last_error: LocalAIError | None = None
        for attempt in range(1, self.max_attempts + 1):
            if not self.breaker.allow():
                raise LocalAIError("local_ai_circuit_open").with_stats(stats)
            remaining = deadline - time.monotonic()
            if remaining < MIN_ATTEMPT_S:
                break
            stats.attempts = attempt
            body = payload
            if deadline_field and payload is not None:
                options = dict(payload.get("options") or {})
                options["deadline_ms"] = max(1000, int((remaining - SERVER_MARGIN_S) * 1000))
                body = {**payload, "options": options}
            try:
                response = await self._send(method, path, tenant, request_id, body, remaining, params)
            except (httpx.ConnectError, httpx.ConnectTimeout) as exc:
                self.breaker.failure()
                last_error = LocalAIError("local_ai_unreachable", retryable=True)
                stats.errors.append(type(exc).__name__)
            except httpx.TimeoutException as exc:
                stats.errors.append(type(exc).__name__)
                last_error = LocalAIError("local_ai_timeout", retryable=True)
            except httpx.HTTPError as exc:
                self.breaker.failure()
                last_error = LocalAIError("local_ai_transport_error", retryable=True)
                stats.errors.append(type(exc).__name__)
            else:
                self.breaker.success()
                if response.status_code == 200:
                    return response.json(), stats
                last_error = self._classify(response)
                stats.errors.append(f"http_{response.status_code}:{last_error.code}")
            if not last_error.retryable or attempt == self.max_attempts:
                break
            delay = self._backoff(attempt)
            if last_error.retry_after_s:
                delay = max(delay, last_error.retry_after_s)
            if delay + MIN_ATTEMPT_S > deadline - time.monotonic():
                break
            await self._sleep(delay)
        raise (last_error or LocalAIError("local_ai_timeout")).with_stats(stats)

    @staticmethod
    def _classify(response: httpx.Response) -> LocalAIError:
        try:
            data = response.json()
        except ValueError:
            data = {}
        code = str(data.get("error_code") or "")
        status = response.status_code
        if status == 503:
            retry_after = None
            try:
                retry_after = float(response.headers.get("retry-after") or data.get("retry_after_s") or 0) or None
            except ValueError:
                retry_after = None
            return LocalAIError("local_ai_saturated", retryable=True, retry_after_s=retry_after, status=status)
        if status == 504:
            return LocalAIError("local_ai_timeout", retryable=True, status=status)
        if status in (401, 403):
            return LocalAIError(f"local_ai_auth_{code or status}", status=status)
        if status in (400, 422):
            return LocalAIError(f"local_ai_bad_request_{code or status}", status=status)
        if status == 502:
            return LocalAIError("local_ai_inference_error", retryable=True, status=status)
        return LocalAIError(f"local_ai_http_{status}", retryable=status >= 500, status=status)

    async def respond(self, tenant: str, request_id: str, payload: Dict[str, Any]) -> tuple[Dict[str, Any], CallStats]:
        return await self.call("POST", "/v1/respond", tenant=tenant, request_id=request_id, payload=payload,
                               deadline_field=True)

    async def sync(self, tenant: str, request_id: str, operations: list) -> tuple[Dict[str, Any], CallStats]:
        return await self.call("POST", "/v1/knowledge/sync", tenant=tenant, request_id=request_id,
                               payload={"tenant_id": tenant, "operations": operations}, budget_s=120.0)

    async def manifest(self, tenant: str, request_id: str) -> tuple[Dict[str, Any], CallStats]:
        return await self.call("GET", "/v1/knowledge/manifest", tenant=tenant, request_id=request_id,
                               params={"tenant_id": tenant}, budget_s=15.0)

    async def probe(self) -> Dict[str, Any]:
        """Unauthenticated readiness probe (cheap; the server caches its own inference check)."""
        started = time.monotonic()
        try:
            ready = await self._client.get("/ready", timeout=httpx.Timeout(8.0, connect=self.connect_timeout_s))
            status = await self._client.get("/v1/status", timeout=httpx.Timeout(5.0, connect=self.connect_timeout_s))
            body = ready.json()
            return {
                "reachable": True,
                "ready": bool(body.get("ready")),
                "checks": {k: bool(v.get("ok")) for k, v in (body.get("checks") or {}).items()},
                "status": status.json() if status.status_code == 200 else None,
                "latency_ms": int((time.monotonic() - started) * 1000),
            }
        except (httpx.HTTPError, ValueError) as exc:
            return {"reachable": False, "ready": False, "error": type(exc).__name__,
                    "latency_ms": int((time.monotonic() - started) * 1000)}
