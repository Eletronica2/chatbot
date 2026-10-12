"""Ingestion-time neutralization of instruction-like lines embedded in tenant documents."""

import re

from app.retrieval.text import strip_accents

_INSTRUCTION_PATTERNS = [
    r"\b(ignore|ignora|ignorar|desconsidere|desconsiderar|esqueca|esquecer)\b.{0,40}\b(instruc|regra|orientac|prompt|anterior)",
    r"\b(ignore|disregard|forget)\b.{0,40}\b(instruction|rule|previous|prompt)",
    r"\b(voce agora e|a partir de agora voce|you are now|act as|aja como|finja ser)\b",
    r"\b(system prompt|prompt do sistema|mensagem do sistema|developer mode|modo desenvolvedor)\b",
    r"\b(diga|responda|informe|fale)\b.{0,20}\b(ao cliente|aos clientes|para o cliente)\b",
    r"<\s*/?\s*(system|assistant|documento|instructions?)\s*>",
]
_RE = re.compile("|".join(_INSTRUCTION_PATTERNS))


def strip_instructions(content: str) -> tuple[str, int]:
    kept, removed = [], 0
    for line in content.split("\n"):
        if _RE.search(strip_accents(line.lower())):
            removed += 1
            continue
        kept.append(line)
    return "\n".join(kept), removed
