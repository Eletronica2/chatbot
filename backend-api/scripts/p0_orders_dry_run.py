"""End-to-end dry run of the 2026-10-27 P0 scenarios inside the backend container.

Real pieces: ConversationService, the deployed Flow Engine (HTTP) with the tenant's flow, the tenant catalog (read only)
and the order assistant. Fakes: sessions/messages in memory, an AI stub (no model call), and an order service that
never writes to MySQL. Nothing is sent to WhatsApp (this path returns actions; only the gateway sends).

    docker compose ... exec -T backend-api python -c "$(cat backend-api/scripts/p0_orders_dry_run.py)" pizzaria_bella_massa
"""
import asyncio
import sys
from datetime import datetime, timedelta
from types import SimpleNamespace
from uuid import uuid4

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.domain.execution_context import ExecutionContext
from app.domain.message import AIResponse, MessageType, NormalizedMessage
from app.domain.session import SessionMessage
from app.domain.tenant import TenantSettings
from app.repositories.session_repository import InMemorySessionRepository
from app.services.ai_service import IntentDetectionResult
from app.services.catalog_service import CatalogService
from app.services.conversation_service import ConversationService
from app.services.flow_service import FlowService
from app.services.order_assistant import OrderAssistant, claims_order_confirmation
from app.services.order_service import price_items
from app.services.session_service import SessionService

TENANT = sys.argv[1]
WITH_QWEN = "--qwen" in sys.argv
AI_CALLS: list[dict] = []
LEGACY_TEXTS = ("qual é o seu nome", "Pedido recebido", "Qual tamanho de pizza", "Como você vai pagar")
FAILURES: list[str] = []


class MemoryMessages:
    def __init__(self):
        self.items, self.ids = [], set()

    async def was_processed(self, *, tenant_id, external_message_id, direction):
        return (external_message_id, direction) in self.ids

    async def append(self, **kwargs):
        self.items.append(kwargs)
        if kwargs.get("external_message_id"):
            self.ids.add((kwargs["external_message_id"], kwargs["direction"]))


class SimulatedOrders:
    def __init__(self, catalog, fail=False):
        self.catalog, self.fail, self.created = catalog, fail, []

    async def create(self, tenant_key, **kwargs):
        if self.fail:
            raise RuntimeError("simulated database failure")
        for order in self.created:
            if order["key"] == kwargs["idempotency_key"]:
                return {**order, "created": False}
        priced = price_items(await self.catalog.list_products(tenant_key), kwargs["items"])
        order = {"id": len(self.created) + 1, "order_number": len(self.created) + 1, "created": True,
                 "total_cents": sum(p["line_total_cents"] for p in priced), "key": kwargs["idempotency_key"]}
        self.created.append(order)
        return order

    async def latest_for_customer(self, *args):
        return None


def build(orders_enabled: bool, fail: bool = False):
    catalog = CatalogService(MySQLDatabase(settings.DATABASE_URL))
    orders = SimulatedOrders(catalog, fail=fail)
    messages = MemoryMessages()

    async def get_or_create(tenant_id):
        return TenantSettings(tenant_id=tenant_id, orders_enabled=orders_enabled)

    async def detect_intent(**kwargs):
        return IntentDetectionResult(intent=None, confidence=0.0)

    async def generate_response(msg, ai_session, **kwargs):
        AI_CALLS.append({"messages": [m.get("content") for m in (ai_session.context or {}).get("messages") or []],
                         "collected": (msg.metadata or {}).get("collected_data") or {}})
        return AIResponse(reply_text="(IA simulada) resposta", handled=True, metadata={})

    async def nothing(*args, **kwargs):
        return None

    service = ConversationService(
        session_service=SessionService(InMemorySessionRepository()),
        flow_service=FlowService(settings.FLOW_ENGINE_URL, settings.FLOW_ENGINE_TIMEOUT),
        ai_service=SimpleNamespace(detect_intent=detect_intent, generate_response=generate_response),
        tenant_settings_service=SimpleNamespace(get_or_create=get_or_create),
        subscription_service=None,
        conversation_log_service=SimpleNamespace(append=nothing),
        message_service=messages,
        billing_gate=SimpleNamespace(enabled=True),
        order_assistant=OrderAssistant(catalog, orders),
    )
    service._record_ai_usage = nothing
    return service, orders


