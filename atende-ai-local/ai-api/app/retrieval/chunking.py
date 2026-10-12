import hashlib
import re
from dataclasses import dataclass

_HEADING_RE = re.compile(r"^(#{1,4})\s+(.+?)\s*#*\s*$")


@dataclass
class Chunk:
    index: int
    section: str
    text: str

    @property
    def content_hash(self) -> str:
        return hashlib.sha256(self.text.encode("utf-8")).hexdigest()


def _sanitize(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _split_block(body: str, max_chars: int) -> list[str]:
    """Split an oversized section on paragraph, then line boundaries, never mid-line."""
    if len(body) <= max_chars:
        return [body]
    units: list[str] = []
    for para in body.split("\n\n"):
        if len(para) <= max_chars:
            units.append(para)
        else:
            units.extend(line for line in para.split("\n") if line.strip())
    out: list[str] = []
    current = ""
    for unit in units:
        candidate = f"{current}\n{unit}" if current else unit
        if len(candidate) > max_chars and current:
            out.append(current)
            current = unit
        else:
            current = candidate
    if current:
        out.append(current)
    return out


def chunk_document(title: str, content: str, content_type: str = "markdown", max_chars: int = 900) -> list[Chunk]:
    """Structure-aware chunking: one chunk per (sub)section, keeping the heading path as context."""
    content = _sanitize(content)
    sections: list[tuple[str, list[str]]] = []
    path: list[tuple[int, str]] = []
    current_lines: list[str] = []
    current_section = title

    def flush():
        body = "\n".join(current_lines).strip()
        if body:
            sections.append((current_section, body))

    for line in content.split("\n"):
        m = _HEADING_RE.match(line) if content_type == "markdown" else None
        if m:
            flush()
            current_lines = []
            level = len(m.group(1))
            path = [(lvl, name) for lvl, name in path if lvl < level] + [(level, m.group(2).strip())]
            current_section = " > ".join([title] + [name for _, name in path if name != title])
        else:
            current_lines.append(line)
    flush()

    chunks: list[Chunk] = []
    for section, body in sections:
        for piece in _split_block(body, max_chars):
            chunks.append(Chunk(index=len(chunks), section=section, text=f"[{section}]\n{piece.strip()}"))
    return chunks
