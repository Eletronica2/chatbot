import zlib
from collections import Counter

from app.retrieval.text import content_tokens

# BM25 term-frequency saturation; IDF is applied server-side by Qdrant (modifier=idf).
K1 = 1.2
B = 0.75
AVG_DOC_LEN = 60.0


def _term_id(term: str) -> int:
    return zlib.crc32(term.encode("utf-8"))


def _merge(indices: list[int], values: list[float]) -> tuple[list[int], list[float]]:
    acc: dict[int, float] = {}
    for i, v in zip(indices, values):
        acc[i] = acc.get(i, 0.0) + v
    return list(acc.keys()), list(acc.values())


def encode_document(text: str) -> tuple[list[int], list[float]]:
    toks = content_tokens(text)
    if not toks:
        return [], []
    tf = Counter(toks)
    norm = K1 * (1 - B + B * len(toks) / AVG_DOC_LEN)
    return _merge([_term_id(t) for t in tf], [f * (K1 + 1) / (f + norm) for f in tf.values()])


def encode_query(text: str) -> tuple[list[int], list[float]]:
    toks = set(content_tokens(text))
    return _merge([_term_id(t) for t in toks], [1.0] * len(toks))
