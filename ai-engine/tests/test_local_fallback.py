"""Local provider failures must hand the conversation to a human: no canned text, no Gemini call."""
import asyncio
import base64

import httpx
import pytest

from app.api.ai import _to_legacy_response
from app.clients.local_ai_client import LocalAIClient
from app.config.settings import settings
from app.domain.message import AIRequestPayload
from app.services.ai_service import AIService
from app.services.intent_service import intent_service


class _ExternalProviderMustNotRun:
    async def generate_content(self, *args, **kwargs):
        raise AssertionError("Gemini must not be used for a local-provider tenant")

    async def create_chat_completion(self, *args, **kwargs):
        raise AssertionError("OpenAI must not be used for a local-provider tenant")


async def _noop(_seconds):
    return None


def _service(handler, *, configured=True):
    client = LocalAIClient(
        base_url="http://10.77.0.2:8100", key_id="aws-test" if configured else None,
        secret_b64=base64.b64encode(b"s" * 32).decode() if configured else None,
        max_attempts=2, total_budget_s=5, transport=httpx.MockTransport(handler), sleep=_noop,
    )
    external = _ExternalProviderMustNotRun()
    return AIService(openai_client=external, gemini_client=external, intent_service=intent_service,
                     local_client=client), client


def _payload():
    return AIRequestPayload(
        tenant_id="pizzaria_bella_massa", phone_number="5534992665547", message={"text": "Vocês oferecem Wi-Fi?"},
        metadata={"ai_provider": "local", "message_id": "wamid.TEST"},
    )


def _run(service, client):
    async def scenario():
        try:
            return await service.generate(_payload())
        finally:
            await client.close()
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(scenario())
    finally:
        loop.close()


def _raise(exc):
    def handler(request):
        raise exc
    return handler


@pytest.mark.parametrize("name,handler,error", [
    ("wireguard_down", _raise(httpx.ConnectError("unreachable")), "local_ai_unreachable"),
    ("qwen3_timeout", _raise(httpx.ReadTimeout("slow")), "local_ai_timeout"),
    ("queue_full", lambda r: httpx.Response(503, json={"error_code": "saturated", "reason": "queue_full"},
                                             headers={"Retry-After": "0"}), "local_ai_saturated"),
    ("ollama_down", lambda r: httpx.Response(502, json={"error_code": "inference_error"}), "local_ai_inference_error"),
    ("deadline", lambda r: httpx.Response(504, json={"error_code": "deadline_exceeded"}), "local_ai_timeout"),
    ("invalid_hmac", lambda r: httpx.Response(401, json={"detail": {"error_code": "signature_invalid"}}), "local_ai_auth"),
])
def test_local_failures_hand_off_without_reply_or_gemini(monkeypatch, name, handler, error):
    monkeypatch.setattr(settings, "LOCAL_AI_ENABLED", True)
    service, client = _service(handler)
    result = _run(service, client)
    assert result.handled is False, name
    assert result.error.startswith(error), (name, result.error)
    assert result.metadata["provider"] == "local" and result.metadata["handoff_required"] is True
    assert result.metadata["ai_usage"]["status"] == result.error
    legacy = _to_legacy_response(result)
    assert legacy.handled is False and legacy.reply_text == ""


def test_invalid_hmac_is_not_retried(monkeypatch):
    monkeypatch.setattr(settings, "LOCAL_AI_ENABLED", True)
    calls = []

    def handler(request):
        calls.append(request)
        return httpx.Response(401, json={"detail": {"error_code": "signature_invalid"}})

    service, client = _service(handler)
    _run(service, client)
    assert len(calls) == 1


@pytest.mark.parametrize("enabled,configured", [(False, True), (True, False)])
def test_kill_switch_or_missing_credential_never_falls_back_to_gemini(monkeypatch, enabled, configured):
    monkeypatch.setattr(settings, "LOCAL_AI_ENABLED", enabled)
    service, client = _service(lambda r: httpx.Response(200, json={"text": "não deveria"}), configured=configured)
    result = _run(service, client)
    assert result.handled is False and result.error == "local_ai_disabled"
    assert _to_legacy_response(result).reply_text == ""


def test_local_success_reports_provider_model_and_tokens(monkeypatch):
    monkeypatch.setattr(settings, "LOCAL_AI_ENABLED", True)
    body = {"text": "Não tenho essa informação confirmada no momento. Posso encaminhar sua dúvida para a equipe?",
            "model": "qwen3:4b-instruct-2507-q4_K_M", "level": "rag", "usage": {"prompt_tokens": 900, "completion_tokens": 20},
            "latency_ms": 9000, "timings": {"queue_ms": 0}, "retrieval": {"documents_used": 2}, "actions": []}
    service, client = _service(lambda r: httpx.Response(200, json=body))
    result = _run(service, client)
    assert result.handled is True and result.reply.content.startswith("Não tenho")
    usage = result.metadata["ai_usage"]
    assert (usage["provider"], usage["model"], usage["input_tokens"], usage["output_tokens"]) == (
        "local", "qwen3:4b-instruct-2507-q4_K_M", 900, 20)
