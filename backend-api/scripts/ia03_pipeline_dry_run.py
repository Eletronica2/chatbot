"""Dry-run of the production conversation pipeline for Bella Massa: real Flow Engine + real AI Engine (local Qwen3),
same metadata and reply composition as ConversationService, but session kept in memory.

Nothing is persisted, no billing reservation is made and nothing is sent to WhatsApp.
Run inside the backend-api container:  python - < scripts/ia03_pipeline_dry_run.py
"""
import asyncio
import time
from datetime import datetime

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.domain.message import MessageDirection, MessageType, NormalizedMessage
from app.domain.session import ConversationSession
from app.services.ai_service import AIService
from app.services.conversation_service import ConversationService
from app.services.flow_service import FlowService
from app.services.tenant_settings_service import TenantSettingsService

TENANT = "pizzaria_bella_massa"
CONVERSATION = ["Boa noite", "Quanto custa a pizza de calabresa grande?", "Vocês oferecem Wi-Fi?",
                "Tem pizza grande?", "De calabresa", "Quanto custa?"]


def message(text: str, n: int) -> NormalizedMessage:
    return NormalizedMessage(
        message_id=f"dryrun-ia03-{int(time.time())}-{n}", tenant_id=TENANT, phone_number="dry-run",
        phone_number_id="dry-run", display_phone_number="dry-run", message_type=MessageType.TEXT,
        direction=MessageDirection.INCOMING, content=text, timestamp=datetime.utcnow(), metadata={"source": "dry_run"},
    )


async def main() -> None:
    tenant_settings = await TenantSettingsService(MySQLDatabase(settings.DATABASE_URL)).get_or_create(TENANT)
    ai_meta = tenant_settings.as_ai_metadata()
    print("tenant settings:", {"ai_provider_sent": ai_meta["ai_provider"], "auto_reply_mode": tenant_settings.auto_reply_mode})
    flows = FlowService(settings.FLOW_ENGINE_URL, settings.FLOW_ENGINE_TIMEOUT)
    ai = AIService(settings.AI_ENGINE_URL, settings.AI_ENGINE_TIMEOUT)
    session = ConversationSession(tenant_id=TENANT, phone_number="dry-run")
    for n, text in enumerate(CONVERSATION, 1):
        started = time.monotonic()
        msg = message(text, n)
        session.append_history(role="user", content=text, limit=10)
        session.context = {"messages": [{"role": h.role, "content": h.content} for h in session.conversation_history]}
        flow = await flows.execute_flow(msg, session)
        meta = flow.metadata or {}
        if flow.requires_ai_fallback:
            ai_msg = msg.model_copy(update={"metadata": {**(msg.metadata or {}), "flow_state_message": meta.get("flow_state_message"),
                                                         "options": meta.get("options"), "collected_data": flow.collected_data,
                                                         "resolution_reason": "fallback_ai"}})
            result = await ai.generate_response(ai_msg, session, metadata_overrides=ai_meta)
            usage = (result.metadata or {}).get("ai_usage") or {}
            if result.handled:
                reply = ConversationService._compose_ai_fallback_reply(result.reply_text, meta.get("flow_state_message"))
                path = f"flow({meta.get('state')}) -> AI fallback"
            else:
                reply, path = "", f"AI falhou -> humano ({(result.metadata or {}).get('error')})"
            detail = (f"provider={usage.get('provider')} model={usage.get('model')} tokens_in={usage.get('input_tokens')} "
                      f"tokens_out={usage.get('output_tokens')} ai_latency_ms={usage.get('latency_ms')} level={(result.metadata or {}).get('level')} "
                      f"guard={(result.metadata or {}).get('guard')}")
        else:
            reply, path, detail = flow.reply_text or "", f"flow({meta.get('state')}) determinístico", "sem IA"
        session.conversation_state = flow.session_state or session.conversation_state
        session.current_state = meta.get("state") or session.current_state
        session.active_flow = meta.get("flow") or session.active_flow
        session.append_history(role="assistant", content=reply, limit=10) if reply else None
        print(f"\n[{n}] cliente: {text}\n    caminho: {path} | {detail} | total_ms={int((time.monotonic() - started) * 1000)}")
        print("    resposta: " + (reply.replace("\n", " ⏎ ")[:420] or "(nenhuma — handoff humano)"))


asyncio.run(main())
