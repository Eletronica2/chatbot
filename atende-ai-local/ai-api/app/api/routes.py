import time

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from app.domain.models import DeleteRequest, RespondRequest, RespondResponse, SearchRequest, UpsertRequest
from app.inference.gate import Saturated
from app.inference.ollama_client import OllamaError
from app.logging import log_event
from app.security.auth import Principal, require_principal, resolve_tenant

router = APIRouter()


@router.get("/health")
async def health():
    return {"status": "ok"}


@router.get("/ready")
async def ready(request: Request):
    report = await request.app.state.readiness.check()
    return JSONResponse(report, status_code=200 if report["ready"] else 503)


def _tenant(request: Request, principal: Principal, requested: str | None) -> tuple[str, dict]:
    registry = request.app.state.tenants
    tenant_id = resolve_tenant(principal, requested, registry)
    request.state.tenant_id = tenant_id
    return tenant_id, registry.get(tenant_id)


@router.post("/v1/respond", response_model=RespondResponse)
async def respond(req: RespondRequest, request: Request, principal: Principal = Depends(require_principal("respond"))):
    tenant_id, tenant = _tenant(request, principal, req.tenant_id)
    started = time.perf_counter()
    try:
        result = await request.app.state.responder.respond(req, tenant_id, tenant)
    except Saturated as exc:
        log_event("respond", request_id=req.request_id, tenant_id=tenant_id, status=503, error_code="saturated",
                  reason=exc.reason, latency_ms=int((time.perf_counter() - started) * 1000))
        return JSONResponse(
            {"error_code": "saturated", "reason": exc.reason, "retry_after_s": exc.retry_after_s,
             "request_id": req.request_id, "queue": request.app.state.gate.snapshot()},
            status_code=503, headers={"Retry-After": str(exc.retry_after_s)},
        )
    except ValueError as exc:
        if str(exc) == "model_not_allowed":
            return JSONResponse({"error_code": "model_not_allowed"}, status_code=400)
        raise
    except OllamaError as exc:
        log_event("respond", request_id=req.request_id, tenant_id=tenant_id, status=502, error_code="inference_error")
        return JSONResponse({"error_code": "inference_error", "detail": str(exc)[:200], "request_id": req.request_id},
                            status_code=502)
    log_event("respond", request_id=req.request_id, tenant_id=tenant_id, key_id=principal.key_id, status=200,
              level=result.level, model=result.model, latency_ms=result.latency_ms,
              prompt_tokens=result.usage.prompt_tokens, completion_tokens=result.usage.completion_tokens,
              retrieval_count=result.retrieval.documents_used, queue_ms=result.timings.queue_ms, guard=result.guard)
    return result


@router.post("/v1/knowledge/upsert")
async def knowledge_upsert(req: UpsertRequest, request: Request,
                           principal: Principal = Depends(require_principal("knowledge:write"))):
    tenant_id, _ = _tenant(request, principal, req.tenant_id)
    results = [await request.app.state.knowledge.upsert(tenant_id, doc) for doc in req.documents]
    log_event("knowledge_upsert", tenant_id=tenant_id, key_id=principal.key_id, documents=len(results),
              chunks=sum(r.get("chunks", 0) for r in results))
    return {"tenant_id": tenant_id, "results": results}


@router.post("/v1/knowledge/delete")
async def knowledge_delete(req: DeleteRequest, request: Request,
                           principal: Principal = Depends(require_principal("knowledge:write"))):
    tenant_id, _ = _tenant(request, principal, req.tenant_id)
    removed = await request.app.state.knowledge.delete(tenant_id, req.document_ids)
    log_event("knowledge_delete", tenant_id=tenant_id, key_id=principal.key_id, documents=len(req.document_ids),
              chunks_removed=removed)
    return {"tenant_id": tenant_id, "chunks_removed": removed}


@router.post("/v1/knowledge/search")
async def knowledge_search(req: SearchRequest, request: Request,
                           principal: Principal = Depends(require_principal("knowledge:read"))):
    tenant_id, _ = _tenant(request, principal, req.tenant_id)
    started = time.perf_counter()
    mode = req.mode or request.app.state.settings.retrieval_mode
    hits = await request.app.state.responder.retrieve(tenant_id, req.query, req.top_k, mode)
    latency = int((time.perf_counter() - started) * 1000)
    log_event("knowledge_search", tenant_id=tenant_id, key_id=principal.key_id, retrieval_count=len(hits),
              latency_ms=latency, mode=mode)
    return {"tenant_id": tenant_id, "mode": mode, "latency_ms": latency, "results": hits}
