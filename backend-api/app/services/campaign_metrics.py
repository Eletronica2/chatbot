"""Apresentação dos contadores de campanha (status atual é exclusivo no banco)."""
from __future__ import annotations


def presentation_counts(
    *,
    pending: int = 0,
    sent: int = 0,
    delivered: int = 0,
    read: int = 0,
    failed: int = 0,
    uncertain: int = 0,
) -> dict[str, int | float | None]:
    accepted = max(0, sent) + max(0, delivered) + max(0, read) + max(0, failed) + max(0, uncertain)
    delivered_ok = max(0, delivered) + max(0, read)
    known = delivered_ok + max(0, failed) + max(0, uncertain)
    rate = (delivered_ok / known * 100) if known else None
    return {
        "pending": max(0, pending),
        "sent": accepted,
        "delivered": delivered_ok,
        "read": max(0, read),
        "failed": max(0, failed),
        "uncertain": max(0, uncertain),
        "delivery_rate": rate,
    }
