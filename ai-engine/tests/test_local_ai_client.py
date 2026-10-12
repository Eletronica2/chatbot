import base64
import hashlib
import hmac

import httpx

from app.clients.local_ai_client import LocalAIClient, safe_request_id


def _client(handler, *, sleep=None):
    return LocalAIClient(
        base_url="http://local.test", key_id="aws-test",
        secret_b64=base64.b64encode(b"s" * 32).decode(), max_attempts=2,
        total_budget_s=5, transport=httpx.MockTransport(handler), sleep=sleep or _noop,
    )


async def _noop(_seconds):
    return None


def test_request_id_is_stable_and_does_not_expose_raw_value():
    assert safe_request_id("wamid.test-1") == "wamid.test-1"
    assert safe_request_id("bad id with spaces") == safe_request_id("bad id with spaces")
    assert "bad id with spaces" not in safe_request_id("bad id with spaces")


def test_client_signs_tenant_and_retries_503_using_retry_after():
    calls = []

    def handler(request):
        calls.append(request)
        assert request.headers["x-aa-tenant"] == "pizzaria_bella_massa"
        body = request.content
        expected = hmac.new(
            b"s" * 32,
            "\n".join([
                "POST", "/v1/respond", request.headers["x-aa-timestamp"],
                request.headers["x-aa-nonce"], request.headers["x-aa-tenant"],
                request.headers["x-aa-request-id"], hashlib.sha256(body).hexdigest(),
            ]).encode(), hashlib.sha256,
        ).hexdigest()
        assert hmac.compare_digest(request.headers["x-aa-signature"], expected)
        if len(calls) == 1:
            return httpx.Response(503, json={"error_code": "saturated", "retry_after_s": 0},
                                  headers={"Retry-After": "0"})
        return httpx.Response(200, json={"text": "Olá"})

    async def scenario():
        client = _client(handler)
        try:
            data, stats = await client.call(
                "POST", "/v1/respond", tenant="pizzaria_bella_massa", request_id="m-1",
                payload={"tenant_id": "pizzaria_bella_massa", "message": "oi"},
            )
            assert data["text"] == "Olá" and stats.attempts == 2 and len(calls) == 2
        finally:
            await client.close()

    import asyncio
    asyncio.run(scenario())


def test_client_retries_transient_read_timeout_within_attempt_limit():
    calls = 0

    def handler(_request):
        nonlocal calls
        calls += 1
        if calls == 1:
            raise httpx.ReadTimeout("temporary")
        return httpx.Response(200, json={"ok": True})

    async def scenario():
        client = _client(handler)
        try:
            data, stats = await client.call("GET", "/health", tenant="pizzaria_bella_massa", request_id="m-2")
            assert data == {"ok": True} and stats.attempts == 2 and calls == 2
        finally:
            await client.close()

    import asyncio
    asyncio.run(scenario())
