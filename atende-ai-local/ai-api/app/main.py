import asyncio
import json
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.api.routes import router
from app.config.settings import get_settings
from app.embeddings.encoder import Encoder
from app.inference.gate import InferenceGate
from app.inference.ollama_client import OllamaClient
from app.logging import log_event, setup_logging
from app.prompts.builder import PromptParts, build_messages
from app.retrieval.store import KnowledgeStore, TenantScopeError
from app.security.auth import CredentialStore, TenantRegistry
from app.security.service_auth import ServiceVerifier, parse_keys
from app.services.idempotency import IdempotencyCache
from app.services.knowledge import KnowledgeService
from app.services.registry import DocumentRegistry
from app.services.readiness import Readiness
from app.services.responder import Responder


@asynccontextmanager
async def lifespan(app: FastAPI):
    s = get_settings()
    setup_logging(s.log_level)
    app.state.settings = s
    app.state.credentials = CredentialStore.load(s.credentials_file)
    app.state.tenants = TenantRegistry.load(s.tenants_file)
    started = time.perf_counter()
    encoder = await asyncio.to_thread(Encoder, s.embedding_model, s.embedding_threads, s.embedding_dim)
    log_event("startup", detail=f"embedding={encoder.model_name} dim={encoder.dim} load_ms={encoder.load_ms}")
    store = KnowledgeStore(s.qdrant_url, s.qdrant_api_key, s.qdrant_collection, encoder.dim, encoder.model_name)
    await store.ensure_collection()
    llm = OllamaClient(s.ollama_url, s.llm_timeout_s)
    gate = InferenceGate(s.llm_concurrency, s.llm_max_queue, s.llm_queue_timeout_s, s.llm_max_per_tenant)
    service_keys = parse_keys(s.service_keys_json)
    app.state.service_verifier = ServiceVerifier(service_keys, s.service_max_skew_s)
    log_event("startup", detail=f"service_keys={len(service_keys)}")
    app.state.registry = DocumentRegistry(s.registry_path)
    app.state.idempotency = IdempotencyCache(s.idempotency_ttl_s)
    app.state.encoder = encoder
    app.state.gate = gate
    app.state.responder = Responder(s, encoder, store, llm, gate)
    app.state.knowledge = KnowledgeService(encoder, store, app.state.registry)
    app.state.readiness = Readiness(s, encoder, store, llm, app.state.registry)
    log_event("startup", detail=f"ready_in_ms={int((time.perf_counter() - started) * 1000)}")
    served = sorted({t for key in service_keys.values() for t in key.tenants if app.state.tenants.get(t)})
    warmup = asyncio.create_task(_warm_model(app.state.readiness, llm, gate, s, app.state.tenants, served))
    yield
    warmup.cancel()
    await llm.close()
    await store.client.close()


async def _warm_model(readiness: Readiness, llm: OllamaClient, gate: InferenceGate, s, tenants: TenantRegistry,
                      served: list[str], attempts: int = 10, delay_s: float = 15.0) -> None:
    # After a reboot the model is not resident and the stable prompt prefix is not in the KV cache; on CPU the
    # first customer request would pay both (~40 s) and can exceed the caller's deadline. Ollama may still be
    # starting, hence the retries.
    for attempt in range(1, attempts + 1):
        report = await readiness.check()
        detail = report["checks"].get("inference", {}).get("detail")
        if report["ready"]:
            log_event("warmup", detail=f"ok attempt={attempt} {detail}")
            break
        log_event("warmup", detail=f"pending attempt={attempt} {detail}")
        await asyncio.sleep(delay_s)
    else:
        return
    for tenant_id in served:
        tenant = tenants.get(tenant_id) or {}
        messages = build_messages(PromptParts(
            tenant_name=tenant.get("display_name", tenant_id), tenant_profile=tenant.get("profile", ""),
            flow_state="", structured="", documents=[], history=[], summary="", message="ok"))
        try:
            async with gate.slot(tenant_id, timeout_s=s.llm_timeout_s) as _:
                gen = await llm.chat(s.llm_model, messages, num_ctx=s.llm_num_ctx, temperature=0.0, max_tokens=1,
                                     keep_alive=s.llm_keep_alive)
            log_event("warmup", tenant_id=tenant_id, detail=f"prefix prompt_tokens={gen.prompt_tokens} "
                                                            f"total_ms={gen.total_ms}")
        except Exception as exc:
            log_event("warmup", tenant_id=tenant_id, detail=f"prefix error: {str(exc)[:120]}")


app = FastAPI(title="Atende Ai Local AI API", version="0.1.0", lifespan=lifespan, docs_url=None, redoc_url=None)
app.include_router(router)


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError):
    fields = [".".join(str(p) for p in e.get("loc", [])) for e in exc.errors()]
    return JSONResponse({"error_code": "invalid_request", "fields": fields[:10]}, status_code=422)


@app.exception_handler(TenantScopeError)
async def tenant_scope_error(request: Request, exc: TenantScopeError):
    log_event("tenant_scope_violation", path=request.url.path, status=403, error_code="tenant_scope")
    return JSONResponse({"error_code": "tenant_scope"}, status_code=403)


def _network_status(path: str) -> dict | None:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    keys = ("checked_at", "wifi_up", "wifi_signal_dbm", "gateway_ok", "gateway_rtt_ms",
            "gateway_packet_loss_pct", "vpn_peer_ok", "vpn_peer_rtt_ms", "vpn_peer_packet_loss_pct",
            "handshake_age_s", "last_successful_handshake_at", "vpn_restarts_total", "last_action")
    return {k: data.get(k) for k in keys}


@app.get("/v1/status")
async def status(request: Request):
    state = request.app.state
    return {
        "queue": state.gate.snapshot(),
        "embedding_model": state.encoder.model_name,
        "idempotency_hits": state.idempotency.hits,
        "network": _network_status(state.settings.netwatch_file),
    }
