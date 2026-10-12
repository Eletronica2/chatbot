"""Structured business data (sent by the Atende Ai backend) and the deterministic response level."""

import re
from dataclasses import dataclass, field

from app.retrieval.text import STOPWORDS, content_tokens, normalize, tokens

PRICE_WORDS = {"quanto", "custa", "custam", "preco", "precos", "valor", "sai", "fica", "cobra", "cobram"}
PAYMENT_WORDS = {"pagamento", "pagar", "pago", "aceita", "aceitam", "aceitar", "forma", "formas", "pix", "cartao",
                 "credito", "debito", "dinheiro", "vale", "refeicao", "alimentacao", "boleto"}
DELIVERY_WORDS = {"entrega", "entregar", "entregas", "delivery", "bairro", "taxa", "frete", "levam", "leva"}
HOURS_WORDS = {"horario", "horarios", "abre", "abrem", "fecha", "fecham", "funciona", "funcionam", "aberto", "aberta",
               "horas", "hora", "ate", "hoje", "amanha", "domingo", "segunda", "sabado", "feriado"}
HANDOFF_PATTERNS = {
    "order_cancel": re.compile(r"\bcancel\w*"),
    "order_change": re.compile(r"\b(alterar|mudar|trocar|modificar)\b.*\bpedido\b|\bpedido\b.*\b(alterar|mudar|trocar)\b"),
    "order_create": re.compile(r"\b(quero|queria|gostaria de|vou querer|manda|me ve|faz)\b.*\b(pedir|pedido|uma|um|duas|dois)\b"),
    "order_status": re.compile(r"\b(meu pedido|minha pizza|meu pastel|status do pedido|cade|ja saiu|saiu pra entrega"
                               r"|nao chegou|ta demorando|esta demorando|atrasad\w*)\b"),
}
FILLER = {"sai", "fica", "cobra", "hoje", "agora", "ai", "vcs", "voces", "voce", "pizza", "pizzas", "pastel", "pasteis",
          "favor", "moco", "moca", "amigo", "pra", "pro", "ate", "que", "horas", "uma", "um", "tambem", "e"}


def brl(value: float) -> str:
    s = f"{value:,.2f}"
    return "R$ " + s.replace(",", "X").replace(".", ",").replace("X", ".")


def price_cents_in(text: str) -> set[int]:
    out = set()
    for m in re.finditer(r"R\$\s*(\d{1,3}(?:\.\d{3})*|\d+)(?:,(\d{2}))?", text):
        out.add(int(m.group(1).replace(".", "")) * 100 + int(m.group(2) or 0))
    return out


def numbers_in(text: str) -> set[str]:
    """Canonical numbers in a text ('65,00' -> '65', '1.234,50' -> '1234.5', '18h' -> '18')."""
    out = set()
    for m in re.finditer(r"\d+(?:\.\d{3})*(?:,\d+)?|\d+(?:\.\d+)?", text):
        raw = m.group(0)
        if "," in raw:
            raw = raw.replace(".", "").replace(",", ".")
        try:
            value = float(raw)
        except ValueError:
            continue
        out.add(f"{value:g}")
    return out


