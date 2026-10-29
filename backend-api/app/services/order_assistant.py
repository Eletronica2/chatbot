"""WhatsApp order assistant: catalog-grounded cart with explicit confirmation.

The assistant never writes orders itself: on an explicit "SIM" it calls ``OrderService.create`` (prices recomputed
from the catalog, idempotent per draft). The draft lives in ``session.context["order_draft"]``:

* ``items``   — cart lines ``{line_id, product_id, name, variant_name, quantity}`` (always fully specified);
* ``pending`` — lines still waiting for an option (size, flavor); they are not in the cart yet;
* ``focus``   — line_id of the last line touched ("quero só uma", "na verdade...");
* ``clarify`` — a question waiting for the customer to pick among several lines/products.

Every cart change drops the shown summary, so a new summary and a new explicit "SIM" are always required.
"""
from __future__ import annotations

import difflib
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
from app.services.order_service import OrderConflict, OrderError, price_items

logger = logging.getLogger(__name__)

DRAFT_TTL = timedelta(hours=2)
# A "SIM" only confirms the summary the customer saw recently; older summaries are shown again first.
CONFIRM_TTL = timedelta(minutes=15)
START_ACTION = "start_order"

_STOP = {"de", "da", "do", "das", "dos", "com", "c", "e", "a", "o", "as", "os", "um", "uma", "pizza", "pizzas",
         "quero", "queria", "pra", "para", "por", "favor", "mais", "sem", "no", "na", "em", "meu", "minha"}
_SEPARATORS = {"e", "mais", ",", "+", ";", "tambem"}
_NUMBER_WORDS = {"um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6,
                 "sete": 7, "oito": 8, "nove": 9, "dez": 10}
# Digits that are spelled out inside product names ("Quatro Queijos" written as "4 queijos").
_DIGIT_WORDS = {"1": "um", "2": "dois", "3": "tres", "4": "quatro", "5": "cinco", "6": "seis", "7": "sete",
                "8": "oito", "9": "nove", "10": "dez"}
_NUM = r"(?P<q>um|uma|dois|duas|tres|quatro|cinco|seis|sete|oito|nove|dez|\d{1,2})"
_START_PHRASES = re.compile(
    r"\b(fazer (um |o )?pedido|novo pedido|quero (fazer )?(um )?pedi(r|do)|queria pedir|gostaria de pedir|"
    r"quero encomendar|vou pedir)\b"
)
_BUY_VERBS = re.compile(r"\b(quero|queria|gostaria|vou querer|manda|me ve|me da|pode mandar|pedir|pedido)\b")
_BROWSE = re.compile(r"\b(ver|veja|mostra|mostrar|mostre|conhecer|saber|olhar|cardapio|menu|opcoes|sabores)\b")
_PRICE_QUESTION = re.compile(r"\b(quanto (custa|e|sai|fica|ta|esta)|qual (o|e o) (preco|valor)|preco d|valor d|precos? )")
_ORDER_CLAIM = re.compile(
    r"(\bpedido\b.{0,60}\b(recebido|confirmado|registrado|anotado|finalizado|realizado|entregue|enviado|a caminho"
    r"|em preparo|sendo preparado|pronto)\b"
    r"|\b(recebemos|registramos|confirmamos|anotamos|anotei|registrei|confirmei|temos|ja temos) (o |seu |o seu )?pedido\b"
    r"|\bpagamento\b.{0,30}\b(confirmado|aprovado|recebido)\b)"
)
_STATUS_QUERY = re.compile(r"\b(meu pedido|status do pedido|cade (o )?(meu )?pedido|andamento do pedido|"
                           r"pedido (#|n|numero )?\s*\d+)\b")
_YES = re.compile(r"(sim|confirmo|confirmar|confirma|confirmado|pode confirmar|ok confirmo|ok pode confirmar)"
                  r"( (confirmo|confirma|pode confirmar|pode|por favor|esta certo|ta certo|certo|isso))?")
_ACCEPT = re.compile(r"(aceito|aceita|aceitar|sim aceito|aceito sim|ok aceito|sim|confirmo|sim confirmo)")
_NO = {"nao", "n", "nao quero", "nao obrigado", "agora nao"}
_NOTHING_MORE = re.compile(r"^(nao|n|so isso|e so|so|nada|nada mais|mais nada|por enquanto e so|"
                           r"nao obrigad[oa]|ta bom|pronto|acabou|e isso)\b")
_CANCEL = re.compile(r"\b(cancelar|cancela|cancele|desisto|desistir|deixa pra la|esquece)\b")
_HANDOFF = re.compile(r"\b(atendente|humano|pessoa|falar com alguem)\b")
_DELIVERY = re.compile(r"\b(entrega|entregar|delivery|em casa|receber)\b")
_PICKUP = re.compile(r"\b(retirada|retirar|retiro|buscar|busco|balcao|pegar ai|vou ai)\b")
# Cart operations (on normalized text).
_OP_REPLACE = re.compile(r"\b(troca|trocar|troque|substitui|substituir|substitua|muda|mudar|mude|altera|alterar|"
                         r"altere)\b(?P<old>.*?)\b(por|pelo|pela)\b(?P<new>.+)$")
_OP_REMOVE = re.compile(r"\b(tira|tirar|tire|remove|remover|remova|retira|retire|exclui|excluir|exclua|cancela|"
                        r"cancele)\b(?P<ref>.+)$")
