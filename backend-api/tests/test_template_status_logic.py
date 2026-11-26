"""Unit tests for WhatsApp template status merge rules."""
from app.services.template_status_logic import effective_status, should_apply_webhook


def test_effective_status_prefers_newer_graph():
    assert (
        effective_status(
            graph_status="APPROVED",
            webhook_status="PENDING",
            graph_synced_at=200,
            webhook_event_at=100,
        )
        == "APPROVED"
    )


def test_effective_status_prefers_newer_webhook():
    assert (
        effective_status(
            graph_status="PENDING",
            webhook_status="APPROVED",
            graph_synced_at=100,
            webhook_event_at=200,
        )
        == "APPROVED"
    )


def test_webhook_idempotent_same_event():
    apply, reason = should_apply_webhook(
        stored_webhook_event_at=100,
        event_time=100,
        stored_effective="APPROVED",
        new_status="APPROVED",
    )
    assert apply is False
    assert reason == "duplicate"


def test_webhook_rejects_stale():
    apply, reason = should_apply_webhook(
        stored_webhook_event_at=500,
        event_time=400,
        stored_effective="APPROVED",
        new_status="PENDING",
    )
    assert apply is False
    assert reason == "stale_event"