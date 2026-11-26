"""Regras de conteúdo para modelos WhatsApp (alinhadas à Meta)."""
from __future__ import annotations

import re

_VAR_RE = re.compile(r"\{\{(\d+|[a-zA-Z_][a-zA-Z0-9_]*)\}\}")
_EMOJI_RE = re.compile(
    r"[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0000FE00-\U0000FEFF"
    r"\U0001F900-\U0001F9FF\U0000200D\U0000203C\U00002049]"
)
_MARKDOWN_RE = re.compile(r"(\*[^*]+\*|_[^_]+_|~[^~]+~|```)")
_NEWLINE_RE = re.compile(r"[\r\n]")


def _vars(text: str) -> list[str]:
    return _VAR_RE.findall(text or "")


def validate_header_text(text: str | None) -> str | None:
    if not text or not text.strip():
        return None
    t = text.strip()
    if len(t) > 60:
        return "Cabeçalho: máximo 60 caracteres."
    if _NEWLINE_RE.search(t):
        return "Cabeçalho: não permite quebra de linha."
    if _EMOJI_RE.search(t):
        return "Cabeçalho: emojis não são permitidos."
    if _MARKDOWN_RE.search(t):
        return "Cabeçalho: formatação (*, _, ~, ```) não é permitida."
    if len(_vars(t)) > 1:
        return "Cabeçalho: no máximo 1 variável."
    return None


def validate_footer_text(text: str | None) -> str | None:
    if not text or not text.strip():
        return None
    t = text.strip()
    if len(t) > 60:
        return "Rodapé: máximo 60 caracteres."
    if _NEWLINE_RE.search(t):
        return "Rodapé: não permite quebra de linha."
    if _EMOJI_RE.search(t):
        return "Rodapé: emojis não são permitidos."
    if _vars(t):
        return "Rodapé: variáveis não são permitidas."
    if _MARKDOWN_RE.search(t):
        return "Rodapé: formatação não é permitida."
    return None


def validate_body_text(text: str, *, examples: list[str] | None = None) -> str | None:
    if not text or not text.strip():
        return "Corpo: obrigatório."
    t = text.strip("\n")
    if len(t) > 1024:
        return "Corpo: máximo 1.024 caracteres."
    vars_found = _vars(t)
    if vars_found:
        numbered = [v for v in vars_found if v.isdigit()]
        if numbered:
            nums = sorted(int(x) for x in numbered)
            if nums != list(range(1, len(nums) + 1)):
                return "Corpo: use variáveis numeradas sequenciais ({{1}}, {{2}}…)."
        ex = [x.strip() for x in (examples or []) if x and str(x).strip()]
        if len(ex) != len(vars_found):
            return (
                f"Corpo: informe {len(vars_found)} exemplo(s) para aprovação "
                f"({len(ex)} informado(s)), separados por |."
            )
    return None


def validate_button_label(text: str, *, field: str = "Botão") -> str | None:
    t = (text or "").strip()
    if not t:
        return f"{field}: texto obrigatório."
    if len(t) > 25:
        return f"{field}: máximo 25 caracteres."
    if _EMOJI_RE.search(t):
        return f"{field}: emojis não são permitidos."
    if _vars(t):
        return f"{field}: variáveis não são permitidas."
    if _MARKDOWN_RE.search(t):
        return f"{field}: formatação não é permitida."
    return None