@dataclass
class Business:
    name: str = ""
    products: list[dict] = field(default_factory=list)
    hours: list[dict] = field(default_factory=list)
    hours_text: str = ""
    delivery_served: list[dict] = field(default_factory=list)
    delivery_not_served: list[str] = field(default_factory=list)
    payment_methods: list[str] = field(default_factory=list)
    promotions: list[dict] = field(default_factory=list)

    @classmethod
    def from_context(cls, ctx: dict) -> "Business":
        delivery = ctx.get("delivery") or {}
        return cls(
            name=str(ctx.get("business_name", "")),
            products=[p for p in ctx.get("products", []) if isinstance(p, dict) and "name" in p],
            hours=list(ctx.get("hours", [])),
            hours_text=str(ctx.get("hours_text", "")),
            delivery_served=list(delivery.get("neighborhoods", [])),
            delivery_not_served=list(delivery.get("not_served", [])),
            payment_methods=list(ctx.get("payment_methods", [])),
            promotions=list(ctx.get("promotions", [])),
        )

    def is_empty(self) -> bool:
        return not (self.products or self.hours or self.hours_text or self.delivery_served
                    or self.delivery_not_served or self.payment_methods or self.promotions)

    def known_prices(self) -> set[int]:
        cents = set()
        for p in self.products:
            if p.get("price") is not None:
                cents.add(round(float(p["price"]) * 100))
        for n in self.delivery_served:
            if n.get("fee") is not None:
                cents.add(round(float(n["fee"]) * 100))
        for promo in self.promotions:
            if promo.get("price") is not None:
                cents.add(round(float(promo["price"]) * 100))
        return cents

    def hours_line(self) -> str:
        if self.hours:
            return "; ".join(
                f"{h['days']}: fechado" if str(h.get("open", "")).lower() == "fechado"
                else f"{h['days']}: {h['open']} às {h['close']}"
                for h in self.hours
            )
        return self.hours_text

    def render(self) -> str:
        lines = []
        if self.name:
            lines.append(f"Empresa: {self.name}")
        if self.products:
            lines.append("Produtos (preço oficial):")
            for p in self.products:
                status = "" if p.get("available", True) else " — INDISPONÍVEL no momento"
                price = brl(float(p["price"])) if p.get("price") is not None else "sem preço cadastrado"
                lines.append(f"- {p['name']}: {price}{status}")
        if self.hours_line():
            lines.append(f"Horário de funcionamento: {self.hours_line()}")
        if self.delivery_served:
            served = ", ".join(f"{n['name']} (taxa {brl(float(n['fee']))})" if n.get("fee") is not None else n["name"]
                               for n in self.delivery_served)
            lines.append(f"Entrega nos bairros: {served}")
        if self.delivery_not_served:
            lines.append(f"NÃO entrega em: {', '.join(self.delivery_not_served)}")
        if self.payment_methods:
            lines.append(f"Formas de pagamento aceitas: {', '.join(self.payment_methods)}")
        if self.promotions:
            lines.append("Promoções vigentes: " + "; ".join(
                f"{p['title']}" + (f" ({brl(float(p['price']))})" if p.get("price") is not None else "") for p in self.promotions))
        else:
            lines.append("Promoções vigentes: nenhuma cadastrada")
        return "\n".join(lines)


_FEMININE_PLACES = {"vila", "zona", "cidade", "praia", "rua", "avenida", "chacara", "colonia", "fazenda", "lagoa",
                    "serra", "regiao", "area", "comunidade", "estrada", "quadra"}
_METHOD_LABEL = {"pix": "PIX", "credito": "cartão de crédito", "debito": "cartão de débito", "dinheiro": "dinheiro",
                 "boleto": "boleto"}


def place_with_article(name: str) -> str:
    first = normalize(name).split(" ")[0] if name.strip() else ""
    return f"{'na' if first in _FEMININE_PLACES else 'no'} {name}"


def _product_tokens(p: dict) -> set[str]:
    names = [p["name"], *p.get("aliases", [])]
    return {t for n in names for t in content_tokens(n)}


def match_products(message: str, products: list[dict]) -> list[tuple[float, dict]]:
    msg = set(tokens(message))
    scored = []
    for p in products:
        toks = {t for t in content_tokens(p["name"])}
        alias_hit = any(set(content_tokens(a)) <= msg for a in p.get("aliases", []) if content_tokens(a))
        if not toks:
            continue
        score = 1.0 if alias_hit else len(toks & msg) / len(toks)
        if score > 0:
            scored.append((score, p))
    scored.sort(key=lambda x: -x[0])
    return scored


@dataclass
class Deterministic:
    text: str
    intents: list[str]


def detect_handoff(message: str) -> str | None:
    norm = normalize(message)
    for reason, pattern in HANDOFF_PATTERNS.items():
        if pattern.search(norm):
            return reason
    return None


