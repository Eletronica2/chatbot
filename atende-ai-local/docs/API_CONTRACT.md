# API Contract — Atende Ai Local AI API v0.1.0

Base: `http://127.0.0.1:8100` (IA-02: exposta somente via WireGuard). Autenticação: `Authorization: Bearer <token>`.

## GET /health
Liveness. `200 {"status":"ok"}`. Não verifica dependências.

## GET /ready
Readiness: FastAPI, Qdrant (coleção existe), Ollama (responde), modelo configurado presente, embedding carregado
e sonda de inferência de 1–2 tokens **em cache por 10 min** (não roda inferência pesada a cada chamada).
`200` quando tudo ok; `503` com o detalhe de cada check quando algo falha.

## POST /v1/respond  (escopo `respond`)

Request:
```json
{
  "request_id": "uuid",
  "tenant_id": "pizzaria_bella_massa",
  "conversation_id": "uuid",
  "message": "Quanto custa a pizza grande?",
  "recent_history": [{"role": "user|assistant", "content": "..."}],
  "flow_context": {"step": "menu", "conversation_summary": "..."},
  "business_context": {
    "business_name": "...",
    "products": [{"name": "Pizza Calabresa Grande", "price": 65.0, "available": true, "aliases": []}],
    "hours": [{"days": "terça a quinta", "open": "18h", "close": "23h"}],
    "delivery": {"neighborhoods": [{"name": "Centro", "fee": 5.0}], "not_served": ["Zona Rural"]},
    "payment_methods": ["PIX", "dinheiro"],
    "promotions": [{"title": "...", "price": 30.0}]
  },
  "options": {"model": null, "max_tokens": null, "temperature": null, "num_ctx": null,
              "retrieval_mode": null, "allow_deterministic": true}
}
```
`tenant_id` é validado contra a credencial (ver MULTITENANCY.md). `options.model` só aceita modelos de
`ALLOWED_MODELS`.

Response 200:
```json
{
  "request_id": "uuid",
  "tenant_id": "pizzaria_bella_massa",
  "text": "Pizza Calabresa Grande custa R$ 65,00.",
  "language": "pt-BR",
  "model": "qwen3:4b-instruct-2507-q4_K_M | null (determinístico/handoff)",
  "level": "deterministic | rag | llm | handoff | fallback",
  "usage": {"prompt_tokens": 0, "completion_tokens": 0},
  "latency_ms": 0,
  "timings": {"queue_ms": 0, "retrieval_ms": 0, "load_ms": 0, "first_token_ms": null,
              "generation_ms": 0, "tokens_per_s": null},
  "retrieval": {"documents_used": 0, "mode": "hybrid", "chunks": [{"chunk_id": "...", "document_id": "...",
                "section": "...", "score": 0.0}]},
  "actions": [{"type": "handoff_required", "reason": "order_create"}],
  "guard": null
}
```
`usage` e `timings` vêm dos contadores reais do Ollama (`prompt_eval_count`, `eval_count`, durações) e do relógio
da API; respostas determinísticas/handoff têm usage 0 porque não chamam o LLM. `documents_used` = chunks usados.

Erros: `401 credential_missing|credential_invalid`, `403 scope_forbidden|tenant_forbidden|tenant_scope`,
`400 tenant_required|tenant_invalid|model_not_allowed`, `404 tenant_unknown`, `422 invalid_request`,
`502 inference_error`, `503 saturated` (+ `Retry-After`, `retry_after_s`, snapshot da fila).

## POST /v1/knowledge/upsert  (escopo `knowledge:write`)
```json
{"tenant_id": "opcional", "documents": [{"document_id": "cardapio", "title": "Cardápio", "content": "# ...",
  "source": "painel", "document_version": null, "content_type": "markdown|text"}]}
```
→ `{"tenant_id": "...", "results": [{"document_id", "document_version", "previous_version", "chunks",
"stale_chunks_removed"}]}`

## POST /v1/knowledge/delete  (escopo `knowledge:write`)
`{"tenant_id": "opcional", "document_ids": ["cardapio"]}` → `{"tenant_id": "...", "chunks_removed": N}`

## POST /v1/knowledge/search  (escopo `knowledge:read`)
`{"tenant_id": "opcional", "query": "...", "top_k": 4, "mode": "dense|hybrid"}` →
`{"tenant_id", "mode", "latency_ms", "results": [{"score", "tenant_id", "document_id", "document_version",
"section", "chunk_id", "text", "source"}]}`

## GET /v1/status
Snapshot da fila (`active`, `waiting`, `max_queue`, `rejected_total`) e modelo de embedding. Sem dados de tenant.
