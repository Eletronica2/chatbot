from typing import Any, Literal

from pydantic import BaseModel, Field

TENANT_PATTERN = r"^[a-z0-9][a-z0-9_\-]{1,63}$"


class HistoryMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(max_length=4000)


class RespondOptions(BaseModel):
    model: str | None = None
    max_tokens: int | None = Field(None, ge=16, le=512)
    temperature: float | None = Field(None, ge=0.0, le=1.0)
    num_ctx: int | None = Field(None, ge=1024, le=8192)
    retrieval_mode: Literal["dense", "hybrid"] | None = None
    allow_deterministic: bool = True
    deadline_ms: int | None = Field(None, ge=1000, le=180_000)


class RespondRequest(BaseModel):
    request_id: str = Field(min_length=1, max_length=64)
    tenant_id: str | None = Field(None, max_length=64)
    conversation_id: str | None = Field(None, max_length=64)
    message: str = Field(min_length=1, max_length=4000)
    recent_history: list[HistoryMessage] = Field(default_factory=list, max_length=50)
    flow_context: dict[str, Any] = Field(default_factory=dict)
    business_context: dict[str, Any] = Field(default_factory=dict)
    options: RespondOptions = Field(default_factory=RespondOptions)


class Usage(BaseModel):
    prompt_tokens: int = 0
    completion_tokens: int = 0


class Timings(BaseModel):
    queue_ms: int = 0
    retrieval_ms: int = 0
    load_ms: int = 0
    first_token_ms: int | None = None
    generation_ms: int = 0
    tokens_per_s: float | None = None


class RetrievalInfo(BaseModel):
    documents_used: int = 0
    chunks: list[dict[str, Any]] = Field(default_factory=list)
    mode: str | None = None


class Action(BaseModel):
    type: str
    reason: str


class RespondResponse(BaseModel):
    request_id: str
    tenant_id: str
    text: str
    language: str = "pt-BR"
    model: str | None
    level: Literal["deterministic", "rag", "llm", "handoff", "fallback"]
    usage: Usage
    latency_ms: int
    timings: Timings
    retrieval: RetrievalInfo
    actions: list[Action] = Field(default_factory=list)
    guard: str | None = None


class KnowledgeDocument(BaseModel):
    document_id: str = Field(min_length=1, max_length=128)
    title: str = Field(min_length=1, max_length=200)
    content: str = Field(min_length=1, max_length=200_000)
    source: str = Field("manual", max_length=200)
    document_version: int | None = Field(None, ge=1)
    content_type: Literal["text", "markdown"] = "markdown"


class UpsertRequest(BaseModel):
    tenant_id: str | None = Field(None, max_length=64)
    documents: list[KnowledgeDocument] = Field(min_length=1, max_length=50)


class DeleteRequest(BaseModel):
    tenant_id: str | None = Field(None, max_length=64)
    document_ids: list[str] = Field(min_length=1, max_length=100)


class SyncOperation(BaseModel):
    op: Literal["upsert", "delete"]
    document_id: str = Field(min_length=1, max_length=128, pattern=r"^[A-Za-z0-9_\-.:]+$")
    version: int = Field(ge=1)
    content_hash: str | None = Field(None, pattern=r"^[0-9a-f]{64}$")
    updated_at: str = Field(min_length=1, max_length=40)
    status: Literal["active", "inactive", "deleted"] = "active"
    title: str | None = Field(None, max_length=200)
    content: str | None = Field(None, max_length=200_000)
    content_type: Literal["text", "markdown"] = "markdown"


class SyncRequest(BaseModel):
    tenant_id: str | None = Field(None, max_length=64)
    operations: list[SyncOperation] = Field(min_length=1, max_length=20)


class SearchRequest(BaseModel):
    tenant_id: str | None = Field(None, max_length=64)
    query: str = Field(min_length=1, max_length=1000)
    top_k: int = Field(4, ge=1, le=20)
    mode: Literal["dense", "hybrid"] | None = None
