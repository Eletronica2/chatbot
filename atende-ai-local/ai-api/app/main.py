import asyncio
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
from app.retrieval.store import KnowledgeStore, TenantScopeError
from app.security.auth import CredentialStore, TenantRegistry
from app.services.knowledge import KnowledgeService
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
    gate = InferenceGate(s.llm_concurrency, s.llm_max_queue, s.llm_queue_timeout_s)
    app.state.encoder = encoder
    app.state.gate = gate
    app.state.responder = Responder(s, encoder, store, llm, gate)
    app.state.knowledge = KnowledgeService(encoder, store)
    app.state.readiness = Readiness(s, encoder, store, llm)
    log_event("startup", detail=f"ready_in_ms={int((time.perf_counter() - started) * 1000)}")
    yield
    await llm.close()
    await store.client.close()


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


@app.get("/v1/status")
async def status(request: Request):
    return {"queue": request.app.state.gate.snapshot(), "embedding_model": request.app.state.encoder.model_name}
