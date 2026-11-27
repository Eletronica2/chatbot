"""Apresentação dos contadores de campanha (status atual é exclusivo no banco)."""
from __future__ import annotations


def recipient_accepted_by_meta(row: dict) -> bool:
    """Aceite exige status de envio ou, em falha/incerteza, wamid, sent_at ou evento sent/delivered/read."""
    status = str(row.get("status") or "").strip().lower()
    if status in {"sent", "delivered", "read"}:
        return True
    if status not in {"failed", "uncertain"}:
        return False
    if str(row.get("provider_message_id") or "").strip():
        return True
    if row.get("sent_at"):
        return True
    events = row.get("accepted_events") or ()
    return any(str(item).strip().lower() in {"sent", "delivered", "read"} for item in events)


def presentation_counts(
    *,
    pending: int = 0,
    sent: int = 0,
    delivered: int = 0,
    read: int = 0,
    failed: int = 0,
    uncertain: int = 0,
    failed_accepted: int = 0,
    uncertain_accepted: int = 0,
) -> dict[str, int | float | None]:
    accepted = (
        max(0, sent)
        + max(0, delivered)
        + max(0, read)
        + max(0, failed_accepted)
        + max(0, uncertain_accepted)
    )
    delivered_ok = max(0, delivered) + max(0, read)
    rate = (delivered_ok / accepted * 100) if accepted else None
    return {
        "pending": max(0, pending),
        "sent": accepted,
        "delivered": delivered_ok,
        "read": max(0, read),
        "failed": max(0, failed),
        "uncertain": max(0, uncertain),
        "delivery_rate": rate,
    }
