"""WhatsApp order assistant: catalog-grounded slot filling with explicit confirmation.

The assistant never writes orders itself: on an explicit "SIM" it calls ``OrderService.create`` (prices recomputed
from the catalog, idempotent per draft). The draft lives in ``session.context["order_draft"]``.
"""
from __future__ import annotations

import hashlib
import json
import logging
import re
import unicodedata
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

from app.domain import orders as order_domain
from app.services.order_service import OrderError, price_items

logger = logging.getLogger(__name__)

DRAFT_TTL = timedelta(hours=2)
# A "SIM" only confirms the summary the customer saw recently; older summaries are shown again first.
CONFIRM_TTL = timedelta(minutes=15)
START_ACTION = "start_order"

_STOP = {"de", "da", "do", "das", "dos", "com", "c", "e", "a", "o", "as", "os", "um", "uma", "pizza", "pizzas",
         "quero", "queria", "pra", "para", "por", "favor", "mais", "sem", "no", "na", "em", "meu", "minha", "ml"}
_SEPARATORS = {"e", "mais", ",", "+", ";", "tambem"}
_NUMBER_WORDS = {"um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6,
                 "sete": 7, "oito": 8, "nove": 9, "dez": 10}
_START_PHRASES = re.compile(
    r"\b(fazer (um |o )?pedido|novo pedido|quero (fazer )?(um )?pedi(r|do)|queria pedir|gostaria de pedir|"
    r"quero encomendar|vou pedir)\b"
)
_BUY_VERBS = re.compile(r"\b(quero|queria|gostaria|vou querer|manda|me ve|me da|pode mandar|pedir|pedido)\b")
_BROWSE = re.compile(r"\b(ver|veja|mostra|mostrar|mostre|conhecer|saber|olhar|cardapio|menu|opcoes|sabores)\b")
_PRICE_QUESTION = re.compile(r"\b(quanto (custa|e|sai|fica|ta|esta)|qual (o|e o) (preco|valor)|preco d|valor d|precos? )")
_ORDER_CLAIM = re.compile(
    r"(\bpedido\b.{0,40}\b(recebido|confirmado|registrado|anotado|finalizado|realizado)\b"
    r"|\b(recebemos|registramos|confirmamos|anotamos|anotei|registrei|confirmei) (o |seu |o seu )?pedido\b)"
)
_STATUS_QUERY = re.compile(r"\b(meu pedido|status do pedido|cade (o )?(meu )?pedido|andamento do pedido|"
                           r"pedido (#|n|numero )?\s*\d+)\b")
_YES = re.compile(r"(sim|confirmo|confirmar|confirma|confirmado|pode confirmar|ok confirmo|ok pode confirmar)"
                  r"( (confirmo|confirma|pode confirmar|pode|por favor|esta certo|ta certo|certo|isso))?")
_NO = {"nao", "n", "nao quero", "nao obrigado", "agora nao"}
_NOTHING_MORE = re.compile(r"^(nao|n|so isso|e so|so|nada|nada mais|mais nada|por enquanto e so|"
                           r"nao obrigad[oa]|ta bom|pronto|acabou|e isso)\b")
_CANCEL = re.compile(r"\b(cancelar|cancela|cancele|desisto|desistir|deixa pra la|esquece)\b")
_HANDOFF = re.compile(r"\b(atendente|humano|pessoa|falar com alguem)\b")
_DELIVERY = re.compile(r"\b(entrega|entregar|delivery|em casa|receber)\b")
_PICKUP = re.compile(r"\b(retirada|retirar|retiro|buscar|busco|balcao|pegar ai|vou ai)\b")


def normalize(text: str) -> str:
    value = unicodedata.normalize("NFKD", str(text or "").lower())
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    value = re.sub(r"\b(2|dois)\s*(l|lt|litro|litros)\b", "2l", value)
    value = re.sub(r"([,;+])", r" \1 ", value)
    value = re.sub(r"[^a-z0-9,;+#]+", " ", value)
    return " ".join(value.split())


def _tokens(text: str) -> List[str]:
    return normalize(text).split()