_OP_CORRECT = re.compile(r"^(na verdade|alias|corrigindo|quis dizer|eu quis dizer|errei|melhor)\b(?P<new>.*)$")
_OP_QUANTITY = (
    re.compile(rf"^(eu )?(quero |vou querer )?(so|apenas|somente) {_NUM}\b(?P<ref>.*)$"),
    re.compile(rf"^(deixa|coloca|muda para|muda pra|altera para|altera pra) {_NUM}\b(?P<ref>.*)$"),
    re.compile(rf"\b(quantidade|qtd)\b(?P<ref>.*?)\b(para|pra) {_NUM}\b"),
)
_OP_ADD = re.compile(r"\b(adiciona|adicione|adicionar|acrescenta|acrescente|inclui|incluir|tambem)\b")
_ADDRESS_CHANGE = re.compile(r"\b(muda|mudar|troca|trocar|corrige|corrigir|altera|alterar)\b.*\bendereco\b")
_NO_NUMBER = re.compile(r"\b(s ?/ ?n|sn|sem numero|sem n)\b")
_COMPLEMENT = re.compile(r"\b(casa|apto|apartamento|ap|bloco|bl|fundos|sala|loja|referencia|perto|proximo|ao lado|"
                         r"esquina|portao|condominio|cond)\b")
_ADDRESS_FIELDS = ("street", "number", "neighborhood", "city")
_ADDRESS_QUESTIONS = {
    "street": "Qual é a rua do endereço de entrega?",
    "number": "Qual é o número? (se não tiver, responda *sem número*)",
    "neighborhood": "Qual é o bairro?",
    "city": "Qual é a cidade?",
}


def normalize(text: str) -> str:
    value = unicodedata.normalize("NFKD", str(text or "").lower())
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    # Packaging and sizes are one token ("2 litros" -> "2l", "350 ml" -> "350ml"): never a quantity.
    value = re.sub(r"\b(\d+|dois)\s*(litros|litro|lts|lt|l)\b", lambda m: ("2" if m.group(1) == "dois" else m.group(1)) + "l", value)
    value = re.sub(r"\b(\d+)\s*(ml|cm|kg|g)\b", r"\1\2", value)
    value = re.sub(r"([,;+])", r" \1 ", value)
    value = re.sub(r"[^a-z0-9,;+#/]+", " ", value)
    return " ".join(value.split())


def _tokens(text: str) -> List[str]:
    return normalize(text).split()


def _stem(token: str) -> str:
    return token[:-1] if len(token) > 3 and token.endswith("s") else token


def _significant(name: str) -> List[str]:
    return [_stem(t) for t in _tokens(name)
            if t not in _STOP and t not in {",", ";", "+"} and (len(t) >= 3 or t.isdigit() or t == "2l")]


def _quantity(token: str) -> Optional[int]:
    if token.isdigit():
        value = int(token)
        return value if 1 <= value <= 50 else None
    return _NUMBER_WORDS.get(token)


_EXACT_ONLY = set(_NUMBER_WORDS) | {"quanto", "quanta", "quantos", "quantas", "quando", "qual", "quais", "quero"}


def _close(a: str, b: str) -> bool:
    """Typo tolerance for longer words ("antartica" ~ "antarctica", "calabreza" ~ "calabresa").

    Number words and question words never fuzz ("quanto" is not "quatro").
    """
    if a in _EXACT_ONLY or b in _EXACT_ONLY:
        return False
    return len(a) >= 5 and len(b) >= 5 and difflib.SequenceMatcher(None, a, b).ratio() >= 0.8


def _hit(token: str, keys) -> bool:
    return token in keys or any(_close(token, key) for key in keys)


def _new_line_id() -> str:
    return uuid.uuid4().hex[:8]


@dataclass
class ParsedItem:
    product: Dict[str, Any]
    quantity: int
    variant_name: Optional[str]
    explicit_quantity: bool = False


@dataclass
class AssistantResult:
    reply: str
    draft: Optional[Dict[str, Any]]
    order: Optional[Dict[str, Any]] = None
    return_state: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    ignore: bool = False  # duplicate/stale event: nothing is sent and the draft is untouched