def message(text, phone, message_id=None):
    return NormalizedMessage(message_id=message_id or f"wamid.dry.{uuid4().hex}", tenant_id=TENANT,
                             phone_number=phone, phone_number_id="dry-run", display_phone_number="dry",
                             message_type=MessageType.TEXT, content=text, timestamp=datetime.utcnow())


async def say(service, phone, text, message_id=None):
    action = await service._handle_incoming_core(message(text, phone, message_id),
                                                 execution_context=ExecutionContext.production())
    state = (action.metadata or {}).get("state") or ""
    first = (action.reply_text or "").strip().splitlines()[0][:70] if action.reply_text else "(sem resposta)"
    print(f"    > {text!r:42} {action.source:18} {state:22} {first}")
    return action


def check(condition, label):
    print(f"  {'PASS' if condition else 'FAIL'} {label}")
    if not condition:
        FAILURES.append(label)


async def scenarios(orders_enabled: bool):
    mode = "ATIVADO" if orders_enabled else "DESATIVADO"
    print(f"\n=== Pedidos {mode} ===")
    service, orders = build(orders_enabled)
    phone = lambda: "550000" + uuid4().hex[:7]  # noqa: E731 - fictitious numbers, never sent

    print("  A) Boa noite -> Cardápio -> Tradicionais")
    p = phone()
    *_, last = [await say(service, p, t) for t in ["Boa noite", "Cardápio", "Tradicionais"]]
    check(last.metadata.get("state") == "pizzas_tradicionais" and "Calabresa" in last.reply_text, "A lista tradicionais")

    print("  B) Cardápio -> Quero ver as tradicionais")
    p = phone()
    *_, last = [await say(service, p, t) for t in ["Cardápio", "Quero ver as tradicionais"]]
    check(last.metadata.get("state") == "pizzas_tradicionais", "B lista tradicionais sem iniciar pedido")
    for text, state in [("Especiais", "pizzas_especiais"), ("Bebidas", "bebidas")]:
        p = phone()
        await say(service, p, "Cardápio")
        check((await say(service, p, text)).metadata.get("state") == state, f"B {text}")

    print("  C) Quanto custa a calabresa?")
    action = await say(service, phone(), "Quanto custa a calabresa?")
    check(action.source == "catalog_price" and "R$ 62,90" in action.reply_text, "C preço do cadastro")

    print("  Conversa real de 27/10 (fluxo legado)")
    p, replies = phone(), []
    for text in ["Boa noite", "Cardápio", "Tradicionais", "Quero ver as tradicionais", "Arthur", "Grande", "Calabresa",
                 "Só a pizza", "Vou retirar", "Vou retirar no local", "Cartão"]:
        replies.append((await say(service, p, text)).reply_text or "")
    check(not any(any(t in r for t in LEGACY_TEXTS) for r in replies), "nenhuma etapa/confirmação legada enviada")

    print("  D/E/F) Quero duas pizzas grandes de calabresa")
    p = phone()
    steps = ["Quero duas pizzas grandes de calabresa", "não", "retirada", "Teste"]
    actions = [await say(service, p, t) for t in steps]
    summary = actions[-1].reply_text or ""
    if orders_enabled:
        check("Confira seu pedido" in summary and "R$ 125,80" in summary, "D resumo com total, aguardando SIM")
        check(not orders.created, "E sem confirmação: nenhum pedido")
        session = await service.session_service.get_or_create_session(TENANT, p)
        draft = dict(session.context["order_draft"])
        draft["summary"] = {**draft["summary"], "at": (datetime.utcnow() - timedelta(minutes=20)).isoformat()}
        session.context["order_draft"] = draft
        await service.session_service.repository.save_session(session)
        stale = await say(service, p, "sim")
        check("Confira" in (stale.reply_text or "") and not orders.created, "E 'sim' após 20 min reapresenta resumo")
        confirm_id = f"wamid.dry.{uuid4().hex}"
        ok = await say(service, p, "sim", confirm_id)
        check("registrado" in (ok.reply_text or "") and len(orders.created) == 1, "F confirmação explícita = 1 pedido")
        dup = await say(service, p, "sim", confirm_id)
        check(dup.source == "duplicate" and len(orders.created) == 1, "G webhook repetido não duplica")
        again = await say(service, p, "sim")
        check(len(orders.created) == 1 and "registrado!" not in (again.reply_text or ""), "G 'sim' extra não cria")
        p2 = phone()
        for t in steps:
            await say(service, p2, t)
        both = await asyncio.gather(say(service, p2, "sim"), say(service, p2, "sim, confirmo"))
        check(len(orders.created) == 2 and sum("registrado!" in (a.reply_text or "") for a in both) == 1,
              "G mensagens simultâneas: 1 pedido, 1 confirmação")
        failing, failing_orders = build(True, fail=True)
        p3 = phone()
        for t in steps:
            await say(failing, p3, t)
        fail = await say(failing, p3, "sim")
        check("registrado" not in (fail.reply_text or "") and not failing_orders.created, "H falha não confirma")
    else:
        check(not any("Confira seu pedido" in (a.reply_text or "") for a in actions), "D sem módulo: nada de pedido")
        check(not any(t in (a.reply_text or "") for a in actions for t in LEGACY_TEXTS), "D sem fluxo legado")
        await say(service, p, "sim")
        check(not orders.created, "F/E sem módulo: nenhum pedido")