def _stem(token: str) -> str:
    return token[:-1] if len(token) > 3 and token.endswith("s") else token


def _significant(name: str) -> List[str]:
    return [_stem(t) for t in _tokens(name) if t not in _STOP and t not in {",", ";", "+"} and (len(t) >= 3 or t.isdigit() or t == "2l")]


def _quantity(token: str) -> Optional[int]:
    if token.isdigit():
        value = int(token)
        return value if 1 <= value <= 50 else None
    return _NUMBER_WORDS.get(token)


@dataclass
class ParsedItem:
    product: Dict[str, Any]
    quantity: int
    variant_name: Optional[str]


@dataclass
class AssistantResult:
    reply: str
    draft: Optional[Dict[str, Any]]
    order: Optional[Dict[str, Any]] = None
    return_state: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    ignore: bool = False  # duplicate/stale event: nothing is sent and the draft is untouched


class CatalogMatcher:
    """Finds catalog products, quantities and variants in a free-text message."""

    def __init__(self, products: List[Dict[str, Any]]):
        self.products = [p for p in products if p.get("available")]
        self._keys = {int(p["id"]): _significant(p["name"]) for p in self.products}

    def _variant_in(self, product: Dict[str, Any], region: List[str]) -> Optional[str]:
        stems = {_stem(t) for t in region}
        hits = [v["name"] for v in product.get("variants") or [] if set(_significant(v["name"])) & stems]
        return hits[0] if len(hits) == 1 else None

    def parse(self, text: str) -> Tuple[List[ParsedItem], List[Dict[str, Any]]]:
        """Returns (items, ambiguous_candidates)."""
        tokens = _tokens(text)
        stems = [_stem(t) for t in tokens]
        spans: List[Tuple[int, int, Dict[str, Any]]] = []
        used: set[int] = set()
        ordered = sorted(self.products, key=lambda p: -len(self._keys[int(p["id"])]))
        for product in ordered:
            key = self._keys[int(product["id"])]
            if not key:
                continue
            for start in range(len(stems)):
                window = range(start, min(len(stems), start + len(key) + 2))
                positions = [i for i in window if stems[i] in key and i not in used]
                if positions and positions[0] == start and set(stems[i] for i in positions) >= set(key):
                    spans.append((positions[0], positions[-1], product))
                    used.update(range(positions[0], positions[-1] + 1))
                    break
        partial, ambiguous = self._partial_by_segment(tokens, stems, used)
        if not spans:
            return [item for _, item in partial], ambiguous
        spans.sort(key=lambda s: s[0])
        bounds: List[Tuple[int, int]] = []
        region_start = 0
        for index, (start, end, _) in enumerate(spans):
            if index + 1 < len(spans):
                next_start = spans[index + 1][0]
                gap = [i for i in range(end + 1, next_start) if tokens[i] in _SEPARATORS]
                region_end = gap[0] if gap else next_start
            else:
                region_end = len(tokens)
            bounds.append((region_start, region_end))
            region_start = region_end
        positioned: List[Tuple[int, ParsedItem]] = list(partial)
        for (start, end, product), (r_start, r_end) in zip(spans, bounds):
            before = tokens[r_start:start]
            after = tokens[end + 1:r_end]
            quantity = next((q for q in (_quantity(t) for t in reversed(before)) if q), None) or 1
            variant = self._variant_in(product, after) or self._variant_in(product, before)
            positioned.append((start, ParsedItem(product=product, quantity=quantity, variant_name=variant)))
        positioned.sort(key=lambda entry: entry[0])
        return [item for _, item in positioned], ambiguous

    def _partial_by_segment(
        self, tokens: List[str], stems: List[str], used: set[int],
    ) -> Tuple[List[Tuple[int, ParsedItem]], List[Dict[str, Any]]]:
        """Partial matches ("coca lata") inside separator-delimited segments that hold no exact product match."""
        segments, start = [], 0
        for index, token in enumerate(tokens):
            if token in _SEPARATORS:
                segments.append((start, index))
                start = index + 1
        segments.append((start, len(tokens)))
        items: List[Tuple[int, ParsedItem]] = []
        ambiguous: List[Dict[str, Any]] = []
        for seg_start, seg_end in segments:
            if seg_start >= seg_end or any(i in used for i in range(seg_start, seg_end)):
                continue
            candidates = self._partial_candidates(stems[seg_start:seg_end])
            if len(candidates) == 1:
                region = tokens[seg_start:seg_end]
                quantity = next((q for q in (_quantity(t) for t in region) if q), None) or 1
                items.append((seg_start, ParsedItem(product=candidates[0], quantity=quantity,
                                                    variant_name=self._variant_in(candidates[0], region))))
            else:
                ambiguous.extend(c for c in candidates if c not in ambiguous)
        return items, ambiguous

    def _partial_candidates(self, stems: List[str]) -> List[Dict[str, Any]]:
        present = {s for s in stems if len(s) >= 4 or s == "2l"}
        if not present:
            return []
        scored = []
        for product in self.products:
            key = set(self._keys[int(product["id"])])
            variant_keys = set() if _is_size_only(product) else {
                k for v in product.get("variants") or [] for k in _significant(v["name"])}
            score = len(key & present) + len(variant_keys & present)
            if score:
                scored.append((score, product))
        if not scored:
            return []
        best = max(score for score, _ in scored)
        return [product for score, product in scored if score == best]

    def variant_options(self, product: Dict[str, Any]) -> str:
        return ", ".join(f"{v['name']} ({order_domain.money(v['price_cents'])})" for v in product.get("variants") or [])