class CatalogMatcher:
    """Finds catalog products, quantities and options in a free-text message."""

    def __init__(self, products: List[Dict[str, Any]]):
        self.products = [p for p in products if p.get("available")]
        self._keys = {int(p["id"]): _significant(p["name"]) for p in self.products}

    def key(self, product: Dict[str, Any]) -> List[str]:
        return self._keys.get(int(product["id"])) or _significant(product["name"])

    def product(self, product_id: int) -> Optional[Dict[str, Any]]:
        return next((p for p in self.products if int(p["id"]) == int(product_id)), None)

    @staticmethod
    def _aligned(stems: List[str], key: List[str]) -> List[str]:
        """Read "4 queijos" as "quatro queijos" when the product name spells the number."""
        out = list(stems)
        for i, stem in enumerate(stems):
            word = _DIGIT_WORDS.get(stem)
            if word and word in key and word not in stems and i + 1 < len(stems) and stems[i + 1] in key:
                out[i] = word
        return out

    @staticmethod
    def _variant_keys(product: Dict[str, Any]) -> set:
        return {k for v in product.get("variants") or [] for k in _significant(v["name"])}

    def _variant_in(self, product: Dict[str, Any], region: List[str]) -> Optional[str]:
        stems = {_stem(t) for t in region}
        hits = [v["name"] for v in product.get("variants") or []
                if any(_hit(s, set(_significant(v["name"]))) for s in stems)]
        return hits[0] if len(hits) == 1 else None

    def _name_positions(self, stems: List[str], product: Dict[str, Any]) -> set:
        """Token positions that belong to the product name or one of its options (never a quantity)."""
        key = self.key(product)
        aligned = self._aligned(stems, key)
        names = set(key) | self._variant_keys(product)
        return {i for i, stem in enumerate(aligned) if _hit(stem, names)}

    def parse(self, text: str) -> Tuple[List[ParsedItem], List[Dict[str, Any]]]:
        """Returns (items, ambiguous_candidates)."""
        tokens = _tokens(text)
        stems = [_stem(t) for t in tokens]
        spans: List[Tuple[int, int, Dict[str, Any]]] = []
        used: set[int] = set()
        ordered = sorted(self.products, key=lambda p: -len(self.key(p)))
        for product in ordered:
            key = self.key(product)
            if not key:
                continue
            aligned = self._aligned(stems, key)
            for start in range(len(aligned)):
                window = range(start, min(len(aligned), start + len(key) + 2))
                positions = [i for i in window if aligned[i] in key and i not in used]
                if positions and positions[0] == start and set(aligned[i] for i in positions) >= set(key):
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
            quantity = next((q for q in (_quantity(t) for t in reversed(before)) if q), None)
            variant = self._variant_in(product, after) or self._variant_in(product, before)
            positioned.append((start, ParsedItem(product=product, quantity=quantity or 1, variant_name=variant,
                                                 explicit_quantity=quantity is not None)))
        positioned.sort(key=lambda entry: entry[0])
        return [item for _, item in positioned], ambiguous

    def _partial_by_segment(
        self, tokens: List[str], stems: List[str], used: set[int],
    ) -> Tuple[List[Tuple[int, ParsedItem]], List[Dict[str, Any]]]:
        """Partial matches ("coca lata", "quatro queijos") inside segments that hold no exact product match."""
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
            region = tokens[seg_start:seg_end]
            candidates = self._partial_candidates(stems[seg_start:seg_end])
            if len(candidates) == 1:
                product = candidates[0]
                name_positions = self._name_positions([_stem(t) for t in region], product)
                quantity = next((q for i, q in enumerate(_quantity(t) for t in region)
                                 if q and i not in name_positions), None)
                items.append((seg_start, ParsedItem(product=product, quantity=quantity or 1,
                                                    variant_name=self._variant_in(product, region),
                                                    explicit_quantity=quantity is not None)))
            else:
                ambiguous.extend(c for c in candidates if c not in ambiguous)
        return items, ambiguous

    def _partial_candidates(self, stems: List[str]) -> List[Dict[str, Any]]:
        if not any(len(s) >= 4 or s == "2l" for s in stems):
            return []
        scored = []
        for product in self.products:
            key = set(self.key(product))
            aligned = {s for s in self._aligned(stems, list(key)) if len(s) >= 4 or s == "2l"}
            variant_keys = set() if _is_size_only(product) else self._variant_keys(product)
            score = sum(1 for s in aligned if _hit(s, key)) + sum(1 for s in aligned if _hit(s, variant_keys))
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


def _plain(norm: str) -> str:
    return " ".join(re.sub(r"[,;+#.!]", " ", norm).split())


def _is_yes(norm: str) -> bool:
    """Explicit confirmation only ("sim", "sim, confirmo", "confirmo"); "pode", "isso" or "sim, mas..." are not."""
    return bool(_YES.fullmatch(_plain(norm)))


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


def parse_address(text: str) -> Dict[str, str]:
    """Split a free-text address into street / number / neighborhood / city / complement (nothing is invented)."""
    raw = " ".join(str(text or "").split()).strip(" .")
    parts = [p.strip(" .") for p in re.split(r"[,;\n]| - ", raw) if p.strip(" .")]
    found: Dict[str, str] = {}
    rest: List[str] = []
    for part in parts:
        norm = normalize(part)
        if "number" not in found and _NO_NUMBER.search(norm):
            found["number"] = "s/n"
            before = re.split(r"(?i)\b(s\s*/\s*n|sem n[uú]mero|sem n)\b", part)[0].strip(" ,.")
            if before and "street" not in found and re.search(r"[A-Za-zÀ-ú]{3,}", before):
                found["street"] = before
            continue
        number = re.search(r"(?:^|\s)(?:n[º°o]?\.?\s*)?(\d{1,5}[A-Za-z]?)(?:\s|$)", part)
        if "number" not in found and number and not re.fullmatch(r"\d{5}-?\d{3}", part.strip()):
            found["number"] = number.group(1)
            before = part[:number.start()].strip(" ,.")
            after = part[number.end():].strip(" ,.")
            if before and "street" not in found and re.search(r"[A-Za-zÀ-ú]{3,}", before):
                found["street"] = before
            if after:
                rest.append(after)
            continue
        rest.append(part)
    for part in rest:
        if "street" not in found and re.search(r"[A-Za-zÀ-ú]{3,}", part):
            found["street"] = part
        elif _COMPLEMENT.search(normalize(part)):
            found["complement"] = ", ".join(filter(None, [found.get("complement"), part]))
        elif "neighborhood" not in found:
            found["neighborhood"] = part
        elif "city" not in found:
            found["city"] = part
        else:
            found["complement"] = ", ".join(filter(None, [found.get("complement"), part]))
    return found


