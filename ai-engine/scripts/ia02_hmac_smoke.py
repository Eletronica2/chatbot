#!/usr/bin/env python3
"""Explicit private IA-02 integration runner. Reads short-lived test keys from stdin only.

Run inside the existing AI Engine container. It invokes the shipped LocalAIClient and
local_provider directly; it never changes LOCAL_AI_ENABLED or the live message router.
Output contains fixture responses and timings, never key material.
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import secrets
import sys
import time
from datetime import datetime, timezone

import httpx

from app.clients.local_ai_client import LocalAIClient, LocalAIError, sign
from app.config.settings import settings
from app.domain.message import AIRequestPayload
from app.services.local_provider import generate_local


BASE = "http://10.77.0.2:8100"
BELLA = "pizzaria_bella_massa"
ZE = "pastelaria_do_ze"
SCOPES = {"respond", "knowledge:read", "knowledge:write"}
REPORT: list[str] = []


def check(condition: bool, name: str, detail: str = "") -> None:
    if not condition:
        raise AssertionError(f"FAIL | {name}" + (f" | {detail}" if detail else ""))
    REPORT.append(f"PASS | {name}" + (f" | {detail}" if detail else ""))


class CapturingLocalAIClient(LocalAIClient):
    last_response: dict | None = None
    last_stats = None

    async def respond(self, tenant: str, request_id: str, payload: dict):
        result, stats = await super().respond(tenant, request_id, payload)
        self.last_response, self.last_stats = result, stats
        return result, stats


def parse_bundle() -> dict[str, dict]:
    bundle = json.load(sys.stdin)
    entries = bundle.get("keys", [])
    check(isinstance(entries, list) and len(entries) == 3, "bundle_identity_set")
    keys = {}
    expected = {BELLA: SCOPES, ZE: SCOPES}
    for tenant, scopes in expected.items():
        matches = [item for item in entries if item.get("tenants") == [tenant]
                   and set(item.get("scopes", [])) == scopes]
        check(len(matches) == 1, "one_full_credential_per_tenant", tenant)
        keys[tenant] = matches[0]
    readonly = [item for item in entries if item.get("tenants") == [BELLA]
                and set(item.get("scopes", [])) == {"respond"}]
    check(len(readonly) == 1, "read_only_negative_scope_credential")
    keys["bella_readonly"] = readonly[0]
    for role, item in keys.items():
        tenant = item["tenants"][0]
        secret = base64.b64decode(item["secret_b64"], validate=True)
        check(len(secret) >= 32, "credential_minimum_256_bits", role)
        check(item.get("tenants") == [tenant], "credential_is_tenant_restricted", role)
    return keys


def new_client(key: dict, *, attempts: int = 1, budget: float = 45) -> CapturingLocalAIClient:
    return CapturingLocalAIClient(
        base_url=BASE,
        key_id=key["key_id"],
        secret_b64=key["secret_b64"],
        connect_timeout_s=3,
        total_budget_s=budget,
        max_attempts=attempts,
        breaker_threshold=3,
        breaker_cooldown_s=30,
    )


def auth_headers(key: dict, method: str, path: str, tenant: str, request_id: str,
                 body: bytes = b"", *, timestamp: str | None = None, nonce: str | None = None) -> dict[str, str]:
    timestamp = timestamp or str(int(time.time()))
    nonce = nonce or secrets.token_urlsafe(18)
    secret = base64.b64decode(key["secret_b64"], validate=True)
    return {
        "content-type": "application/json",
        "x-aa-key-id": key["key_id"],
        "x-aa-timestamp": timestamp,
        "x-aa-nonce": nonce,
        "x-aa-tenant": tenant,
        "x-aa-request-id": request_id,
        "x-aa-signature": sign(secret, method, path, timestamp, nonce, tenant, request_id, body),
    }


async def raw_request(method: str, path: str, headers: dict[str, str] | None = None,
                      body: bytes = b"") -> httpx.Response:
    async with httpx.AsyncClient(timeout=12) as client:
        return await client.request(method, BASE + path, headers=headers, content=body or None)


async def available_paths() -> set[str]:
    response = await raw_request("GET", "/openapi.json")
    if response.status_code != 200:
        raise RuntimeError(f"local_api_openapi_http_{response.status_code}")
    return set(response.json().get("paths", {}))


async def seed_fixture(client: LocalAIClient, tenant: str, doc_id: str, title: str,
                       content: str, run_id: str, paths: set[str]) -> dict:
    if "/v1/knowledge/sync" in paths:
        op = {"op": "upsert", "document_id": doc_id, "version": 1,
              "content_hash": hashlib.sha256(content.encode()).hexdigest(),
              "updated_at": datetime.now(timezone.utc).isoformat(), "status": "active",
              "title": title, "content": content, "content_type": "markdown"}
        result, _ = await client.sync(tenant, "ia02-seed-" + run_id, [op])
        return result
    if "/v1/knowledge/upsert" in paths:
        result, _ = await client.call(
            "POST", "/v1/knowledge/upsert", tenant=tenant, request_id="ia02-seed-" + run_id,
            payload={"documents": [{"document_id": doc_id, "title": title, "content": content,
                                    "source": "ia02-synthetic-fixture", "document_version": 1,
                                    "content_type": "markdown"}]}, budget_s=45)
        return result
    raise RuntimeError("local_api_has_no_supported_knowledge_write_route")


async def delete_fixture(client: LocalAIClient, tenant: str, doc_id: str, run_id: str,
                         paths: set[str]) -> dict:
    if "/v1/knowledge/sync" in paths:
        op = {"op": "delete", "document_id": doc_id, "version": 2,
              "updated_at": datetime.now(timezone.utc).isoformat(), "status": "deleted"}
        result, _ = await client.sync(tenant, "ia02-clean-" + run_id, [op])
        return result
    if "/v1/knowledge/delete" in paths:
        result, _ = await client.call(
            "POST", "/v1/knowledge/delete", tenant=tenant, request_id="ia02-clean-" + run_id,
            payload={"document_ids": [doc_id]}, budget_s=30)
        return result
    raise RuntimeError("local_api_has_no_supported_knowledge_delete_route")


def error_code(response: httpx.Response) -> str:
    try:
        data = response.json()
        if not isinstance(data, dict):
            return ""
        detail = data.get("detail") or {}
        if not isinstance(detail, dict):
            detail = {}
        return str(detail.get("error_code") or data.get("error_code") or "")
    except ValueError:
        return ""


async def signed_search(client: LocalAIClient, tenant: str, query: str, *, body_tenant: str | None = None):
    payload = {"query": query, "top_k": 4, "mode": "hybrid"}
    if body_tenant is not None:
        payload["tenant_id"] = body_tenant
    return await client.call("POST", "/v1/knowledge/search", tenant=tenant,
                             request_id="ia02-search-" + secrets.token_hex(8), payload=payload,
                             budget_s=20)


async def test_negative_auth(keys: dict[str, dict]) -> None:
    probe_body = json.dumps({"query": "ia02-fixture", "top_k": 2}, separators=(",", ":")).encode()
    path = "/v1/knowledge/search"

    r = await raw_request("POST", path, {"content-type": "application/json"}, probe_body)
    check(r.status_code == 401 and error_code(r) == "credential_missing", "missing_hmac_rejected")

    hdr = auth_headers(keys[BELLA], "POST", path, BELLA, "neg-invalid", probe_body)
    hdr["x-aa-signature"] = "0" * 64
    r = await raw_request("POST", path, hdr, probe_body)
    check(r.status_code == 401 and error_code(r) == "signature_invalid", "invalid_hmac_rejected")

    hdr = auth_headers(keys[BELLA], "POST", path, BELLA, "neg-body", probe_body)
    changed = b'{"query":"tenant crossover","top_k":2}'
    r = await raw_request("POST", path, hdr, changed)
    check(r.status_code == 401 and error_code(r) == "signature_invalid", "body_tamper_rejected")

    hdr = auth_headers(keys[BELLA], "POST", path, BELLA, "neg-path", probe_body)
    # Keep the method valid on the alternate route so routing does not return 405 before auth runs.
    r = await raw_request("POST", "/v1/knowledge/upsert", hdr, probe_body)
    check(r.status_code == 401 and error_code(r) == "signature_invalid", "path_tamper_rejected",
          f"status={r.status_code} error={error_code(r)}")

    old_ts = str(int(time.time()) - 90)
    hdr = auth_headers(keys[BELLA], "POST", path, BELLA,
                       "neg-expired", probe_body, timestamp=old_ts)
    r = await raw_request("POST", path, hdr, probe_body)
    check(r.status_code == 401 and error_code(r) == "timestamp_expired", "expired_timestamp_rejected")

    unknown = dict(keys[BELLA])
    unknown["key_id"] = "unknown-ia02-test-key"
    hdr = auth_headers(unknown, "POST", path, BELLA, "neg-unknown", probe_body)
    r = await raw_request("POST", path, hdr, probe_body)
    check(r.status_code == 401 and error_code(r) == "key_unknown", "unknown_identity_rejected")

    hdr = auth_headers(keys[BELLA], "POST", path, ZE, "neg-tenant-header", probe_body)
    r = await raw_request("POST", path, hdr, probe_body)
    check(r.status_code == 403 and error_code(r) == "tenant_forbidden", "unauthorized_signed_tenant_rejected")

    cross_body = json.dumps({"tenant_id": ZE, "query": "fixture", "top_k": 2}, separators=(",", ":")).encode()
    hdr = auth_headers(keys[BELLA], "POST", path, BELLA, "neg-tenant-body", cross_body)
    r = await raw_request("POST", path, hdr, cross_body)
    check(r.status_code == 403 and error_code(r) == "tenant_forbidden", "tenant_body_cannot_expand_identity")

    ro = keys["bella_readonly"]
    hdr = auth_headers(ro, "POST", path, BELLA, "neg-scope", probe_body)
    r = await raw_request("POST", path, hdr, probe_body)
    check(r.status_code == 403 and error_code(r) == "scope_forbidden", "insufficient_scope_rejected")

    # One-tenant identities may omit tenant_id in JSON; the authenticated identity supplies it.
    omitted = json.dumps({"query": "fixture", "top_k": 1}, separators=(",", ":")).encode()
    hdr = auth_headers(keys[BELLA], "POST", path, BELLA, "tenant-omitted", omitted)
    r = await raw_request("POST", path, hdr, omitted)
    check(r.status_code == 200 and r.json().get("tenant_id") == BELLA,
          "omitted_body_tenant_resolves_to_single_tenant_identity")

    req_id = "ia02-replay-" + secrets.token_hex(8)
    replay_body = json.dumps({"query": "IA-02 replay probe", "top_k": 1}, separators=(",", ":")).encode()
    replay_headers = auth_headers(keys[BELLA], "POST", path, BELLA, req_id, replay_body)
    first = await raw_request("POST", path, replay_headers, replay_body)
    second = await raw_request("POST", path, replay_headers, replay_body)
    check(first.status_code == 200, "replay_seed_request_accepted")
    check(second.status_code == 401 and error_code(second) == "replay_detected", "nonce_replay_rejected")


async def main() -> int:
    check(settings.LOCAL_AI_ENABLED is False, "global_local_provider_remains_disabled")
    check(settings.LOCAL_AI_BASE_URL == BASE, "private_vpn_url_configured")
    keys = parse_bundle()
    bella_key = keys[BELLA]
    ze_key = keys[ZE]
    check(settings.LOCAL_AI_KEY_ID == bella_key["key_id"], "ai_engine_key_is_tenant_a_only")
    check(settings.LOCAL_AI_SECRET_B64 == bella_key["secret_b64"], "ai_engine_secret_matches_staged_bundle")
    paths = await available_paths()
    check("/v1/knowledge/search" in paths and
          ("/v1/knowledge/sync" in paths or "/v1/knowledge/upsert" in paths) and
          ("/v1/knowledge/sync" in paths or "/v1/knowledge/delete" in paths),
          "local_api_routes_support_fixture_lifecycle")

    bella = new_client({"key_id": settings.LOCAL_AI_KEY_ID, "secret_b64": settings.LOCAL_AI_SECRET_B64}, attempts=2)
    ze = new_client(ze_key, attempts=2)
    ro = new_client(keys["bella_readonly"], attempts=1)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(3)
    bella_doc = f"fixture-ia02-bella-{run_id}"
    ze_doc = f"fixture-ia02-ze-{run_id}"
    fixtures = [
        (bella, BELLA, bella_doc, "Fixture IA-02 — Pizzaria Bella Massa",
         "Documento fictício exclusivo do teste IA-02. Pizza de calabresa grande custa R$ 65,00. "
         "A massa tem fermentação lenta de 24 horas e a receita leva molho de tomate e queijo. "
         "Código de fixture: nebulosa rubi calabresa."),
        (ze, ZE, ze_doc, "Fixture IA-02 — Pastelaria do Zé",
         "Documento fictício exclusivo do teste IA-02. Pastel de carne custa R$ 12,00 e é frito na hora. "
         "Código de fixture: horizonte azul pastel de carne."),
    ]

    try:
        for client, tenant, doc_id, title, content in fixtures:
            result = await seed_fixture(client, tenant, doc_id, title, content, run_id, paths)
            check(result.get("tenant_id") == tenant and bool(result.get("results")),
                  "fixture_sync_" + tenant)

        for client, tenant, own_doc in [
            (bella, BELLA, bella_doc), (ze, ZE, ze_doc)
        ]:
            result, _ = await signed_search(client, tenant, "fixture preço produto")
            hits = result.get("results", [])
            check(result.get("tenant_id") == tenant and all(h.get("tenant_id") == tenant for h in hits),
                  "retrieval_filtered_to_" + tenant)
            check(any(h.get("document_id") == own_doc for h in hits), "retrieval_contains_own_fixture_" + tenant)
        await test_negative_auth(keys)

        # Exercise the actual provider adapter and LocalAIClient with the private Qwen endpoint.
        payload = AIRequestPayload(
            tenant_id=BELLA,
            session_id="ia02-hmac-integration",
            message="Quanto custa a pizza de calabresa grande? Responda com uma explicação curta, em português do Brasil, usando somente o documento da empresa.",
            context=[],
            metadata={"request_id": "ia02-price-" + run_id,
                      "local_ai": {"tenant_key": BELLA, "business_context": {}}},
        )
        provider_result = await generate_local(bella, payload, payload.metadata, None, None, None)
        raw = bella.last_response or {}
        check(provider_result.handled and raw.get("request_id") == "ia02-price-" + run_id,
              "real_provider_call_over_signed_vpn")
        check(raw.get("tenant_id") == BELLA and raw.get("language") == "pt-BR", "response_identity_and_language")
        check(raw.get("model") and (raw.get("usage") or {}).get("completion_tokens", 0) > 0,
              "qwen_generation_confirmed_with_real_token_usage")
        check((raw.get("retrieval") or {}).get("documents_used", 0) > 0,
              "qdrant_retrieval_used_for_inference")
        provider_text = provider_result.reply.content if provider_result.reply else ""
        check("65" in provider_text, "price_answer_grounded_in_bella_fixture")
        REPORT.append("RESULT | text=" + provider_text.replace("\n", " ")[:500])
        REPORT.append("METRICS | request_id=" + str(raw.get("request_id"))
                      + " model=" + str(raw.get("model"))
                      + " level=" + str(raw.get("level"))
                      + " total_ms=" + str((bella.last_stats.elapsed_ms if bella.last_stats else None))
                      + " server_ms=" + str(raw.get("latency_ms"))
                      + " queue_ms=" + str((raw.get("timings") or {}).get("queue_ms"))
                      + " retrieval_ms=" + str((raw.get("timings") or {}).get("retrieval_ms"))
                      + " generation_ms=" + str((raw.get("timings") or {}).get("generation_ms"))
                      + " prompt_tokens=" + str((raw.get("usage") or {}).get("prompt_tokens"))
                      + " completion_tokens=" + str((raw.get("usage") or {}).get("completion_tokens"))
                      + " retrieval_docs=" + str((raw.get("retrieval") or {}).get("documents_used")))

        # Unknown commercial fact must not be asserted; this is still an authenticated AI Engine provider call.
        unknown_payload = AIRequestPayload(
            tenant_id=BELLA,
            session_id="ia02-hmac-unknown",
            message="Vocês oferecem Wi-Fi grátis?",
            context=[],
            metadata={"request_id": "ia02-unknown-" + run_id,
                      "local_ai": {"tenant_key": BELLA, "business_context": {}}},
        )
        unknown = await generate_local(bella, unknown_payload, unknown_payload.metadata, None, None, None)
        unknown_raw = bella.last_response or {}
        text = unknown.reply.content if unknown.reply else ""
        check(unknown.handled and not any(term in text.lower() for term in
              ("oferecemos wi-fi", "temos wi-fi", "não oferecemos wi-fi", "nao oferecemos wi-fi", "não temos wi-fi")),
              "unknown_wifi_claim_not_invented")
        check(bool(unknown_raw.get("actions")) or unknown_raw.get("guard") is not None
              or "confirmar" in text.lower() or "informação" in text.lower() or "informacao" in text.lower(),
              "unknown_fact_safe_response")

        # One active + one waiting for the same tenant; the third must receive bounded 503.
        async def concurrent_call(index: int):
            client = new_client(bella_key, attempts=1, budget=90)
            request = AIRequestPayload(
                tenant_id=BELLA,
                session_id=f"ia02-concurrency-{index}",
                message=("Explique em uma frase como é preparada a pizza de calabresa grande, "
                         "usando somente a fixture da empresa."),
                context=[],
                metadata={"request_id": f"ia02-concurrency-{run_id}-{index}",
                          "local_ai": {"tenant_key": BELLA, "business_context": {}}},
            )
            try:
                result = await generate_local(client, request, request.metadata, None, None, None)
                return index, result, client.last_response
            finally:
                await client.close()

        concurrency_results = await asyncio.gather(*(concurrent_call(i) for i in range(3)))
        admitted = [item for item in concurrency_results if item[1].handled]
        rejected = [item for item in concurrency_results if not item[1].handled]
        check(len(admitted) == 2, "same_tenant_concurrency_admits_active_plus_waiting")
        check(len(rejected) == 1 and rejected[0][1].error == "local_ai_saturated",
              "same_tenant_overflow_returns_bounded_503")
        check(all((item[2] or {}).get("usage", {}).get("completion_tokens", 0) > 0 for item in admitted),
              "admitted_concurrent_requests_used_real_qwen_tokens")
        REPORT.append("CONCURRENCY | submitted=3 admitted=2 rejected=1 provider_global_enabled=false")

        # Test the LocalAIClient's timeout/unavailable handling without stopping any service.
        short = new_client(bella_key, attempts=1, budget=2)
        try:
            await short.call("GET", "/v1/knowledge/manifest", tenant=BELLA,
                             request_id="ia02-short-deadline", budget_s=1)
            check(False, "short_deadline_rejected")
        except LocalAIError as exc:
            check(exc.code == "local_ai_timeout", "short_deadline_classified")
        finally:
            await short.close()
        down = LocalAIClient(base_url="http://10.77.0.2:9", key_id=bella_key["key_id"],
                             secret_b64=bella_key["secret_b64"], connect_timeout_s=1,
                             total_budget_s=3, max_attempts=1)
        try:
            await down.manifest(BELLA, "ia02-closed-port")
            check(False, "closed_port_detected")
        except LocalAIError as exc:
            check(exc.code == "local_ai_unreachable" and exc.retryable, "closed_port_handled_without_service_stop")
        finally:
            await down.close()

        saturated = LocalAIClient._classify(httpx.Response(
            503, json={"error_code": "saturated", "retry_after_s": 7}, headers={"Retry-After": "7"}))
        check(saturated.retryable and saturated.retry_after_s == 7, "503_retry_after_classification")

    finally:
        # Tombstone only the two unique synthetic fixture documents created by this run.
        for client, tenant, doc_id in [(bella, BELLA, bella_doc), (ze, ZE, ze_doc)]:
            try:
                result = await delete_fixture(client, tenant, doc_id, run_id, paths)
                cleaned = result.get("tenant_id") == tenant and (
                    bool(result.get("results")) or "chunks_removed" in result)
                check(cleaned,
                      "fixture_cleanup_" + tenant)
            except Exception as exc:
                REPORT.append("FAIL | fixture_cleanup_" + tenant + " | " + type(exc).__name__)
        await bella.close()
        await ze.close()
        await ro.close()

    for line in REPORT:
        print(line)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except Exception as exc:
        for line in REPORT:
            print(line)
        print(f"FAIL | integration_runner | {type(exc).__name__}: {exc}")
        raise SystemExit(1)