OLD_TURNS = [("user", "Vou retirar no local"), ("assistant", "Quase lá! Como você vai pagar?"), ("user", "Cartão"),
             ("assistant", "🎉 Pedido recebido com sucesso! Nossa equipe já vai conferir tudo")]
OLD_COLLECTED = {"payment_method": "cartao", "address": "vou retirar no local", "pizza_size": "grande",
                 "customer_name": "arthur", "delivery_type": "vou retirar", "drink": "so a pizza"}


async def age(service, phone, hours=1.0, legacy=False):
    """Simulate the stored conversation of the 27/10 test (legacy order turns) and/or a long silence."""
    session = await service.session_service.get_or_create_session(TENANT, phone)
    then = datetime.utcnow() - timedelta(hours=hours)
    if legacy:
        session.conversation_history = [SessionMessage(role=r, content=c, created_at=then) for r, c in OLD_TURNS]
        session.context = {**(session.context or {}), "messages": [
            {"role": r, "content": c, "created_at": then.isoformat(), "source": None} for r, c in OLD_TURNS]}
        session.conversation_state = {"current_state": "pedido_confirmacao", "last_state": "pedido_confirmacao",
                                      "collected_data": dict(OLD_COLLECTED)}
        session.current_state = "pedido_confirmacao"
    else:
        for turn in session.conversation_history:
            turn.created_at = then
        for item in (session.context or {}).get("messages") or []:
            item["created_at"] = then.isoformat()
    await service.session_service.repository.save_session(session)
    session.last_interaction = then


def clean_ai_input(call) -> bool:
    joined = " ".join(call["messages"])
    return not call["collected"] and "Cartão" not in joined and "Pedido recebido" not in joined


