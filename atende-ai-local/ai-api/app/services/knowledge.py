import asyncio

from app.domain.models import KnowledgeDocument
from app.embeddings.encoder import Encoder
from app.retrieval.chunking import chunk_document
from app.retrieval.sanitize import strip_instructions
from app.retrieval.store import KnowledgeStore


class KnowledgeService:
    def __init__(self, encoder: Encoder, store: KnowledgeStore):
        self.encoder = encoder
        self.store = store

    async def upsert(self, tenant_id: str, doc: KnowledgeDocument) -> dict:
        content, removed = strip_instructions(doc.content)
        chunks = chunk_document(doc.title, content, doc.content_type, max_chars=600)
        if not chunks:
            return {"document_id": doc.document_id, "chunks": 0, "skipped": "empty", "instruction_lines_removed": removed}
        vectors = await asyncio.to_thread(self.encoder.encode_documents, [(c.section, c.text) for c in chunks])
        result = await self.store.upsert_document(
            tenant_id=tenant_id, document_id=doc.document_id, title=doc.title, source=doc.source,
            version=doc.document_version, chunks=chunks, vectors=vectors,
        )
        return {**result, "instruction_lines_removed": removed}

    async def delete(self, tenant_id: str, document_ids: list[str]) -> int:
        return await self.store.delete_documents(tenant_id, document_ids)
