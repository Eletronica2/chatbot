"""Unit tests for product hardening (no live MySQL required)."""
from __future__ import annotations

from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException

from app.api.access import assert_capability, capabilities_for
from app.domain.auth import AuthenticatedUser
from app.domain.execution_context import ExecutionContext, ExecutionMode
from app.services.quick_reply_service import normalize_shortcut
from app.services.subscription_service import PLAN_LIMITS
from app.services.usage_ledger_service import UsageLedgerService


def _user(role: str) -> AuthenticatedUser:
    return AuthenticatedUser(
        user_id="user-1",
        tenant_id="tenant-demo",
        email="user@example.com",
        display_name="User Demo",
        role=role,
    )


def test_dry_run_execution_context_flags():
    ctx = ExecutionContext.dry_run()
    assert ctx.mode == ExecutionMode.TEST
    assert ctx.persist is False
    assert ctx.allow_external_side_effects is False
    assert ctx.allow_billing is False
    assert ctx.is_test is True

    prod = ExecutionContext.production()
    assert prod.mode == ExecutionMode.NORMAL
    assert prod.persist is True
    assert prod.allow_billing is True
    assert prod.is_test is False


def test_human_owned_helper():
    from app.domain.session import ConversationSession
    from app.services.conversation_service import ConversationService

    ai = ConversationSession(tenant_id="t", phone_number="1", assignment_mode="ai")
    human = ConversationSession(
        tenant_id="t",
        phone_number="1",
        assignment_mode="human",
        assigned_user_id="u1",
    )
    assert ConversationService._is_human_owned(ai) is False
    assert ConversationService._is_human_owned(human) is True


def test_rbac_agent_vs_admin_capabilities():
    agent = capabilities_for(_user("agent"))
    admin = capabilities_for(_user("owner"))

    assert agent["canViewConversations"] is True
    assert agent["canManageAutomations"] is False
    assert agent["canManageActions"] is False
    assert agent["canManageTemplates"] is False
    assert agent["canManageGroups"] is False
    assert agent["canManageQuickReplies"] is True

    assert admin["canManageAutomations"] is True
    assert admin["canManageActions"] is True
    assert admin["canManageTemplates"] is True
    assert admin["canManageGroups"] is True

    with pytest.raises(HTTPException) as err:
        assert_capability(_user("agent"), "canManageAutomations")
    assert err.value.status_code == 403

    assert_capability(_user("owner"), "canManageAutomations")
    assert_capability(_user("superadmin"), "canManageTemplates")


def test_subscription_on_demand_in_plan_limits():
    assert "on_demand" in PLAN_LIMITS
    assert PLAN_LIMITS["on_demand"] == 0
    # 0 means unlimited allowance (billing via usage events separately)
    assert PLAN_LIMITS["starter"] > 0


def test_normalize_shortcut_prefix():
    assert normalize_shortcut("oi") == "/oi"
    assert normalize_shortcut("/ajuda") == "/ajuda"


def test_usage_events_unique_logic_with_mock_db():
    import asyncio

    database = MagicMock()
    database.resolve_tenant_pk.return_value = 42

    # First call: no existing row → insert → created True
    database.fetch_one.return_value = None
    database.execute.return_value = None
    service = UsageLedgerService(database)

    first = asyncio.get_event_loop().run_until_complete(
        service.record_delivered("tenant-demo", "wamid.ABC", category="UTILITY")
    )
    assert first["created"] is True
    assert first["provider_message_id"] == "wamid.ABC"
    assert database.execute.call_count == 1

    # Second call: existing UNIQUE row → created False
    database.fetch_one.return_value = {
        "id": first["id"],
        "provider_message_id": "wamid.ABC",
        "category": "UTILITY",
        "market": "BR",
        "event_type": "delivered",
        "quantity": 1,
        "delivered_at": None,
        "billing_period": first["billing_period"],
        "stripe_status": "pending",
        "created_at": None,
    }
    second = asyncio.get_event_loop().run_until_complete(
        service.record_delivered("tenant-demo", "wamid.ABC", category="UTILITY")
    )
    assert second["created"] is False
    # No additional insert
    assert database.execute.call_count == 1
