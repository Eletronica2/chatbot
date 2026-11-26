"""Campaign recipient status transitions (webhook ordering)."""
from __future__ import annotations

STATUS_RANK = {
    "invalid": -1,
    "pending": 0,
    "sending": 1,
    "sent": 2,
    "delivered": 3,
    "read": 4,
    "failed": 99,
}

WEBHOOK_STATUSES = frozenset({"sent", "delivered", "read", "failed"})


def should_promote(current: str, incoming: str) -> bool:
    cur = (current or "pending").lower()
    inc = (incoming or "").lower()
    if inc not in WEBHOOK_STATUSES:
        return False
    if inc == "failed":
        return cur not in {"read", "delivered"}
    if cur == "failed":
        return False
    return STATUS_RANK.get(inc, 0) > STATUS_RANK.get(cur, 0)