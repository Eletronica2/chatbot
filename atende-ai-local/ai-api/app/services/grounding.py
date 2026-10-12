"""Existence-claim grounding: "temos X" / "não temos X" is only allowed when X is in the authorized context.

The authorized context is business data, retrieved documents, flow state and tenant profile. The
customer's own message is deliberately NOT authorized context: repeating the question back as a fact
("Sim, temos Wi-Fi" / "Não, não temos Wi-Fi") is exactly what the model must not do.
"""

import re

from app.retrieval.text import strip_accents

_VERBS = (
    r"temos|tem|possuimos|possui|oferecemos|oferece|disponibilizamos|disponibiliza|aceitamos|aceita|"
    r"fazemos|faz|vendemos|vende|servimos|serve|contamos com|conta com|dispomos de|trabalhamos com|"
    r"ha|existe|existem"
)
_CLAIM_RE = re.compile(rf"\b(?P<verb>{_VERBS})\b\s+(?P<obj>[^.!?;:\n]{{1,60}})")
_SUBJECT_YOU = {"voce", "vc", "vcs", "voces", "senhor", "senhora"}

_STOP = {
    "a", "o", "as", "os", "um", "uma", "uns", "umas", "de", "da", "do", "das", "dos", "em", "no", "na", "nos", "nas",
    "e", "ou", "com", "sem", "para", "pra", "pro", "por", "que", "se", "sim", "nao", "sim,", "isso", "essa", "esse",
    "este", "esta", "aqui", "ai", "la", "tambem", "ainda", "sempre", "hoje", "agora", "mais", "menos", "muito", "muita",
    "muitos", "muitas", "varias", "varios", "diversas", "diversos", "algum", "alguma", "alguns", "algumas", "nenhum",
    "nenhuma", "todo", "toda", "todos", "todas", "seu", "sua", "seus", "suas", "nosso", "nossa", "nossos", "nossas",
    "voce", "voces", "cliente", "clientes", "disponivel", "disponiveis", "sim", "so", "apenas", "somente", "bem",
    "otimo", "otima", "otimos", "otimas", "delicioso", "deliciosa", "deliciosos", "deliciosas", "gostoso", "gostosa",
    "delicia", "claro", "certo", "certamente", "normalmente", "geralmente", "tudo", "nada", "ja", "e", "eh",
}
# Generic nouns that do not assert the existence of a specific amenity/product.
_GENERIC = {
    "informacao", "informacoes", "opcao", "opcoes", "sabor", "sabores", "duvida", "duvidas", "pedido", "pedidos",
    "problema", "problemas", "certeza", "detalhe", "detalhes", "dado", "dados", "cardapio", "equipe", "atendimento",
    "atendente", "atendentes", "ajuda", "previsao", "item", "itens", "produto", "produtos",
}
_PAYMENT_HINTS = {"vale", "pix", "cartao", "credito", "debito", "dinheiro", "boleto", "cheque", "ticket", "sodexo",
                  "alelo", "vr", "va", "pagamento", "pagamentos", "bitcoin", "cripto", "picpay", "transferencia"}


def _tokens(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", strip_accents(text.lower()))


def _stem(token: str) -> str:
    return token[:5] if len(token) > 5 else token


def context_stems(context_texts: list[str]) -> set[str]:
    return {_stem(t) for text in context_texts for t in _tokens(text)}


def unsupported_existence_claims(text: str, authorized_context: list[str], closed_payment_list: bool = False) -> list[str]:
    """Return the objects of existence claims whose head noun is absent from the authorized context."""
    ctx = context_stems(authorized_context)
    normalized = strip_accents(text.lower())
    violations = []
    for m in _CLAIM_RE.finditer(normalized):
        preceding = _tokens(normalized[max(0, m.start() - 30):m.start()])[-2:]
        if preceding and preceding[-1] in _SUBJECT_YOU:
            continue
        negated = "nao" in preceding
        content = [t for t in _tokens(m.group("obj")) if t not in _STOP and not t.isdigit()]
        if not content or content[0] in _GENERIC:
            continue
        head = content[0]
        if all(_stem(t) in ctx for t in content[:3] if t not in _GENERIC):
            continue
        if negated and m.group("verb").startswith("aceit") and closed_payment_list and head in _PAYMENT_HINTS:
            continue
        violations.append(" ".join(content[:3]))
    return violations
