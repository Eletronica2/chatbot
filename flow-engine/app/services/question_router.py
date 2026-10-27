"""Detects specific customer questions that a keyword transition would answer with a generic screen.

Used only by flows that opt in with `prefer_ai_for_specific_questions: true`. A message is a specific question when it
is phrased as a question, is not a navigation request ("quero ver o cardápio"), and still has at least one concrete
term after removing generic words — "Quanto custa a pizza de calabresa?" keeps "calabresa", "Qual o horário?" keeps
nothing, so only the first leaves the deterministic path. Input is already lowercased and accent-free.
"""
from __future__ import annotations

import re
from typing import Iterable

_QUESTION_STARTS = (
    "quanto", "quantos", "quantas", "qual", "quais", "tem", "voces tem", "vcs tem", "vc tem", "voce tem", "tens",
    "aceita", "aceitam", "faz", "fazem", "entrega", "entregam", "como", "onde", "quando", "pode", "posso", "existe",
    "ha", "vende", "vendem", "serve", "servem", "oferece", "oferecem", "e possivel", "da pra", "da para",
    "voces", "vcs", "vc", "voce",
)

_NAVIGATION = (
    "ver o cardapio", "ver cardapio", "ver o menu", "ver menu", "mostra o cardapio", "mostrar o cardapio",
    "manda o cardapio", "mandar o cardapio", "me manda o cardapio", "envia o cardapio", "enviar o cardapio",
    "cardapio completo", "abrir o cardapio", "quero ver",
)

# Words that never make a question specific on their own (articles, pronouns, question words, topic names that a
# flow screen already answers in full).
_GENERIC = set("""
a o as os um uma uns umas de da do das dos em no na nos nas e ou que se me te lhe nos pra para por com sem ao aos
voce voces vc vcs tu eu ele ela eles elas meu minha seu sua nosso nossa isso isto aqui ai la ja agora hoje ainda
quanto quantos quantas qual quais como onde quando quem porque pq tem tens tem ha existe sao e eh esta estao
custa custam custo preco precos valor valores fica ficam sai saem cobra cobram
aceita aceitam faz fazem entrega entregam vende vendem serve servem oferece oferecem pode posso podem
pizza pizzas cardapio menu sabor sabores opcao opcoes tipo tipos item itens produto produtos
horario horarios funciona funcionam funcionamento abre abrem fecha fecham aberto aberta
promocao promocoes oferta ofertas desconto descontos combo combos bebida bebidas
pedido pedidos atendimento delivery
algum alguma alguns algumas tudo todo toda todos todas mais menos muito pouco
oi ola bom boa dia tarde noite tudo bem obrigado obrigada favor pf pfv por gostaria queria quero saber
""".split())

_WORD_RE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")


def _starts_like_question(text: str) -> bool:
    return any(text == q or text.startswith(q + " ") for q in _QUESTION_STARTS)


def is_specific_question(text: str, extra_generic: Iterable[str] = ()) -> bool:
    text = (text or "").strip()
    if not text or len(text) > 300:
        return False
    if not ("?" in text or _starts_like_question(text)):
        return False
    if any(phrase in text for phrase in _NAVIGATION):
        return False
    generic = _GENERIC | {w.strip().lower() for w in extra_generic if isinstance(w, str)}
    content = [w for w in _WORD_RE.findall(text) if w not in generic and not w.isdigit() and len(w) >= 3]
    return bool(content)
