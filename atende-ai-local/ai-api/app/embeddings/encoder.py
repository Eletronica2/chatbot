import threading
import time

import torch

# Query/document prefixes each model was trained with.
_PREFIXES = {
    "google/embeddinggemma-2": ("task: search result | query: {q}", "title: {t} | text: {d}"),
    "intfloat/multilingual-e5-small": ("query: {q}", "passage: {t}. {d}"),
}


class Encoder:
    """Local text embedding model. CPU, float32 (float16 is unsafe for EmbeddingGemma)."""

    def __init__(self, model_name: str, threads: int = 4, dim: int | None = None):
        from sentence_transformers import SentenceTransformer

        if model_name not in _PREFIXES:
            raise ValueError(f"embedding model não suportado: {model_name}")
        torch.set_num_threads(threads)
        kwargs: dict = {"device": "cpu", "model_kwargs": {"dtype": torch.float32}}
        if model_name == "google/embeddinggemma-2":
            kwargs["config_kwargs"] = {"vision_config": None, "audio_config": None}
        started = time.perf_counter()
        self.model = SentenceTransformer(model_name, **kwargs)
        self.load_ms = int((time.perf_counter() - started) * 1000)
        self.model_name = model_name
        self.native_dim = self.model.get_sentence_embedding_dimension()
        self.dim = dim or self.native_dim
        self.query_tpl, self.doc_tpl = _PREFIXES[model_name]
        self._lock = threading.Lock()
        self.revision = self._revision()

    def _revision(self) -> str | None:
        try:
            cfg = self.model[0].auto_model.config
            return getattr(cfg, "_commit_hash", None)
        except Exception:
            return None

    def param_count(self) -> int:
        return sum(p.numel() for p in self.model.parameters())

    def _encode(self, texts: list[str]) -> list[list[float]]:
        with self._lock, torch.inference_mode():
            vecs = self.model.encode(
                texts,
                batch_size=16,
                normalize_embeddings=True,
                truncate_dim=self.dim if self.dim != self.native_dim else None,
                convert_to_numpy=True,
            )
        return vecs.tolist()

    def encode_queries(self, queries: list[str]) -> list[list[float]]:
        return self._encode([self.query_tpl.format(q=q) for q in queries])

    def encode_documents(self, docs: list[tuple[str, str]]) -> list[list[float]]:
        return self._encode([self.doc_tpl.format(t=t or "none", d=d) for t, d in docs])