def _is_size_only(product: Dict[str, Any]) -> bool:
    return {v["name"].lower() for v in product.get("variants") or []} <= {"broto", "média", "media", "grande", "pequena",
                                                                           "pequeno", "família", "familia"}


def detect_start(text: str, matcher: CatalogMatcher) -> bool:
    norm = normalize(text)
    if _START_PHRASES.search(norm):
        return True
    if _BUY_VERBS.search(norm) and "?" not in text and not _BROWSE.search(norm) and not _PRICE_QUESTION.search(norm):
        items, _ = matcher.parse(text)
        return bool(items)
    return False


def is_status_query(text: str) -> bool:
    return bool(_STATUS_QUERY.search(normalize(text)))


def _is_yes(norm: str) -> bool:
    """Explicit confirmation only ("sim", "sim, confirmo", "confirmo"); "pode", "isso" or "sim, mas..." are not."""
    return bool(_YES.fullmatch(" ".join(re.sub(r"[,;+#.!]", " ", norm).split())))


def claims_order_confirmation(text: str) -> bool:
    """True when a text tells the customer an order was received/confirmed (only the backend may say that)."""
    return bool(_ORDER_CLAIM.search(normalize(text)))


async def price_reply(catalog: Any, tenant_id: str, text: str) -> Optional[str]:
    """Answer "quanto custa a calabresa?" from the registered catalog; None when it is not such a question."""
    if not _PRICE_QUESTION.search(normalize(text)):
        return None
    products = await catalog.list_products(tenant_id, only_available=True)
    if not products:
        return None
    items, candidates = CatalogMatcher(products).parse(text)
    found = [item.product for item in items] or candidates
    if not found:
        return None
    lines = []
    for product in found[:6]:
        variants = product.get("variants") or []
        if variants:
            price = " · ".join(f"{v['name']} {order_domain.money(v['price_cents'])}" for v in variants)
        else:
            price = order_domain.money(product.get("price_cents") or 0)
        lines.append(f"*{product['name']}*: {price}")
    return "\n".join(lines)


def _summary_signature(priced: List[Dict[str, Any]], draft: Dict[str, Any]) -> str:
    payload = [[p["product_id"], p["variant_name"], p["quantity"], p["unit_price_cents"]] for p in priced]
    payload.append([draft.get("fulfillment"), draft.get("address"), draft.get("customer_name")])
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:16]