HANDOFF_TEXT = {
    "order_cancel": "Entendi que você quer cancelar. Vou encaminhar para a nossa equipe confirmar o cancelamento, tudo bem?",
    "order_change": "Entendi que você quer alterar o pedido. Vou encaminhar para a nossa equipe confirmar a alteração.",
    "order_create": "Ótimo! Vou encaminhar seu pedido para a nossa equipe confirmar os itens, o valor e a entrega.",
    "order_status": "Vou verificar o status do seu pedido com a nossa equipe e já te retorno.",
}


def answer_deterministic(message: str, biz: Business) -> Deterministic | None:
    """Level 1: answer only when every part of the question is covered by structured data."""
    if biz.is_empty():
        return None
    msg_tokens = content_tokens(message)
    msg_set = set(tokens(message))
    if not msg_tokens:
        return None
    covered: set[str] = set(FILLER)
    answers: list[str] = []
    intents: list[str] = []

    if msg_set & PRICE_WORDS and biz.products:
        ranked = match_products(message, biz.products)
        if not ranked or ranked[0][0] < 0.6 or (len(ranked) > 1 and ranked[1][0] == ranked[0][0]):
            return None
        product = ranked[0][1]
        if product.get("price") is None:
            return None
        if not product.get("available", True):
            answers.append(f"{product['name']} está indisponível no momento.")
        else:
            answers.append(f"{product['name']} custa {brl(float(product['price']))}.")
        covered |= PRICE_WORDS | _product_tokens(product)
        intents.append("price")

    if msg_set & {"pix", "cartao", "credito", "debito", "dinheiro", "pagamento", "pagar", "boleto"} and biz.payment_methods:
        methods_norm = {normalize(m): m for m in biz.payment_methods}
        asked = [t for t in ("pix", "credito", "debito", "dinheiro", "boleto") if t in msg_set]
        if asked:
            yes = [t for t in asked if any(t in k for k in methods_norm)]
            no = [t for t in asked if t not in yes]
            parts = []
            if yes:
                parts.append("Sim, aceitamos " + ", ".join(_METHOD_LABEL[t] for t in yes) + ".")
            if no:
                parts.append("Não aceitamos " + ", ".join(_METHOD_LABEL[t] for t in no)
                             + f". Formas aceitas: {', '.join(biz.payment_methods)}.")
            answers.append(" ".join(parts))
        else:
            answers.append(f"Aceitamos: {', '.join(biz.payment_methods)}.")
        covered |= PAYMENT_WORDS
        intents.append("payment")

    if msg_set & DELIVERY_WORDS and (biz.delivery_served or biz.delivery_not_served):
        served = {normalize(n["name"]): n for n in biz.delivery_served}
        hit = [(k, v) for k, v in served.items() if set(k.split()) <= msg_set]
        miss = [n for n in biz.delivery_not_served if set(normalize(n).split()) <= msg_set]
        if hit:
            k, n = hit[0]
            fee = f" A taxa de entrega é {brl(float(n['fee']))}." if n.get("fee") is not None else ""
            answers.append(f"Sim, entregamos {place_with_article(n['name'])}.{fee}")
            covered |= set(k.split())
        elif miss:
            answers.append(f"Infelizmente não entregamos {place_with_article(miss[0])}.")
            covered |= set(normalize(miss[0]).split())
        else:
            return None
        covered |= DELIVERY_WORDS
        intents.append("delivery")

    if msg_set & {"horario", "horarios", "abre", "abrem", "fecha", "fecham", "funciona", "funcionam", "aberto", "aberta"} and biz.hours_line():
        answers.append(f"Nosso horário de funcionamento: {biz.hours_line()}.")
        covered |= HOURS_WORDS
        intents.append("hours")

    if not answers:
        return None
    leftover = [t for t in msg_tokens if t not in covered and t not in STOPWORDS and not t.isdigit()]
    if leftover:
        return None
    return Deterministic(text=" ".join(answers), intents=intents)
