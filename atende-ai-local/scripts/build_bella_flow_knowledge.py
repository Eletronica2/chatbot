"""Build Bella Massa knowledge-sync operations from the tenant's production flow (single source of truth).

Texts are copied from the flow states; the only transformation is making the price columns explicit
("R$ a / R$ b / R$ c" + the flow's own "Broto / Média / Grande" legend -> "broto R$ a, média R$ b, grande R$ c").
The IA-01 fixture documents (cardapio, regras, entrega) are retired for this tenant because they contradict the flow.

Usage: python3 atende-ai-local/scripts/build_bella_flow_knowledge.py > atende-ai-local/knowledge/pizzaria_bella_massa.sync.json
"""
import hashlib
import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
FLOW = ROOT / "flow-engine/app/flows/tenants/pizzaria_bella_massa/atendimento_pizzaria_delivery.yaml"
UPDATED_AT = "2026-10-22T00:00:00Z"
VERSION = 1
SIZES = ("broto", "média", "grande")
PRICE_LINE = re.compile(r"^\s*•\s*\*(?P<name>[^*]+)\*\s*—\s*(?P<a>R\$ [\d.,]+) / (?P<b>R\$ [\d.,]+) / (?P<c>R\$ [\d.,]+)\s*$")
EMOJI = re.compile("[\U0001F300-\U0001FAFF\u2600-\u27BF\u2B50\uFE0F]")

DOCS = [
    ("bella-flow-pizzas-tradicionais", "Pizzas tradicionais Bella Massa", ["pizzas_tradicionais"]),
    ("bella-flow-pizzas-especiais", "Pizzas especiais Bella Massa", ["pizzas_especiais"]),
    ("bella-flow-pizzas-doces", "Pizzas doces Bella Massa", ["pizzas_doces"]),
    ("bella-flow-bebidas", "Bebidas Bella Massa", ["bebidas"]),
    ("bella-flow-promocoes", "Promoções Bella Massa", ["promocoes_do_dia"]),
    ("bella-flow-horarios", "Horários Bella Massa", ["horario_funcionamento"]),
    ("bella-flow-tamanhos", "Tamanhos de pizza Bella Massa", ["pedido_tamanho"]),
    ("bella-flow-entrega-pagamento", "Entrega e pagamento Bella Massa", ["pedido_tipo_entrega", "pedido_pagamento"]),
]
RETIRED_FIXTURES = ["cardapio", "regras", "entrega"]
DROP_LINES = re.compile(r"(\{cta_pedido\}|^_\(Preços:|Quer pedir|Posso te ajudar|Quer montar|Posso montar|Posso adicionar|"
                        r"Qual promoção|Qual tamanho|Pode pedir mais|Como você vai pagar|Você prefere receber|Quase lá|"
                        r"^Ótimo!|^Que prazer)", re.IGNORECASE)


def clean(message: str) -> str:
    out = []
    for raw in message.splitlines():
        line = EMOJI.sub("", raw).replace("*", "").replace("_", "").rstrip()
        match = PRICE_LINE.match(raw)
        if match:
            prices = ", ".join(f"{size} {match[k]}" for size, k in zip(SIZES, "abc"))
            line = f"- {match['name'].strip()}: {prices}"
        if DROP_LINES.search(EMOJI.sub("", raw).replace("*", "").strip()):
            continue
        out.append(line.strip())
    text = "\n".join(out)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def main() -> None:
    flow = yaml.safe_load(FLOW.read_text(encoding="utf-8"))
    ops = []
    for doc_id, title, states in DOCS:
        body = "\n\n".join(clean(flow["states"][s]["message"]) for s in states)
        if "pizzas_" in states[0]:
            body += "\n\nTamanhos: broto 25 cm, média 35 cm, grande 45 cm."
        content = f"# {title}\n\n{body}\n"
        ops.append({"op": "upsert", "document_id": doc_id, "version": VERSION, "title": title, "content": content,
                    "content_hash": hashlib.sha256(content.encode("utf-8")).hexdigest(), "updated_at": UPDATED_AT,
                    "status": "active", "content_type": "markdown"})
    for doc_id in RETIRED_FIXTURES:
        ops.append({"op": "delete", "document_id": doc_id, "version": VERSION, "updated_at": UPDATED_AT, "status": "deleted"})
    json.dump({"tenant_id": "pizzaria_bella_massa", "source": str(FLOW.relative_to(ROOT)), "operations": ops},
              sys.stdout, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
