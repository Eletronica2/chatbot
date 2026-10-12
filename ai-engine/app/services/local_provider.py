"""Maps AI Engine requests to the local AI server contract and back.

The tenant comes from the backend (resolved from the WhatsApp number / authenticated panel user), never
from the model. The customer's phone number is not sent: the conversation is identified by a hash.
"""
from __future__ import annotations

import hashlib
import logging
from typing import Any, Dict, List

from app.clients.local_ai_client import CallStats, LocalAIClient, LocalAIError, safe_request_id
from app.domain.message import AIReply, AIRequestPayload, AIResponsePayload

logger = logging.getLogger(__name__)

MAX_HISTORY = 6
MAX_BUSINESS_CONTEXT_BYTES = 20_000


def conversation_ref(payload: AIRequestPayload) -> str:
    raw = f"{payload.tenant_id}:{payload.session_id or payload.phone_number or ''}"
    return "c-" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:24]


def build_flow_context(metadata: Dict[str, Any]) -> Dict[str, Any]:
    flow: Dict[str, Any] = {}
    for src, dst in (("flow_name", "flow"), ("flow_step", "step"), ("detected_intent", "intent"),
                     ("order_status", "order_status")):
        value = metadata.get(src)
        if isinstance(value, (str, int, float)) and str(value).strip():
            flow[dst] = str(value)[:160]
    state_message = metadata.get("flow_state_message")
    if isinstance(state_message, str) and state_message.strip():
        flow["notes"] = state_message.strip()[:160]
    collected = metadata.get("collected_data")
    if isinstance(collected, dict) and collected:
        flow["collected_data"] = {str(k)[:40]: v for k, v in list(collected.items())[:8]
                                  if isinstance(v, (str, int, float, bool))}
    options = metadata.get("options")
    if isinstance(options, list):
        labels = [str(o.get("label") or o.get("value") or "").strip() for o in options if isinstance(o, dict)]
        labels = [label[:40] for label in labels if label][:8]
        if labels:
            flow["next_actions"] = labels
    allowed = metadata.get("allowed_actions")
    if isinstance(allowed, list):
        flow["allowed_actions"] = [str(a)[:40] for a in allowed if isinstance(a, str)][:8]
    return flow


def build_local_payload(payload: AIRequestPayload, metadata: Dict[str, Any], request_id: str,
                        local_tenant: str, model: str | None) -> Dict[str, Any]:
    history: List[Dict[str, str]] = [
        {"role": m.role, "content": m.content[:4000]}
        for m in payload.context[-MAX_HISTORY:] if m.role in ("user", "assistant")
    ]
    local_cfg = metadata.get("local_ai") if isinstance(metadata.get("local_ai"), dict) else {}
    business_context = local_cfg.get("business_context") if isinstance(local_cfg.get("business_context"), dict) else {}
    if len(str(business_context)) > MAX_BUSINESS_CONTEXT_BYTES:
        logger.warning("local_ai business_context too large tenant=%s; omitted", payload.tenant_id)
        business_context = {}
    options: Dict[str, Any] = {}
    if model:
        options["model"] = model
    return {
        "request_id": request_id,
        "tenant_id": local_tenant,
        "conversation_id": conversation_ref(payload),
        "message": payload.latest_text[:4000],
        "recent_history": history,
        "flow_context": build_flow_context(metadata),
        "business_context": business_context,
        "options": options,
    }


def usage_record(*, model: Any, input_tokens: Any, output_tokens: Any, stats: CallStats | None, status: str,
                 queue_ms: Any = None, level: str | None = None) -> Dict[str, Any]:
    return {
        "provider": "local",
        "model": model,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "cached_tokens": None,
        "latency_ms": stats.elapsed_ms if stats else None,
        "queue_ms": queue_ms,
        "status": status,
        "request_id": stats.request_id if stats else None,
        "attempts": stats.attempts if stats else 0,
        "level": level,
    }


async def generate_local(client: LocalAIClient, payload: AIRequestPayload, metadata: Dict[str, Any],
                         intent_name: str | None, intent_confidence: float | None,
                         model: str | None) -> AIResponsePayload:
    local_cfg = metadata.get("local_ai") if isinstance(metadata.get("local_ai"), dict) else {}
    local_tenant = str(local_cfg.get("tenant_key") or payload.tenant_id)
    request_id = safe_request_id(metadata.get("request_id") or metadata.get("message_id"))
    body = build_local_payload(payload, metadata, request_id, local_tenant, model)
    try:
        result, stats = await client.respond(local_tenant, request_id, body)
        if not str(result.get("text") or "").strip():
            raise LocalAIError("local_ai_empty_reply").with_stats(stats)
    except LocalAIError as exc:
        logger.warning(
            "local_ai_failed tenant=%s request_id=%s error=%s attempts=%s errors=%s",
            payload.tenant_id, request_id, exc.code, exc.stats.attempts if exc.stats else 0,
            exc.stats.errors if exc.stats else [],
        )
        return AIResponsePayload(
            handled=False,
            error=exc.code,
            retryable=exc.retryable,
            session_state=payload.session_state or {},
            metadata={
                "source": "local",
                "provider": "local",
                "request_id": request_id,
                "handoff_required": True,
                "ai_usage": usage_record(model=None, input_tokens=None, output_tokens=None, stats=exc.stats,
                                         status=exc.code),
            },
        )

    usage = result.get("usage") or {}
    timings = result.get("timings") or {}
    retrieval = result.get("retrieval") or {}
    level = result.get("level")
    actions = [a.get("type") for a in (result.get("actions") or []) if isinstance(a, dict)]
    record = usage_record(
        model=result.get("model") or ("local-deterministic" if level in ("deterministic", "handoff") else None),
        input_tokens=usage.get("prompt_tokens"), output_tokens=usage.get("completion_tokens"),
        stats=stats, status="ok", queue_ms=timings.get("queue_ms"), level=level,
    )
    logger.info(
        "local_ai_ok tenant=%s request_id=%s level=%s model=%s latency_ms=%s server_ms=%s queue_ms=%s "
        "retrieval_count=%s input_tokens=%s output_tokens=%s attempts=%s guard=%s",
        payload.tenant_id, request_id, level, record["model"], record["latency_ms"], result.get("latency_ms"),
        timings.get("queue_ms"), retrieval.get("documents_used"), record["input_tokens"],
        record["output_tokens"], stats.attempts, result.get("guard"),
    )
    return AIResponsePayload(
        handled=True,
        intent=intent_name,
        confidence=intent_confidence,
        reply=AIReply(content=str(result.get("text") or "").strip()),
        session_state=payload.session_state or {},
        metadata={
            "source": "local",
            "provider": "local",
            "tenant_id": payload.tenant_id,
            "request_id": request_id,
            "model_used": record["model"],
            "level": level,
            "guard": result.get("guard"),
            "retrieval_count": retrieval.get("documents_used"),
            "server_latency_ms": result.get("latency_ms"),
            "handoff_required": "handoff_required" in actions,
            "ai_usage": record,
        },
    )
