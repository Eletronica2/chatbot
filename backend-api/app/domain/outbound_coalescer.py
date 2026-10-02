"""Join text fragments of one AI turn into as few outbound messages as possible.

Only plain text is coalesced; media, templates and interactive buttons keep
their own messages because WhatsApp cannot merge them. Text longer than the
WhatsApp limit is the only reason a turn yields more than one message.
"""
from __future__ import annotations

from dataclasses import dataclass

WHATSAPP_TEXT_LIMIT = 4096


@dataclass(frozen=True)
class CoalescedText:
    messages: tuple[str, ...]
    parts_before: int
    parts_after: int

    @property
    def text(self) -> str:
        return self.messages[0] if self.messages else ""


def coalesce_text_parts(parts: list[str] | tuple[str, ...], *, limit: int = WHATSAPP_TEXT_LIMIT) -> CoalescedText:
    cleaned = [p.strip() for p in parts if isinstance(p, str) and p.strip()]
    chunks: list[str] = []
    current = ""
    for part in cleaned:
        candidate = f"{current}\n\n{part}" if current else part
        if len(candidate) <= limit:
            current = candidate
            continue
        if current:
            chunks.append(current)
        while len(part) > limit:
            chunks.append(part[:limit])
            part = part[limit:]
        current = part
    if current:
        chunks.append(current)
    return CoalescedText(tuple(chunks), len(parts), len(chunks))
