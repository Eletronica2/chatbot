"""Pure rules for template status updates (webhook vs Graph)."""
from __future__ import annotations

_TERMINAL = frozenset({"APPROVED", "REJECTED", "DELETED", "DISABLED"})


def normalize_status(value: str | None) -> str:
    return (value or "PENDING").strip().upper() or "PENDING"


def effective_status(
    *,
    graph_status: str | None,
    webhook_status: str | None,
    graph_synced_at: int | None,
    webhook_event_at: int | None,
) -> str:
    g_at = int(graph_synced_at or 0)
    w_at = int(webhook_event_at or 0)
    if g_at >= w_at:
        return normalize_status(graph_status or webhook_status)
    return normalize_status(webhook_status or graph_status)


def should_apply_webhook(
    *,
    stored_webhook_event_at: int | None,
    event_time: int,
    stored_effective: str | None,
    new_status: str,
) -> tuple[bool, str | None]:
    """Return (apply, skip_reason). Reject stale or regressive non-terminal downgrades."""
    stored_at = int(stored_webhook_event_at or 0)
    if event_time < stored_at:
        return False, "stale_event"
    prev = normalize_status(stored_effective)
    incoming = normalize_status(new_status)
    if event_time == stored_at and prev == incoming:
        return False, "duplicate"
    if prev in _TERMINAL and incoming not in _TERMINAL and incoming != prev:
        if event_time <= stored_at:
            return False, "regressive"
    return True, None