async def greeting_scenarios(orders_enabled: bool):
    print(f"\n=== Saudações (Pedidos {'ATIVADO' if orders_enabled else 'DESATIVADO'}) ===")
    service, orders = build(orders_enabled)
    phone = lambda: "550000" + uuid4().hex[:7]  # noqa: E731

    print("  Saudação após conversa antiga com pedido legado (estado 27/10)")
    p = phone()
    await say(service, p, "oi")
    await age(service, p, legacy=True)
    AI_CALLS.clear()
    action = await say(service, p, "Boa noite")
    check(not claims_order_confirmation(action.reply_text or "") and "pedido com" not in (action.reply_text or ""),
          "saudação sem pedido inventado")
    check(action.source == "flow" and action.metadata.get("resolution_reason") == "flow_start",
          "novo atendimento: saudação oficial do fluxo")
    check(all(clean_ai_input(c) for c in AI_CALLS), "IA não recebe histórico/dados antigos")
    session = await service.session_service.get_or_create_session(TENANT, p)
    check(not (session.conversation_state.get("collected_data") or {}), "dados legados descartados do estado")
    check(any("Pedido recebido" in m.content for m in session.conversation_history), "histórico preservado")

    print("  Mensagens consecutivas: Cardápio -> Tradicionais -> Boa noite")
    AI_CALLS.clear()
    for text in ["Cardápio", "Tradicionais", "Boa noite"]:
        action = await say(service, p, text)
    check(not claims_order_confirmation(action.reply_text or ""), "sem contaminação entre mensagens")
    check(all(clean_ai_input(c) for c in AI_CALLS), "IA só vê o atendimento atual")

    if orders_enabled:
        print("  Novo atendimento após pedido concluído")
        p = phone()
        for t in ["Quero duas pizzas grandes de calabresa", "não", "retirada", "Teste", "sim"]:
            await say(service, p, t)
        AI_CALLS.clear()
        same_episode = await say(service, p, "Boa noite")
        check(not claims_order_confirmation(same_episode.reply_text or ""), "mesmo atendimento: saudação limpa")
        check(all("registrado" not in " ".join(c["messages"]) for c in AI_CALLS), "IA não vê turnos do pedido")
        await age(service, p)
        new = await say(service, p, "Boa noite")
        check(new.metadata.get("state") == "boas_vindas" and not claims_order_confirmation(new.reply_text or ""),
              "novo atendimento começa na saudação")
        print("  Novo atendimento após pedido cancelado")
        p = phone()
        for t in ["Quero duas pizzas grandes de calabresa", "cancelar"]:
            await say(service, p, t)
        await age(service, p)
        new = await say(service, p, "Boa noite")
        check(new.metadata.get("state") == "boas_vindas" and not claims_order_confirmation(new.reply_text or ""),
              "após cancelamento começa na saudação")


async def qwen_dry_run():
    """Real Qwen3 (local AI via ai-engine): the 23:46 payload vs the corrected one. Nothing is sent to WhatsApp."""
    from app.domain.session import ConversationSession
    from app.services.ai_service import AIService

    print("\n=== Qwen3 dry-run (sem envio) ===")
    ai = AIService(settings.AI_ENGINE_URL, settings.AI_ENGINE_TIMEOUT)
    db = MySQLDatabase(settings.DATABASE_URL)
    from app.services.tenant_settings_service import TenantSettingsService
    overrides = (await TenantSettingsService(db).get_or_create(TENANT)).as_ai_metadata()
    then = datetime.utcnow() - timedelta(hours=1)
    old = [{"role": r, "content": c, "created_at": then.isoformat()} for r, c in OLD_TURNS]
    flow_meta = {"flow_state_message": "Oi! Bem-vindo à Pizzaria Bella Massa!", "resolution_reason": "fallback_ai"}
    cases = [
        ("antes (payload de 23:46)", old + [{"role": "user", "content": "Boa noite"}], dict(OLD_COLLECTED)),
        ("depois (corrigido)", [{"role": "user", "content": "Boa noite"}], {}),
    ]
    for label, messages, collected in cases:
        session = ConversationSession(tenant_id=TENANT, phone_number="5500000000999", context={"messages": messages})
        msg = message("Boa noite", "5500000000999")
        msg = msg.model_copy(update={"metadata": {**flow_meta, "collected_data": collected}})
        reply = await ai.generate_response(msg, session, metadata_overrides=overrides)
        text = (reply.reply_text or "").replace("\n", " ")
        print(f"  {label}: handled={reply.handled} -> {text[:160]!r}")
        if label.startswith("depois"):
            check(reply.handled and not claims_order_confirmation(text) and "pedido" not in text.lower(),
                  "Qwen3 saudação corrigida sem pedido")


async def main():
    if "--qwen-only" in sys.argv:
        await qwen_dry_run()
        print(f"\nRESULT: {'ALL PASS' if not FAILURES else 'FAILURES: ' + '; '.join(FAILURES)}")
        return
    await scenarios(False)
    await scenarios(True)
    await greeting_scenarios(False)
    await greeting_scenarios(True)
    if WITH_QWEN:
        await qwen_dry_run()
    print(f"\nRESULT: {'ALL PASS' if not FAILURES else 'FAILURES: ' + '; '.join(FAILURES)}")


asyncio.run(main())
