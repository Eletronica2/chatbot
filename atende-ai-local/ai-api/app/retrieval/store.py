import re
import uuid
from datetime import datetime, timezone

from qdrant_client import AsyncQdrantClient, models

from app.domain.models import TENANT_PATTERN
from app.retrieval import sparse
from app.retrieval.chunking import Chunk

_TENANT_RE = re.compile(TENANT_PATTERN)
_NS = uuid.UUID("6f1c0a52-5d0e-4b8e-9a51-7b3f2a8c1d10")


class TenantScopeError(ValueError):
    pass


def tenant_filter(tenant_id: str, *extra: models.Condition) -> models.Filter:
    """Every read/write goes through this: no tenant, no query."""
    if not tenant_id or not _TENANT_RE.match(tenant_id):
        raise TenantScopeError("tenant_id obrigatório para acessar a base de conhecimento")
    return models.Filter(
        must=[models.FieldCondition(key="tenant_id", match=models.MatchValue(value=tenant_id)), *extra]
    )


def point_id(tenant_id: str, document_id: str, version: int, index: int) -> str:
    return str(uuid.uuid5(_NS, f"{tenant_id}|{document_id}|{version}|{index}"))


class KnowledgeStore:
    def __init__(self, url: str, api_key: str, collection: str, dim: int, embedding_model: str):
        self.client = AsyncQdrantClient(url=url, api_key=api_key or None, timeout=30, prefer_grpc=False)
        self.collection = collection
        self.dim = dim
        self.embedding_model = embedding_model

    async def ensure_collection(self) -> dict:
        if not await self.client.collection_exists(self.collection):
            await self.client.create_collection(
                collection_name=self.collection,
                vectors_config={"dense": models.VectorParams(size=self.dim, distance=models.Distance.COSINE)},
                sparse_vectors_config={"bm25": models.SparseVectorParams(modifier=models.Modifier.IDF)},
                metadata={"embedding_model": self.embedding_model, "embedding_dim": self.dim},
            )
            await self.client.create_payload_index(
                self.collection,
                field_name="tenant_id",
                field_schema=models.KeywordIndexParams(type=models.KeywordIndexType.KEYWORD, is_tenant=True),
            )
            for name in ("document_id", "content_hash"):
                await self.client.create_payload_index(self.collection, field_name=name, field_schema=models.PayloadSchemaType.KEYWORD)
            await self.client.create_payload_index(self.collection, field_name="document_version", field_schema=models.PayloadSchemaType.INTEGER)
        info = await self.client.get_collection(self.collection)
        dense = info.config.params.vectors["dense"]
        meta = info.config.metadata or {}
        if dense.size != self.dim or meta.get("embedding_model") not in (None, self.embedding_model):
            raise RuntimeError(
                f"coleção {self.collection} configurada para {meta.get('embedding_model')}/{dense.size}d; "
                f"API usa {self.embedding_model}/{self.dim}d — não misturar vetores"
            )
        return {"points": info.points_count, "status": str(info.status), "metadata": meta}

    async def ping(self) -> bool:
        return await self.client.collection_exists(self.collection)

    async def current_version(self, tenant_id: str, document_id: str) -> int:
        flt = tenant_filter(tenant_id, models.FieldCondition(key="document_id", match=models.MatchValue(value=document_id)))
        points, _ = await self.client.scroll(self.collection, scroll_filter=flt, limit=1, with_payload=["document_version"],
                                             order_by=models.OrderBy(key="document_version", direction=models.Direction.DESC))
        return int(points[0].payload["document_version"]) if points else 0

    async def upsert_document(self, *, tenant_id: str, document_id: str, title: str, source: str,
                              version: int | None, chunks: list[Chunk], vectors: list[list[float]]) -> dict:
        tenant_filter(tenant_id)
        previous = await self.current_version(tenant_id, document_id)
        version = version or previous + 1
        now = datetime.now(timezone.utc).isoformat()
        points = []
        for chunk, vec in zip(chunks, vectors):
            idx, vals = sparse.encode_document(chunk.text)
            points.append(models.PointStruct(
                id=point_id(tenant_id, document_id, version, chunk.index),
                vector={"dense": vec, "bm25": models.SparseVector(indices=idx, values=vals)},
                payload={
                    "tenant_id": tenant_id,
                    "document_id": document_id,
                    "document_version": version,
                    "title": title,
                    "section": chunk.section,
                    "chunk_id": f"{document_id}:v{version}:{chunk.index}",
                    "chunk_index": chunk.index,
                    "content_hash": chunk.content_hash,
                    "updated_at": now,
                    "source": source,
                    "text": chunk.text,
                },
            ))
        await self.client.upsert(self.collection, points=points, wait=True)
        stale = tenant_filter(
            tenant_id,
            models.FieldCondition(key="document_id", match=models.MatchValue(value=document_id)),
        )
        stale.must_not = [models.FieldCondition(key="document_version", match=models.MatchValue(value=version))]
        removed = await self.count(stale)
        await self.client.delete(self.collection, points_selector=models.FilterSelector(filter=stale), wait=True)
        return {"document_id": document_id, "document_version": version, "previous_version": previous,
                "chunks": len(points), "stale_chunks_removed": removed}

    async def delete_documents(self, tenant_id: str, document_ids: list[str]) -> int:
        flt = tenant_filter(tenant_id, models.FieldCondition(key="document_id", match=models.MatchAny(any=document_ids)))
        n = await self.count(flt)
        await self.client.delete(self.collection, points_selector=models.FilterSelector(filter=flt), wait=True)
        return n

    async def count(self, flt: models.Filter) -> int:
        return (await self.client.count(self.collection, count_filter=flt, exact=True)).count

    async def search(self, tenant_id: str, dense_vec: list[float], query_text: str, top_k: int,
                     mode: str, min_score: float = 0.0) -> list[dict]:
        flt = tenant_filter(tenant_id)
        if mode == "hybrid":
            idx, vals = sparse.encode_query(query_text)
            prefetch = [models.Prefetch(query=dense_vec, using="dense", filter=flt, limit=top_k * 4)]
            if idx:
                prefetch.append(models.Prefetch(query=models.SparseVector(indices=idx, values=vals), using="bm25",
                                                filter=flt, limit=top_k * 4))
            res = await self.client.query_points(self.collection, prefetch=prefetch,
                                                 query=models.FusionQuery(fusion=models.Fusion.RRF),
                                                 query_filter=flt, limit=top_k, with_payload=True)
        else:
            res = await self.client.query_points(self.collection, query=dense_vec, using="dense", query_filter=flt,
                                                 limit=top_k, with_payload=True,
                                                 score_threshold=min_score or None)
        out = []
        for p in res.points:
            if p.payload.get("tenant_id") != tenant_id:
                raise TenantScopeError("resultado fora do tenant autorizado")
            out.append({"score": round(float(p.score), 4), **{k: p.payload[k] for k in (
                "tenant_id", "document_id", "document_version", "section", "chunk_id", "text", "source")}})
        return out