class OrderAssistant:
    def __init__(self, catalog_service: Any, order_service: Any) -> None:
        self.catalog = catalog_service
        self.orders = order_service

    # ── entry point ───────────────────────────────────────────────────────────

    async def handle(
        self,
        *,
        tenant_id: str,
        text: str,
        context: Dict[str, Any],
        customer_phone: str,
        phone_number_id: Optional[str],
        session_id: Optional[str],
        contact_name: Optional[str] = None,
        trigger: Optional[Dict[str, Any]] = None,
        dry_run: bool = False,
        now: Optional[datetime] = None,
        message_id: Optional[str] = None,
        message_ts: Optional[datetime] = None,
    ) -> Optional[AssistantResult]:
        """Return a reply when the assistant owns this message, else None (flow/AI continue as usual)."""
        now = now or datetime.utcnow()
        draft = self._live_draft(context.get("order_draft"), now)
        if draft is not None and message_id and message_id in (draft.get("seen_message_ids") or []):
            return AssistantResult(reply="", draft=draft, ignore=True)
        products = await self.catalog.list_products(tenant_id, only_available=True)
        if not products:
            return None
        matcher = CatalogMatcher(products)
        norm = normalize(text)

        if draft is None:
            if trigger is None and not detect_start(text, matcher):
                if is_status_query(text):
                    return await self._status_reply(tenant_id, customer_phone)
                return None
            draft = {
                "id": str(uuid.uuid4()),
                "stage": "items",
                "items": [],
                "fulfillment": None,
                "address": "",
                "customer_name": "",
                "return_state": (trigger or {}).get("return_state"),
                "started_at": now.isoformat(),
            }
            result = self._take_items(draft, matcher, text, starting=True)
            return self._touch(result, now, message_id)

        if _HANDOFF.search(norm):
            return AssistantResult(reply="", draft=None, return_state=None, metadata={"order_draft": "handoff"})
        if _CANCEL.search(norm):
            return AssistantResult(
                reply="Tudo bem, cancelei este pedido. Se quiser recomeçar, é só dizer \"quero fazer um pedido\".",
                draft=None, return_state=draft.get("return_state"), metadata={"order_draft": "cancelled"},
            )
        stage = draft.get("stage")
        if stage == "variant":
            result = self._take_variant(draft, matcher, text)
        elif stage in ("items", "more"):
            result = self._take_items(draft, matcher, text)
        elif stage == "fulfillment":
            result = self._take_fulfillment(draft, norm, matcher)
        elif stage == "address":
            result = self._take_address(draft, text, matcher)
        elif stage == "name":
            result = self._take_name(draft, text, matcher)
        elif stage == "confirm":
            result = await self._take_confirmation(
                draft, matcher, text, norm, tenant_id=tenant_id, customer_phone=customer_phone,
                phone_number_id=phone_number_id, session_id=session_id, dry_run=dry_run,
                now=now, message_ts=message_ts,
            )
        else:
            result = self._take_items(draft, matcher, text, starting=True)
        return self._touch(result, now, message_id)

    # ── stages ────────────────────────────────────────────────────────────────

    def _take_items(self, draft: Dict[str, Any], matcher: CatalogMatcher, text: str, starting: bool = False) -> AssistantResult:
        norm = normalize(text)
        items, ambiguous = matcher.parse(text)
        for item in items:
            draft["items"].append({
                "product_id": int(item.product["id"]),
                "name": item.product["name"],
                "variant_name": item.variant_name if item.product.get("variants") else None,
                "quantity": item.quantity,
            })
        if ambiguous:
            draft["stage"] = "items"
            names = ", ".join(p["name"] for p in ambiguous[:6])
            noted = ""
            if items:
                noted = "Anotado:\n" + "\n".join(f"• {self._item_label(i)}" for i in draft["items"]) + "\n\n"
            return AssistantResult(reply=f"{noted}Encontrei mais de uma opção: {names}. Qual delas você quer?",
                                   draft=draft)
        if items:
            return self._next_question(draft, matcher)
        if draft["items"] and (_NOTHING_MORE.search(norm) or _DELIVERY.search(norm) or _PICKUP.search(norm)):
            draft["stage"] = "fulfillment"
            if _DELIVERY.search(norm) or _PICKUP.search(norm):
                return self._take_fulfillment(draft, norm, matcher)
            return self._ask_fulfillment(draft)
        if draft["items"]:
            return AssistantResult(
                reply="Não encontrei esse item no cardápio. Diga o nome como aparece no cardápio, "
                      "ou responda NÃO se já terminou.",
                draft=draft,
            )
        intro = "Claro! O que você gostaria de pedir?" if starting else "Não encontrei esse item no cardápio."
        return AssistantResult(reply=f"{intro}\n\n{self._menu_overview(matcher)}", draft=draft)

    def _take_variant(self, draft: Dict[str, Any], matcher: CatalogMatcher, text: str) -> AssistantResult:
        index = draft.get("pending_index")
        product = self._product(matcher, draft["items"][index]["product_id"]) if index is not None else None
        if product is None:
            return self._next_question(draft, matcher)
        variant = matcher._variant_in(product, _tokens(text))
        if not variant:
            return AssistantResult(
                reply=f"Qual opção para {product['name']}? {matcher.variant_options(product)}", draft=draft
            )
        draft["items"][index]["variant_name"] = variant
        draft.pop("pending_index", None)
        return self._next_question(draft, matcher)

    def _take_fulfillment(self, draft: Dict[str, Any], norm: str, matcher: CatalogMatcher) -> AssistantResult:
        if _PICKUP.search(norm):
            draft["fulfillment"] = "retirada"
            draft["address"] = ""
        elif _DELIVERY.search(norm):
            draft["fulfillment"] = "entrega"
        else:
            return self._ask_fulfillment(draft)
        if draft["fulfillment"] == "entrega" and not draft.get("address"):
            draft["stage"] = "address"
            return AssistantResult(reply="Qual é o endereço completo para entrega? (rua, número, bairro e complemento)",
                                   draft=draft)
        return self._ask_name_or_confirm(draft, matcher)

    def _take_address(self, draft: Dict[str, Any], text: str, matcher: CatalogMatcher) -> AssistantResult:
        address = " ".join(str(text or "").split())
        if _PICKUP.search(normalize(text)) and len(address) < 25:
            draft["fulfillment"] = "retirada"
            return self._ask_name_or_confirm(draft, matcher)
        if len(address) < 8:
            return AssistantResult(reply="Pode me passar o endereço completo? (rua, número e bairro)", draft=draft)
        draft["address"] = address[:300]
        return self._ask_name_or_confirm(draft, matcher)

    def _take_name(self, draft: Dict[str, Any], text: str, matcher: CatalogMatcher) -> AssistantResult:
        name = " ".join(str(text or "").split()).strip(" .!")
        if not 2 <= len(name) <= 60 or _is_yes(normalize(name)) or normalize(name) in _NO:
            return AssistantResult(reply="Em qual nome fica o pedido?", draft=draft)
        draft["customer_name"] = name
        return self._summary(draft, matcher)

    async def _take_confirmation(
        self, draft: Dict[str, Any], matcher: CatalogMatcher, text: str, norm: str, *, tenant_id: str,
        customer_phone: str, phone_number_id: Optional[str], session_id: Optional[str], dry_run: bool,
        now: datetime, message_ts: Optional[datetime],
    ) -> AssistantResult:
        if _is_yes(norm):
            stale = self._confirmation_problem(draft, matcher, now, message_ts)
            if stale:
                result = self._summary(draft, matcher)
                result.reply = f"{stale}\n\n{result.reply}"
                return result
            if dry_run:
                return AssistantResult(reply="(Simulação) Pedido confirmado — nenhum pedido foi registrado.",
                                       draft=None, return_state=draft.get("return_state"),
                                       metadata={"order_draft": "confirmed_dry_run"})
            try:
                order = await self.orders.create(
                    tenant_id,
                    customer_phone=customer_phone,
                    customer_name=draft.get("customer_name") or "",
                    fulfillment=draft["fulfillment"],
                    address=draft.get("address") or "",
                    items=[{"product_id": i["product_id"], "variant_name": i.get("variant_name"),
                            "quantity": i["quantity"]} for i in draft["items"]],
                    idempotency_key=f"draft:{draft['id']}",
                    phone_number_id=phone_number_id or "",
                    session_id=session_id,
                    source="whatsapp",
                    actor_type="assistant",
                    actor_name="Assistente WhatsApp",
                )
            except OrderError as exc:
                draft["stage"] = "items"
                draft["items"] = []
                return AssistantResult(
                    reply=f"Não consegui registrar o pedido: {exc}. Nada foi confirmado. "
                          "Vamos refazer os itens? Me diga o que deseja.",
                    draft=draft,
                )
            except Exception:
                logger.exception("order_create_failed tenant=%s draft=%s", tenant_id, draft.get("id"))
                return AssistantResult(
                    reply="Não consegui registrar seu pedido agora, então ele *não* foi confirmado. "
                          "Responda *SIM* novamente em instantes para tentar de novo.",
                    draft=draft,
                )
            if not order or not order.get("id"):
                return AssistantResult(reply="Não consegui registrar seu pedido agora, então ele *não* foi confirmado.",
                                       draft=draft)
            if order.get("created") is False:
                reply = f"Seu pedido #{order['order_number']} já está registrado. ✅"
            else:
                reply = (
                    f"Pedido #{order['order_number']} registrado! ✅\n"
                    f"Total: {order_domain.money(order['total_cents'])}\n"
                    "Vou te avisar por aqui a cada atualização do pedido."
                )
            return AssistantResult(reply=reply, draft=None, order=order, return_state=draft.get("return_state"),
                                   metadata={"order_draft": "confirmed", "order_id": order["id"]})
        if norm in _NO or norm.startswith("nao "):
            return AssistantResult(
                reply="Tudo bem, não registrei o pedido. Se quiser recomeçar, é só dizer \"quero fazer um pedido\".",
                draft=None, return_state=draft.get("return_state"), metadata={"order_draft": "declined"},
            )
        items, _ = matcher.parse(text)
        if items:
            draft["stage"] = "items"
            return self._take_items(draft, matcher, text)
        return AssistantResult(reply="Para confirmar o pedido responda *SIM*, ou *NÃO* para cancelar.", draft=draft)

    # ── helpers ───────────────────────────────────────────────────────────────

    def _next_question(self, draft: Dict[str, Any], matcher: CatalogMatcher) -> AssistantResult:
        for index, item in enumerate(draft["items"]):
            product = self._product(matcher, item["product_id"])
            if product and product.get("variants") and not item.get("variant_name"):
                draft["stage"] = "variant"
                draft["pending_index"] = index
                return AssistantResult(
                    reply=f"Qual opção para {product['name']}? {matcher.variant_options(product)}", draft=draft
                )
        draft["stage"] = "more"
        lines = "\n".join(f"• {self._item_label(i)}" for i in draft["items"])
        return AssistantResult(
            reply=f"Anotado:\n{lines}\n\nQuer adicionar mais alguma coisa? Se não, me diga se é *entrega* ou *retirada*.",
            draft=draft,
        )

    def _ask_fulfillment(self, draft: Dict[str, Any]) -> AssistantResult:
        draft["stage"] = "fulfillment"
        return AssistantResult(reply="O pedido é para *entrega* ou *retirada* na loja?", draft=draft)

    def _ask_name_or_confirm(self, draft: Dict[str, Any], matcher: CatalogMatcher) -> AssistantResult:
        if not draft.get("customer_name"):
            draft["stage"] = "name"
            return AssistantResult(reply="Em qual nome fica o pedido?", draft=draft)
        return self._summary(draft, matcher)

    def _summary(self, draft: Dict[str, Any], matcher: CatalogMatcher) -> AssistantResult:
        try:
            priced = price_items(matcher.products, draft["items"])
        except OrderError as exc:
            draft["stage"] = "items"
            draft["items"] = []
            return AssistantResult(reply=f"{exc}. Vamos refazer os itens? Me diga o que deseja.", draft=draft)
        draft["stage"] = "confirm"
        draft["summary"] = {"signature": _summary_signature(priced, draft), "at": datetime.utcnow().isoformat()}
        lines = "\n".join(
            f"• {p['quantity']}x {p['product_name']}" + (f" ({p['variant_name']})" if p["variant_name"] else "")
            + f" — {order_domain.money(p['line_total_cents'])}"
            for p in priced
        )
        total = sum(p["line_total_cents"] for p in priced)
        if draft["fulfillment"] == "entrega":
            where = f"Entrega em: {draft['address']}\n(Taxa de entrega, se houver, é confirmada pela loja.)"
        else:
            where = "Retirada na loja"
        reply = (
            f"Confira seu pedido:\n{lines}\n\nTotal: {order_domain.money(total)}\n{where}\n"
            f"Nome: {draft['customer_name']}\n\nResponda *SIM* para confirmar ou *NÃO* para cancelar."
        )
        return AssistantResult(reply=reply, draft=draft)

    def _confirmation_problem(
        self, draft: Dict[str, Any], matcher: CatalogMatcher, now: datetime, message_ts: Optional[datetime],
    ) -> Optional[str]:
        """Why a "SIM" cannot confirm the current summary (None when it can)."""
        summary = draft.get("summary") or {}
        try:
            shown_at = datetime.fromisoformat(str(summary.get("at")))
        except ValueError:
            return "Confira o resumo atualizado do seu pedido:"
        if message_ts is not None:
            lag = shown_at.replace(microsecond=0) - message_ts.replace(tzinfo=None)
            # Sent before the summary existed (late/out-of-order delivery); a large gap is a clock offset instead.
            if timedelta(seconds=1) < lag < timedelta(minutes=30):
                return "Recebi uma resposta anterior ao resumo. Confira o resumo do seu pedido:"
        if now - shown_at > CONFIRM_TTL:
            return "Faz um tempo desde o resumo. Confira se está tudo certo:"
        try:
            priced = price_items(matcher.products, draft["items"])
        except OrderError:
            return "Algum item mudou no cardápio."
        if _summary_signature(priced, draft) != summary.get("signature"):
            return "Os valores do cardápio mudaram. Confira o resumo atualizado:"
        return None

    def _touch(self, result: AssistantResult, now: datetime, message_id: Optional[str] = None) -> AssistantResult:
        if result.draft is not None:
            result.draft["updated_at"] = now.isoformat()
            if message_id:
                result.draft["seen_message_ids"] = [*(result.draft.get("seen_message_ids") or [])[-19:], message_id]
        return result

    async def _status_reply(self, tenant_id: str, customer_phone: str) -> Optional[AssistantResult]:
        order = await self.orders.latest_for_customer(tenant_id, customer_phone)
        if not order:
            return None
        return AssistantResult(
            reply=f"Seu pedido #{order['order_number']} está: *{order['status_label']}*.",
            draft=None, metadata={"order_status_query": order["id"]},
        )

    @staticmethod
    def _live_draft(raw: Any, now: datetime) -> Optional[Dict[str, Any]]:
        if not isinstance(raw, dict) or not raw.get("id"):
            return None
        try:
            updated = datetime.fromisoformat(str(raw.get("updated_at") or raw.get("started_at")))
        except ValueError:
            return None
        if now - updated > DRAFT_TTL:
            return None
        return {**raw, "items": [dict(i) for i in raw.get("items") or []]}

    @staticmethod
    def _product(matcher: CatalogMatcher, product_id: int) -> Optional[Dict[str, Any]]:
        return next((p for p in matcher.products if int(p["id"]) == int(product_id)), None)

    @staticmethod
    def _item_label(item: Dict[str, Any]) -> str:
        variant = f" ({item['variant_name']})" if item.get("variant_name") else ""
        return f"{item['quantity']}x {item['name']}{variant}"

    @staticmethod
    def _menu_overview(matcher: CatalogMatcher) -> str:
        groups: Dict[str, List[str]] = {}
        for product in matcher.products:
            groups.setdefault(product.get("category_name") or "Outros", []).append(product["name"])
        lines = [f"*{cat}:* " + ", ".join(names[:8]) + ("…" if len(names) > 8 else "") for cat, names in groups.items()]
        return "\n".join(lines) + "\n\nPode mandar tudo de uma vez, com quantidade e opção (tamanho, sabor)."
