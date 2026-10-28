"""Build local-AI knowledge documents from a published flow's optional ``knowledge`` section.

    knowledge:
      price_columns: [broto, média, grande]   # "R$ a / R$ b / R$ c" lines become "broto R$ a, média R$ b, ..."
      retire: [cardapio]                        # documents to remove from the tenant knowledge base
      documents:
        - id: bella-flow-pizzas-tradicionais
          title: Pizzas tradicionais Bella Massa
          states: [pizzas_tradicionais]
          append: "Tamanhos: broto 25 cm, média 35 cm, grande 45 cm."

Texts are copied from the flow states (emoji/markup and call-to-action lines removed), so the flow stays the
single source of truth for what the AI knows.
"""
from __future__ import annotations

import re
from typing import Any, Dict, List, Tuple

import yaml

_EMOJI = re.compile("[\U0001F300-\U0001FAFF\u2600-\u27BF\u2B50\uFE0F]")
_DROP_LINES = re.compile(
    r"(\{cta_pedido\}|^_\(Preços:|Quer pedir|Posso te ajudar|Quer montar|Posso montar|Posso adicionar|"
    r"Qual promoção|Qual tamanho|Pode pedir mais|Como você vai pagar|Você prefere receber|Quase lá|"
    r"^Ótimo!|^Que prazer)",
    re.IGNORECASE,
)
_DOC_ID = re.compile(r"^[A-Za-z0-9_\-.:]{1,128}$")
MAX_DOCUMENTS = 40


class FlowKnowledgeError(ValueError):
    pass


def _price_line(columns: List[str]) -> re.Pattern[str] | None:
    if not columns:
        return None
    prices = r" / ".join(rf"(?P<p{i}>R\$ [\d.,]+)" for i in range(len(columns)))
    return re.compile(rf"^\s*•\s*\*(?P<name>[^*]+)\*\s*—\s*{prices}\s*$")


def clean(message: str, price_line: re.Pattern[str] | None, columns: List[str]) -> str:
    out = []
    for raw in str(message or "").splitlines():
        line = _EMOJI.sub("", raw).replace("*", "").replace("_", "").rstrip()
        match = price_line.match(raw) if price_line else None
        if match:
            prices = ", ".join(f"{column} {match[f'p{i}']}" for i, column in enumerate(columns))
            line = f"- {match['name'].strip()}: {prices}"
        if _DROP_LINES.search(_EMOJI.sub("", raw).replace("*", "").strip()):
            continue
        out.append(line.strip())
    return re.sub(r"\n{3,}", "\n\n", "\n".join(out)).strip()


def build_documents(yaml_content: str) -> Tuple[List[Dict[str, str]], List[str]]:
    """Returns (documents[{document_id,title,content}], retired_document_ids). Empty when no knowledge section."""
    try:
        data = yaml.safe_load(yaml_content) or {}
    except yaml.YAMLError as exc:
        raise FlowKnowledgeError(f"YAML inválido: {exc}") from exc
    section = data.get("knowledge") if isinstance(data, dict) else None
    if not isinstance(section, dict):
        return [], []
    states = data.get("states") or {}
    columns = [str(c) for c in section.get("price_columns") or []]
    price_line = _price_line(columns)
    documents: List[Dict[str, str]] = []
    for entry in (section.get("documents") or [])[:MAX_DOCUMENTS]:
        doc_id = str((entry or {}).get("id") or "")
        title = str((entry or {}).get("title") or "").strip()
        if not _DOC_ID.match(doc_id) or not title:
            raise FlowKnowledgeError("cada documento de knowledge precisa de id válido e title")
        names = entry.get("states") or []
        missing = [name for name in names if name not in states]
        if missing:
            raise FlowKnowledgeError(f"knowledge {doc_id}: estados inexistentes {missing}")
        body = "\n\n".join(clean(states[name].get("message") or "", price_line, columns) for name in names)
        if entry.get("append"):
            body += f"\n\n{str(entry['append']).strip()}"
        documents.append({"document_id": doc_id, "title": title, "content": f"# {title}\n\n{body}\n"})
    retired = [str(item) for item in section.get("retire") or [] if _DOC_ID.match(str(item))]
    return documents, retired
