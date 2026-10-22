import asyncio
from datetime import datetime
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.api.routes.tenant_settings import (
    TenantSettingsPatchPayload,
    TenantSettingsResponse,
    assert_tenant_settings_patch_access,
)
from app.domain.execution_context import ExecutionContext
from app.domain.message import ConversationAction, MessageType, NormalizedMessage
from app.domain.tenant import TenantSettings
from app.services.conversation_service import ConversationService

SENDER = "5547999990000"


def _run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


def _settings(mode: str, allowlist=None) -> TenantSettings:
    return TenantSettings(tenant_id="pizzaria_bella_massa", auto_reply_mode=mode, auto_reply_allowlist=allowlist or [])


def test_default_mode_keeps_automatic_replies():
    assert TenantSettings(tenant_id="t").auto_reply_block_reason(SENDER) is None


def test_off_blocks_everyone():
    assert _settings("off").auto_reply_block_reason(SENDER) == "auto_reply_disabled"


@pytest.mark.parametrize("sender", [SENDER, "+55 47 99999-0000", "55 (47) 99999 0000"])
def test_allowlist_accepts_only_listed_sender_in_any_format(sender):
    assert _settings("allowlist", [SENDER]).auto_reply_block_reason(sender) is None


@pytest.mark.parametrize("sender", ["5547999991111", "", None])
def test_allowlist_rejects_other_senders(sender):
    assert _settings("allowlist", [SENDER]).auto_reply_block_reason(sender) == "auto_reply_sender_not_allowed"


PILOT = "5534992665547"


@pytest.mark.parametrize("sender", ["+5534992665547", "5534992665547", "553492665547", "+55 (34) 99266-5547"])
def test_pilot_sender_matches_in_every_meta_and_e164_form(sender):
    assert _settings("allowlist", ["+5534992665547"]).auto_reply_block_reason(sender) is None


@pytest.mark.parametrize("sender", [
    "5534999999999",          # another number
    "",                       # empty
    None,
    "abc",                    # malformed
    "992665547",              # suffix only
    "553499266554",           # truncated
    "55349926655470",         # extra digit
    "5547",                   # last digits only
    "*",                      # wildcard
])
def test_pilot_allowlist_rejects_everything_else(sender):
    assert _settings("allowlist", [PILOT]).auto_reply_block_reason(sender) == "auto_reply_sender_not_allowed"


def test_wildcard_or_partial_entries_never_authorize():
    settings = _settings("allowlist", ["*", "5547", ""])
    assert settings.auto_reply_block_reason(PILOT) == "auto_reply_sender_not_allowed"


def test_bella_allowlist_does_not_authorize_another_tenant():
    recorder_bella = _settings("allowlist", [PILOT])
    other_tenant = TenantSettings(tenant_id="teste_empresa", auto_reply_mode="allowlist", auto_reply_allowlist=[])
    assert recorder_bella.auto_reply_block_reason(PILOT) is None
    assert other_tenant.auto_reply_block_reason(PILOT) == "auto_reply_sender_not_allowed"


def test_gate_reads_settings_of_the_message_tenant_only():
    seen = []
    recorder = _Recorder(_settings("allowlist", [PILOT]))

    async def get_or_create(tenant_id):
        seen.append(tenant_id)
        return recorder.settings

    recorder.get_or_create = get_or_create
    service = _service(recorder)
    service.billing_gate = SimpleNamespace(enabled=False)
    action = _run(service.handle_incoming_message(_message(PILOT), execution_context=ExecutionContext.production()))
    assert seen == ["pizzaria_bella_massa"] and action.reply_text == "Olá!"


def test_empty_allowlist_blocks_everyone_and_unknown_mode_fails_closed():
    assert _settings("allowlist").auto_reply_block_reason(SENDER) == "auto_reply_sender_not_allowed"
    assert _settings("bogus").auto_reply_block_reason(SENDER) == "auto_reply_disabled"


def test_settings_response_never_exposes_allowlisted_numbers():
    body = TenantSettingsResponse.from_domain(_settings("allowlist", [SENDER])).model_dump()
    assert body["auto_reply_mode"] == "allowlist"
    assert body["auto_reply_allowlist_count"] == 1
    assert SENDER not in str(body)


@pytest.mark.parametrize("payload", [
    TenantSettingsPatchPayload(auto_reply_mode="on"),
    TenantSettingsPatchPayload(auto_reply_allowlist=[SENDER]),
])
def test_only_superadmin_changes_auto_reply(payload):
    owner = SimpleNamespace(role="owner", tenant_id="pizzaria_bella_massa")
    with pytest.raises(HTTPException) as exc:
        assert_tenant_settings_patch_access(owner, payload)
    assert exc.value.status_code == 403
    assert_tenant_settings_patch_access(SimpleNamespace(role="superadmin", tenant_id="default"), payload)


