"""Operational inbox visibility: hide closed / expired threads until the customer writes again."""
from __future__ import annotations

from datetime import datetime, timedelta

SERVICE_WINDOW = timedelta(hours=24)


def touch_inbound_customer(context: dict | None) -> dict:
    """Customer message reopens the inbox and records activity time."""
    ctx = dict(context or {})
    ctx["last_customer_message_at"] = datetime.utcnow().isoformat()
    for key in ("inbox_hidden", "inbox_hidden_at", "inbox_hidden_reason"):
        ctx.pop(key, None)
    return ctx


def hide_from_inbox(context: dict | None, *, reason: str) -> dict:
    ctx = dict(context or {})
    ctx["inbox_hidden"] = True
    ctx["inbox_hidden_at"] = datetime.utcnow().isoformat()
    ctx["inbox_hidden_reason"] = reason
    ctx["unread_count"] = 0
    ctx.pop("human_handoff_pending", None)
    ctx.pop("human_handoff_reason", None)
    ctx.pop("human_handoff_at", None)
    return ctx


def _parse_dt(value: object) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    raw = str(value).strip()
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00")).replace(tzinfo=None)
    except ValueError:
        return None


def customer_last_message_at(context: dict | None) -> datetime | None:
    return _parse_dt((context or {}).get("last_customer_message_at"))


def outside_service_window(last_customer_at: datetime | None, *, now: datetime | None = None) -> bool:
    if last_customer_at is None:
        return False
    now = now or datetime.utcnow()
    return now - last_customer_at > SERVICE_WINDOW