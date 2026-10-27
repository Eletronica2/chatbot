import json
import logging
import sys
from datetime import datetime, timezone

_logger = logging.getLogger("atende_ai_local")

# Never log message bodies, documents, prompts or credentials.
_ALLOWED = {
    "request_id", "tenant_id", "key_id", "status", "error_code", "reason", "level", "model", "latency_ms",
    "prompt_tokens", "completion_tokens", "retrieval_count", "queue_ms", "guard", "documents", "chunks",
    "chunks_removed", "mode", "detail", "path", "method", "provider", "deadline_ms", "results", "cached",
    "generation_ms", "retrieval_ms", "auth", "prompt_eval_ms", "eval_ms", "load_ms", "first_token_ms",
    "fallback_reason",
}


def setup_logging(level: str) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter("%(message)s"))
    _logger.handlers = [handler]
    _logger.setLevel(level)
    _logger.propagate = False


def log_event(event: str, **fields) -> None:
    record = {"ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"), "event": event}
    record.update({k: v for k, v in fields.items() if k in _ALLOWED and v is not None})
    _logger.info(json.dumps(record, ensure_ascii=False))