class _Recorder:
    def __init__(self, settings: TenantSettings, processed: bool = False):
        self.settings = settings
        self.processed = processed
        self.persisted = []
        self.session_updates = []

    async def get_or_create(self, tenant_id):
        return self.settings

    async def was_processed(self, **kwargs):
        return self.processed


def _service(recorder: _Recorder) -> ConversationService:
    service = ConversationService.__new__(ConversationService)
    service.tenant_settings_service = recorder
    service.message_service = recorder
    service.billing_gate = SimpleNamespace(enabled=True, preflight=_forbidden, reserve=_forbidden)
    session = SimpleNamespace(session_id="s1", context={}, conversation_state={})

    async def resolve_session(message, ctx):
        return session

    async def persist_message(ctx, **kwargs):
        recorder.persisted.append(kwargs)

    async def persist_session_update(ctx, current, **kwargs):
        recorder.session_updates.append(kwargs)
        return current

    async def core(message, *, execution_context=None):
        return ConversationAction(source="flow", reply_text="Olá!", tenant_id=message.tenant_id,
                                  phone_number=message.phone_number)

    service._resolve_session = resolve_session
    service._persist_message = persist_message
    service._persist_session_update = persist_session_update
    service._append_message = lambda *a, **k: None
    service._handle_incoming_core = core
    return service


def _forbidden(*args, **kwargs):
    raise AssertionError("billing must not be touched when auto reply is blocked")


def _message(sender: str = SENDER) -> NormalizedMessage:
    return NormalizedMessage(
        message_id="wamid.test", tenant_id="pizzaria_bella_massa", phone_number=sender,
        phone_number_id="pnid", display_phone_number="5500000000", message_type=MessageType.TEXT,
        content="oi, vcs tem wi-fi?", timestamp=datetime.utcnow(),
    )


def test_blocked_inbound_is_stored_for_a_human_and_nothing_is_sent_or_billed():
    recorder = _Recorder(_settings("off"))
    action = _run(_service(recorder).handle_incoming_message(_message(), execution_context=ExecutionContext.production()))
    assert action.reply_text == ""
    assert action.source == "auto_reply_disabled"
    assert action.requires_handoff is True
    assert recorder.persisted[0]["direction"] == "incoming"
    assert recorder.persisted[0]["metadata"]["auto_reply_blocked"] == "auto_reply_disabled"
    context = recorder.session_updates[0]["context_updates"]
    assert context["human_handoff_pending"] is True and context["unread_count"] == 1


def test_blocked_duplicate_is_not_stored_twice():
    recorder = _Recorder(_settings("off"), processed=True)
    action = _run(_service(recorder).handle_incoming_message(_message(), execution_context=ExecutionContext.production()))
    assert action.source == "duplicate" and recorder.persisted == []


def test_allowlisted_sender_reaches_the_normal_pipeline():
    recorder = _Recorder(_settings("allowlist", [SENDER]))
    service = _service(recorder)
    service.billing_gate = SimpleNamespace(enabled=False)
    action = _run(service.handle_incoming_message(_message(), execution_context=ExecutionContext.production()))
    assert action.reply_text == "Olá!"


def _core_service(session, processed=False):
    recorder = _Recorder(_settings("allowlist", [PILOT]), processed=processed)
    service = _service(recorder)
    del service._handle_incoming_core
    service.billing_gate = SimpleNamespace(enabled=True)

    async def resolve_session(message, ctx):
        return session

    async def same(current):
        return current

    async def no_ai(*args, **kwargs):
        raise AssertionError("AI/flow must not run")

    service._resolve_session = resolve_session
    service._ensure_operational_defaults = same
    service.ai_service = SimpleNamespace(detect_intent=no_ai, generate_response=no_ai)
    service.flow_service = SimpleNamespace(execute_flow=no_ai)
    return service, recorder


def test_allowlisted_sender_in_human_owned_conversation_gets_no_automatic_reply():
    session = SimpleNamespace(session_id="s1", context={}, conversation_state={}, assignment_mode="human",
                              assigned_user_id="3")
    service, recorder = _core_service(session)
    action = _run(service._handle_incoming_core(_message(PILOT), execution_context=ExecutionContext.production()))
    assert action.source == "human_owned" and action.reply_text == "" and recorder.persisted


def test_duplicate_webhook_for_allowlisted_sender_is_not_processed_twice():
    session = SimpleNamespace(session_id="s1", context={}, conversation_state={}, assignment_mode="ai")
    service, recorder = _core_service(session, processed=True)
    action = _run(service._handle_incoming_core(_message(PILOT), execution_context=ExecutionContext.production()))
    assert action.source == "duplicate" and action.reply_text == "" and recorder.persisted == []


def test_simulation_is_not_blocked_so_flows_can_be_validated():
    recorder = _Recorder(_settings("off"))
    service = _service(recorder)
    service.billing_gate = SimpleNamespace(enabled=False)
    action = _run(service.handle_incoming_message(_message(), execution_context=ExecutionContext.dry_run()))
    assert action.reply_text == "Olá!" and recorder.persisted == []