def format_address(parts: Dict[str, str]) -> str:
    text = f"{parts['street']}, {parts['number']} - {parts['neighborhood']}, {parts['city']}"
    return f"{text} ({parts['complement']})" if parts.get("complement") else text


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
        norm = normalize(text)
        if draft is None:
            decision = await self._acceptance_reply(tenant_id, customer_phone, norm, message_ts, dry_run)
            if decision is not None:
                return decision
        products = await self.catalog.list_products(tenant_id, only_available=True)
        if not products:
            return None
        matcher = CatalogMatcher(products)

        if draft is None:
            if trigger is None and not detect_start(text, matcher):
                if is_status_query(text):
                    return await self._status_reply(tenant_id, customer_phone)
                return None
            draft = {
                "id": str(uuid.uuid4()),
                "stage": "items",
                "items": [],
                "pending": [],
                "fulfillment": None,
                "address": "",
                "address_parts": {},
                "customer_name": "",
                "return_state": (trigger or {}).get("return_state"),
                "started_at": now.isoformat(),
            }
            result = self._take_items(draft, matcher, text, starting=True)
            return self._touch(result, now, message_id)

        if _HANDOFF.search(norm):
            return AssistantResult(reply="", draft=None, return_state=None, metadata={"order_draft": "handoff"})
        stage = draft.get("stage")
        result = None
        if draft.get("clarify"):
            result = self._resolve_clarify(draft, matcher, text)
        if result is None and stage not in ("address", "name"):
            result = self._cart_operation(draft, matcher, text, norm)
        if result is None and _CANCEL.search(norm):
            return AssistantResult(
                reply="Tudo bem, cancelei este pedido. Se quiser recomeçar, é só dizer \"quero fazer um pedido\".",
                draft=None, return_state=draft.get("return_state"), metadata={"order_draft": "cancelled"},
            )
        if result is None:
            if stage == "variant":
                result = self._take_variant(draft, matcher, text)
            elif stage in ("items", "more"):
                result = self._take_items(draft, matcher, text)
            elif stage == "fulfillment":
                result = self._take_fulfillment(draft, norm, matcher, text)
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

    # ── cart ──────────────────────────────────────────────────────────────────

    @staticmethod
    def _label(line: Dict[str, Any]) -> str:
        variant = f" ({line['variant_name']})" if line.get("variant_name") else ""
        return f"{line['quantity']}x {line['name']}{variant}"

    def _add_line(self, draft: Dict[str, Any], product: Dict[str, Any], variant: Optional[str], quantity: int) -> None:
        """Add to the cart (merging an identical line) or park it in ``pending`` until the option is chosen."""
        if product.get("variants") and not variant:
            line = {"line_id": _new_line_id(), "product_id": int(product["id"]), "name": product["name"],
                    "variant_name": None, "quantity": quantity}
            draft.setdefault("pending", []).append(line)
            draft["focus"] = line["line_id"]
            return
        variant = variant if product.get("variants") else None
        same = next((line for line in draft["items"] if line["product_id"] == int(product["id"])
                     and line.get("variant_name") == variant), None)
        if same:
            same["quantity"] += quantity
            draft["focus"] = same["line_id"]
            return
        line = {"line_id": _new_line_id(), "product_id": int(product["id"]), "name": product["name"],
                "variant_name": variant, "quantity": quantity}
        draft["items"].append(line)
        draft["focus"] = line["line_id"]

    def _lines(self, draft: Dict[str, Any]) -> List[Dict[str, Any]]:
        return [*draft["items"], *(draft.get("pending") or [])]

    def _find_line(self, draft: Dict[str, Any], line_id: Optional[str]) -> Optional[Dict[str, Any]]:
        return next((line for line in self._lines(draft) if line["line_id"] == line_id), None)

    def _match_lines(self, draft: Dict[str, Any], matcher: CatalogMatcher, ref: str,
                     among: Optional[List[str]] = None) -> List[Dict[str, Any]]:
        """Cart lines the customer refers to ("a coca", "a de calabresa", "o refrigerante 2l")."""
        stems = [_stem(t) for t in _tokens(ref)]
        scored = []
        for line in self._lines(draft):
            if among is not None and line["line_id"] not in among:
                continue
            key = _significant(line["name"])
            aligned = CatalogMatcher._aligned(stems, key)
            score = sum(1 for s in set(aligned) if _hit(s, set(key)))
            if line.get("variant_name"):
                score += sum(1 for s in set(stems) if _hit(s, set(_significant(line["variant_name"]))))
            if score:
                scored.append((score, line))
        if not scored:
            return []
        best = max(score for score, _ in scored)
        return [line for score, line in scored if score == best]

    def _remove_line(self, draft: Dict[str, Any], line_id: str) -> None:
        draft["items"] = [line for line in draft["items"] if line["line_id"] != line_id]
        draft["pending"] = [line for line in draft.get("pending") or [] if line["line_id"] != line_id]
        if draft.get("focus") == line_id:
            draft["focus"] = draft["items"][-1]["line_id"] if draft["items"] else None

    def _ask_which_line(self, draft: Dict[str, Any], op: Dict[str, Any], lines: List[Dict[str, Any]],
                        question: str) -> AssistantResult:
        draft["clarify"] = {**op, "line_ids": [line["line_id"] for line in lines]}
        options = "\n".join(f"{i}) {self._label(line)}" for i, line in enumerate(lines, start=1))
        return AssistantResult(reply=f"{question}\n{options}", draft=draft)

    def _cart_operation(self, draft: Dict[str, Any], matcher: CatalogMatcher, text: str, norm: str) -> Optional[AssistantResult]:
        """Replace / correct / remove / change quantity. None when the message is not a cart edit."""
        for pattern in _OP_QUANTITY:
            match = pattern.search(norm)
            if match and _quantity(match.group("q")):
                ref = match.group("ref").strip()
                lines = self._match_lines(draft, matcher, ref) if ref else []
                if not lines:
                    focus = self._find_line(draft, draft.get("focus"))
                    lines = [focus] if focus and not ref else []
                if not lines:
                    break
                return self._apply({"op": "quantity", "quantity": _quantity(match.group("q"))}, draft, matcher, lines,
                                   "Qual item deve ficar com essa quantidade?")
        match = _OP_REPLACE.search(norm)
        if match and match.group("new").strip():
            lines = self._match_lines(draft, matcher, match.group("old"))
            if lines:
                return self._apply({"op": "replace", "new": match.group("new")}, draft, matcher, lines,
                                   "Qual item você quer trocar?")
            if self._mentions_product(matcher, match.group("old")):
                return self._not_in_cart(draft, match.group("old"))
        match = _OP_CORRECT.search(norm)
        if match and match.group("new").strip():
            new = match.group("new")
            new_tokens = _tokens(new)
            # The line being corrected: one whose product has the option named ("na verdade, Antarctica"),
            # or one named directly; the line in focus breaks ties.
            by_option = [line for line in self._lines(draft) if (product := matcher.product(line["product_id"]))
                         and product.get("variants") and matcher._variant_in(product, new_tokens)]
            lines = by_option or self._match_lines(draft, matcher, new)
            focus = self._find_line(draft, draft.get("focus"))
            if focus and (focus in lines or not lines):
                lines = [focus]
            if lines:
                return self._apply({"op": "replace", "new": new, "verb": "Corrigi"}, draft, matcher, lines,
                                   "Qual item você quer corrigir?")
        match = _OP_REMOVE.search(norm)
        if match:
            lines = self._match_lines(draft, matcher, match.group("ref"))
            if lines:
                return self._apply({"op": "remove"}, draft, matcher, lines, "Qual item você quer tirar?")
            # Removing something that is not in the cart never adds it ("cancela o pedido" still cancels).
            if self._mentions_product(matcher, match.group("ref")):
                return self._not_in_cart(draft, match.group("ref"))
        return None

    @staticmethod
    def _mentions_product(matcher: CatalogMatcher, text: str) -> bool:
        items, ambiguous = matcher.parse(text)
        return bool(items or ambiguous)

    def _not_in_cart(self, draft: Dict[str, Any], ref: str) -> AssistantResult:
        lines = "\n".join(f"• {self._label(i)}" for i in draft["items"]) or "(vazio)"
        return AssistantResult(reply=f"Não encontrei \"{ref.strip()}\" no seu pedido. Ele está assim:\n{lines}",
                               draft=draft)

    def _apply(self, op: Dict[str, Any], draft: Dict[str, Any], matcher: CatalogMatcher,
               lines: List[Dict[str, Any]], question: str) -> AssistantResult:
        if len(lines) > 1:
            return self._ask_which_line(draft, op, lines, question)
        line = lines[0]
        if op["op"] == "remove":
            self._remove_line(draft, line["line_id"])
            return self._after_change(draft, matcher, f"Removi: {self._label(line)}.")
        if op["op"] == "quantity":
            before = self._label(line)
            line["quantity"] = op["quantity"]
            draft["focus"] = line["line_id"]
            return self._after_change(draft, matcher, f"Alterei: {before} → {self._label(line)}.")
        return self._replace_line(draft, matcher, line, op["new"], op.get("verb", "Troquei"))

    def _replace_line(self, draft: Dict[str, Any], matcher: CatalogMatcher, line: Dict[str, Any], new_text: str,
                      verb: str) -> AssistantResult:
        before = self._label(line)
        product = matcher.product(line["product_id"])
        items, ambiguous = matcher.parse(new_text)
        other = [i for i in items if not product or int(i.product["id"]) != int(product["id"])]
        variant = matcher._variant_in(product, _tokens(new_text)) if product and product.get("variants") else None
        if variant and not other:
            self._remove_line(draft, line["line_id"])
            self._add_line(draft, product, variant, line["quantity"])
            changed = self._find_line(draft, draft["focus"])
            return self._after_change(draft, matcher, f"{verb}: {before} → {self._label(changed)}.")
        if len(items) == 1:
            item = items[0]
            quantity = item.quantity if item.explicit_quantity else line["quantity"]
            self._remove_line(draft, line["line_id"])
            self._add_line(draft, item.product, item.variant_name, quantity)
            changed = self._find_line(draft, draft["focus"])
            return self._after_change(draft, matcher, f"{verb}: {before} → {self._label(changed)}.")
        if len(ambiguous) > 1:
            draft["clarify"] = {"op": "replace_with", "line_ids": [line["line_id"]], "text": new_text,
                                "product_ids": [int(p["id"]) for p in ambiguous[:6]], "verb": verb}
            names = "\n".join(f"{i}) {p['name']}" for i, p in enumerate(ambiguous[:6], start=1))
            return AssistantResult(reply=f"Qual destes deve entrar no lugar de {before}?\n{names}", draft=draft)
        return AssistantResult(
            reply=f"Não encontrei essa opção no cardápio para trocar {before}. Diga o nome como aparece no cardápio.",
            draft=draft,
        )

    def _resolve_clarify(self, draft: Dict[str, Any], matcher: CatalogMatcher, text: str) -> Optional[AssistantResult]:
        clarify = draft.pop("clarify")
        norm = _plain(normalize(text))
        ordinal = {"1": 0, "primeiro": 0, "primeira": 0, "2": 1, "segundo": 1, "segunda": 1, "3": 2, "terceiro": 2,
                   "terceira": 2, "4": 3, "5": 4, "6": 5}
        if clarify["op"] in ("add_choice", "replace_with"):
            candidates = [p for p in (matcher.product(pid) for pid in clarify["product_ids"]) if p]
            chosen = None
            if norm in ordinal and ordinal[norm] < len(candidates):
                chosen = candidates[ordinal[norm]]
            else:
                stems = [_stem(t) for t in _tokens(text)]
                scored = [(sum(1 for s in CatalogMatcher._aligned(stems, matcher.key(p)) if _hit(s, set(matcher.key(p)))), p)
                          for p in candidates]
                best = max((score for score, _ in scored), default=0)
                winners = [p for score, p in scored if score == best and score > 0]
                chosen = winners[0] if len(winners) == 1 else None
            if chosen is None:
                return None
            tokens = _tokens(f"{clarify.get('text', '')} {text}")
            variant = matcher._variant_in(chosen, tokens)
            if clarify["op"] == "add_choice":
                self._add_line(draft, chosen, variant, int(clarify.get("quantity") or 1))
                return self._after_change(draft, matcher, "")
            line = self._find_line(draft, clarify["line_ids"][0])
            if not line:
                return None
            before = self._label(line)
            self._remove_line(draft, line["line_id"])
            self._add_line(draft, chosen, variant, line["quantity"])
            changed = self._find_line(draft, draft["focus"])
            return self._after_change(draft, matcher, f"{clarify.get('verb', 'Troquei')}: {before} → {self._label(changed)}.")
        lines = [line for line in (self._find_line(draft, lid) for lid in clarify["line_ids"]) if line]
        if norm in ordinal and ordinal[norm] < len(lines):
            chosen_lines = [lines[ordinal[norm]]]
        else:
            chosen_lines = self._match_lines(draft, matcher, text, among=[line["line_id"] for line in lines])
        if len(chosen_lines) != 1:
            return None
        return self._apply(clarify, draft, matcher, chosen_lines, "")

    def _after_change(self, draft: Dict[str, Any], matcher: CatalogMatcher, note: str) -> AssistantResult:
        """Any cart edit invalidates the shown summary; a new one (and a new SIM) is required."""
        draft.pop("summary", None)
        result = self._next_question(draft, matcher)
        if draft["stage"] == "more" and draft["items"] and self._checkout_ready(draft):
            result = self._summary(draft, matcher)
        if not draft["items"] and not draft.get("pending"):
            draft["stage"] = "items"
            result = AssistantResult(reply="Seu pedido ficou vazio. O que você gostaria de pedir?", draft=draft)
        if note:
            result.reply = f"{note}\n\n{result.reply}"
        return result

    @staticmethod
    def _checkout_ready(draft: Dict[str, Any]) -> bool:
        if draft.get("fulfillment") == "retirada":
            return bool(draft.get("customer_name"))
        return draft.get("fulfillment") == "entrega" and bool(draft.get("address")) and bool(draft.get("customer_name"))

    # ── stages ────────────────────────────────────────────────────────────────

    def _add_parsed(self, draft: Dict[str, Any], matcher: CatalogMatcher, text: str) -> Optional[AssistantResult]:
        items, ambiguous = matcher.parse(text)
        for item in items:
            self._add_line(draft, item.product, item.variant_name, item.quantity)
        if ambiguous:
            tokens = _tokens(text)
            names = set().union(*(matcher._name_positions([_stem(t) for t in tokens], p) for p in ambiguous))
            quantity = next((q for i, q in enumerate(_quantity(t) for t in tokens) if q and i not in names), None) or 1
            # "Adiciona também um guaraná" with a 2L soda already in the cart: same product, new option.
            in_cart = [p for p in ambiguous if any(line["product_id"] == int(p["id"]) for line in self._lines(draft))]
            if len(in_cart) == 1:
                self._add_line(draft, in_cart[0], matcher._variant_in(in_cart[0], tokens), quantity)
                return self._after_change(draft, matcher, "")
            draft["clarify"] = {"op": "add_choice", "product_ids": [int(p["id"]) for p in ambiguous[:6]],
                                "text": text, "quantity": quantity}
            draft["stage"] = draft.get("stage") if draft.get("stage") != "confirm" else "items"
            noted = ""
            if draft["items"]:
                noted = "Anotado:\n" + "\n".join(f"• {self._label(i)}" for i in draft["items"]) + "\n\n"
            names = "\n".join(f"{i}) {p['name']}" for i, p in enumerate(ambiguous[:6], start=1))
            return AssistantResult(reply=f"{noted}Encontrei mais de uma opção. Qual delas você quer?\n{names}",
                                   draft=draft)
        if items:
            return self._after_change(draft, matcher, "")
        return None

    def _take_items(self, draft: Dict[str, Any], matcher: CatalogMatcher, text: str, starting: bool = False) -> AssistantResult:
        norm = normalize(text)
        added = self._add_parsed(draft, matcher, text)
        if added is not None:
            return added
        if draft["items"] and (_NOTHING_MORE.search(norm) or _DELIVERY.search(norm) or _PICKUP.search(norm)):
            draft["stage"] = "fulfillment"
            if _DELIVERY.search(norm) or _PICKUP.search(norm):
                return self._take_fulfillment(draft, norm, matcher, text)
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
        pending = draft.get("pending") or []
        line = pending[0] if pending else None
        product = matcher.product(line["product_id"]) if line else None
        if product is None:
            draft["pending"] = pending[1:]
            return self._next_question(draft, matcher)
        variant = matcher._variant_in(product, _tokens(text))
        if variant:
            draft["pending"] = pending[1:]
            self._add_line(draft, product, variant, line["quantity"])
            return self._after_change(draft, matcher, "")
        added = self._add_parsed(draft, matcher, text)
        if added is not None:
            return added
        return AssistantResult(reply=f"Qual opção para {product['name']}? {matcher.variant_options(product)}",
                               draft=draft)

    def _take_fulfillment(self, draft: Dict[str, Any], norm: str, matcher: CatalogMatcher, text: str = "") -> AssistantResult:
        if _PICKUP.search(norm):
            draft["fulfillment"] = "retirada"
            draft["address"] = ""
            draft["address_parts"] = {}
        elif _DELIVERY.search(norm):
            draft["fulfillment"] = "entrega"
        else:
            added = self._add_parsed(draft, matcher, text) if text else None
            return added if added is not None else self._ask_fulfillment(draft)
        if draft["fulfillment"] == "entrega" and not draft.get("address"):
            draft["stage"] = "address"
            return AssistantResult(
                reply="Qual é o endereço de entrega? Informe rua, número, bairro e cidade (complemento é opcional).",
                draft=draft,
            )
        return self._ask_name_or_confirm(draft, matcher)

    def _take_address(self, draft: Dict[str, Any], text: str, matcher: CatalogMatcher) -> AssistantResult:
        cleaned = " ".join(str(text or "").split()).strip(" .")
        norm = normalize(text)
        if _PICKUP.search(norm) and len(cleaned) < 25:
            draft["fulfillment"] = "retirada"
            draft["address_parts"] = {}
            return self._ask_name_or_confirm(draft, matcher)
        parts = dict(draft.get("address_parts") or {})
        awaiting = draft.get("address_awaiting")
        if awaiting == "number":
            if _NO_NUMBER.search(norm):
                parts["number"] = "s/n"
            elif re.fullmatch(r"(n[º°o]?\.?\s*)?\d{1,5}[A-Za-z]?", cleaned):
                parts["number"] = re.sub(r"^n[º°o]?\.?\s*", "", cleaned)
            else:
                parts.update({k: v for k, v in parse_address(text).items() if k not in parts or k == "complement"})
        elif awaiting in ("street", "neighborhood", "city") and "," not in cleaned and len(cleaned) >= 2:
            parts[awaiting] = cleaned[:120]
        else:
            parts.update({k: v for k, v in parse_address(text).items() if k not in parts or k == "complement"})
        draft["address_parts"] = parts
        missing = next((f for f in _ADDRESS_FIELDS if not parts.get(f)), None)
        if missing:
            draft["address_awaiting"] = missing
            got = ", ".join(parts[f] for f in _ADDRESS_FIELDS if parts.get(f))
            prefix = f"Anotei: {got}. " if got else ""
            return AssistantResult(reply=f"{prefix}{_ADDRESS_QUESTIONS[missing]}", draft=draft)
        draft.pop("address_awaiting", None)
        draft["address"] = format_address(parts)[:300]
        draft.pop("summary", None)
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
                draft["pending"] = []
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
            elif order.get("status") == "aguardando_loja":
                reply = (
                    f"Pedido #{order['order_number']} recebido e aguardando a confirmação da loja.\n"
                    f"Subtotal dos produtos: {order_domain.money(order['subtotal_cents'])}\n"
                    "Taxa de entrega: a confirmar pela loja\n"
                    "Total final: pendente — você recebe o valor final aqui e o pedido só vai para o preparo "
                    "depois que você aceitar."
                )
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
        if _ADDRESS_CHANGE.search(norm) and draft.get("fulfillment") == "entrega":
            draft.update({"address": "", "address_parts": {}, "stage": "address"})
            draft.pop("summary", None)
            draft.pop("address_awaiting", None)
            return AssistantResult(reply="Qual é o novo endereço? Informe rua, número, bairro e cidade.", draft=draft)
        added = self._add_parsed(draft, matcher, text)
        if added is not None:
            return added
        return AssistantResult(reply="Para confirmar o pedido responda *SIM*, ou *NÃO* para cancelar.", draft=draft)

    # ── delivery fee acceptance (orders already registered) ───────────────────

    async def _acceptance_reply(self, tenant_id: str, customer_phone: str, norm: str,
                                message_ts: Optional[datetime], dry_run: bool) -> Optional[AssistantResult]:
        pending = getattr(self.orders, "pending_acceptance", None)
        if pending is None:
            return None
        order = await pending(tenant_id, customer_phone)
        if not order:
            return None
        plain = _plain(norm)
        accept = bool(_ACCEPT.fullmatch(plain))
        refuse = plain in _NO or bool(_CANCEL.search(norm))
        if not accept and not refuse:
            return None
        values = (f"Pedido #{order['order_number']}: produtos {order_domain.money(order['subtotal_cents'])} + "
                  f"taxa de entrega {order_domain.money(order.get('delivery_fee_cents') or 0)} = "
                  f"total final {order_domain.money(order['total_cents'])}.")
        sent_at = order.get("fee_sent_at")
        if accept and message_ts is not None and isinstance(sent_at, datetime):
            lag = sent_at.replace(microsecond=0) - message_ts.replace(tzinfo=None)
            if timedelta(seconds=1) < lag < timedelta(minutes=30):
                return AssistantResult(reply=f"{values}\nResponda *ACEITO* para confirmar ou *CANCELAR*.", draft=None)
        if dry_run:
            return AssistantResult(reply=f"(Simulação) {values} Nada foi alterado.", draft=None)
        try:
            updated = await self.orders.customer_decision(
                tenant_id, order["id"], accept=accept, expected_total_cents=order["total_cents"],
            )
        except (OrderConflict, OrderError):
            return AssistantResult(reply="O valor do seu pedido mudou. Aguarde a nova mensagem da loja com o total.",
                                   draft=None)
        if updated["status"] == "confirmado":
            reply = f"Combinado! {values}\nSeu pedido foi confirmado e vai para o preparo. ✅"
        else:
            reply = f"Tudo bem, o pedido #{order['order_number']} foi cancelado."
        return AssistantResult(reply=reply, draft=None, metadata={"order_acceptance": updated["status"],
                                                                  "order_id": order["id"]})

    # ── helpers ───────────────────────────────────────────────────────────────

    def _next_question(self, draft: Dict[str, Any], matcher: CatalogMatcher) -> AssistantResult:
        # Drafts from before the pending list: lines without their option go back to pending.
        for line in list(draft["items"]):
            product = matcher.product(line["product_id"])
            if product and product.get("variants") and not line.get("variant_name"):
                draft["items"].remove(line)
                draft.setdefault("pending", []).append(line)
        for line in draft.get("pending") or []:
            product = matcher.product(line["product_id"])
            if product:
                draft["stage"] = "variant"
                return AssistantResult(
                    reply=f"Qual opção para {product['name']}? {matcher.variant_options(product)}", draft=draft
                )
        draft["stage"] = "more"
        lines = "\n".join(f"• {self._label(i)}" for i in draft["items"])
        follow = "Quer adicionar mais alguma coisa? Se não, me diga se é *entrega* ou *retirada*."
        if draft.get("fulfillment"):
            follow = "Quer adicionar mais alguma coisa? Se não, responda *NÃO*."
        return AssistantResult(reply=f"Anotado:\n{lines}\n\n{follow}", draft=draft)

    def _ask_fulfillment(self, draft: Dict[str, Any]) -> AssistantResult:
        draft["stage"] = "fulfillment"
        return AssistantResult(reply="O pedido é para *entrega* ou *retirada* na loja?", draft=draft)

    def _ask_name_or_confirm(self, draft: Dict[str, Any], matcher: CatalogMatcher) -> AssistantResult:
        if not draft.get("customer_name"):
            draft["stage"] = "name"
            return AssistantResult(reply="Em qual nome fica o pedido?", draft=draft)
        return self._summary(draft, matcher)

    def _summary(self, draft: Dict[str, Any], matcher: CatalogMatcher) -> AssistantResult:
        if draft.get("fulfillment") == "entrega" and not draft.get("address"):
            draft["stage"] = "address"
            return AssistantResult(reply="Qual é o endereço de entrega? Informe rua, número, bairro e cidade.",
                                   draft=draft)
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
        subtotal = sum(p["line_total_cents"] for p in priced)
        if draft["fulfillment"] == "entrega":
            values = (
                f"Subtotal dos produtos: {order_domain.money(subtotal)}\n"
                "Taxa de entrega: a confirmar pela loja\n"
                "Total final: pendente"
            )
            where = f"Entrega em: {draft['address']}"
            confirm = ("Responda *SIM* para enviar o pedido à loja (o total final chega depois para você aceitar) "
                       "ou *NÃO* para cancelar.")
        else:
            values = f"Total: {order_domain.money(subtotal)}"
            where = "Retirada na loja"
            confirm = "Responda *SIM* para confirmar ou *NÃO* para cancelar."
        reply = (f"Confira seu pedido:\n{lines}\n\n{values}\n{where}\nNome: {draft['customer_name']}\n\n{confirm}")
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
        def lines(key: str) -> List[Dict[str, Any]]:
            return [{"line_id": i.get("line_id") or _new_line_id(), **{k: v for k, v in dict(i).items() if k != "line_id"}}
                    for i in raw.get(key) or []]
        return {**raw, "items": lines("items"), "pending": lines("pending"),
                "address_parts": dict(raw.get("address_parts") or {})}

    @staticmethod
    def _product(matcher: CatalogMatcher, product_id: int) -> Optional[Dict[str, Any]]:
        return matcher.product(product_id)

    @staticmethod
    def _item_label(item: Dict[str, Any]) -> str:
        return OrderAssistant._label(item)

    @staticmethod
    def _menu_overview(matcher: CatalogMatcher) -> str:
        groups: Dict[str, List[str]] = {}
        for product in matcher.products:
            groups.setdefault(product.get("category_name") or "Outros", []).append(product["name"])
        lines = [f"*{cat}:* " + ", ".join(names[:8]) + ("…" if len(names) > 8 else "") for cat, names in groups.items()]
        return "\n".join(lines) + "\n\nPode mandar tudo de uma vez, com quantidade e opção (tamanho, sabor)."
