import asyncio
import re
import time

from app.config.settings import Settings
from app.domain.models import Action, RespondRequest, RespondResponse, RetrievalInfo, Timings, Usage
from app.embeddings.encoder import Encoder
from app.inference.gate import InferenceGate
from app.inference.ollama_client import OllamaClient
from app.prompts.builder import PromptParts, build_messages, render_flow_state, trim_history
from app.retrieval.store import KnowledgeStore
from app.retrieval.text import strip_accents
from app.services.grounding import asks_about_offering, is_offtopic_deflection, unsupported_existence_claims
from app.services.structured import (
    HANDOFF_TEXT,
    Business,
    answer_deterministic,
    detect_handoff,
    numbers_in,
    price_cents_in,
)

FALLBACK_TEXT = "Não tenho essa informação confirmada no momento. Posso encaminhar sua dúvida para a equipe?"
MIN_GENERATION_S = 1.0


class DeadlineExceeded(Exception):
    pass
OFF_TOPIC_TEXT = "Posso ajudar apenas com assuntos da {name}, como cardápio, preços, horários e entregas."
COMMERCIAL_CLAIMS = ("gratis", "de graca", "gratuit", "desconto", "brinde", "cortesia", "frete free")


_PROPER_NOUN_RE = re.compile(r"(?<![.!?:\n]\s)(?<!^)\b([A-ZÀ-Ý][\wÀ-ÿ\-]{2,})")


def _singular(word: str) -> str:
    """Plural tolerance only ("Pizza" is grounded by "pizzas"); never matches a different word."""
    if len(word) > 4 and word.endswith("es") and word[-3] in "rsz":
        return word[:-2]
    if len(word) > 3 and word.endswith("s"):
        return word[:-1]
    return word


def ungrounded_names(text: str, context_texts: list[str]) -> list[str]:
    """Mid-sentence capitalized names (places, brands, people) must come from the authorized context."""
    ctx = set(strip_accents(" ".join(context_texts).lower()).replace("-", " ").split())
    ctx |= {w.strip(".,;:!?()\"'*_") for w in list(ctx)}
    ctx |= {_singular(w) for w in list(ctx)}
    names = []
    for m in _PROPER_NOUN_RE.finditer(text.strip()):
        parts = strip_accents(m.group(1).lower()).split("-")
        if not all(p in ctx or _singular(p) in ctx for p in parts if p):
            names.append(m.group(1))
    return names


def unsupported_claims(text: str, context_texts: list[str]) -> list[str]:
    """Commercial benefits (free items, discounts, gifts) must exist in the authorized context."""
    out = strip_accents(text.lower())
    ctx = strip_accents(" ".join(context_texts).lower())
    return [w for w in COMMERCIAL_CLAIMS if w in out and w not in ctx]


def authorized_context_texts(business_text: str, docs: list[dict], tenant_name: str,
                             tenant_profile: str) -> list[str]:
    """Only tenant-controlled business data may ground factual/commercial claims."""
    return [business_text, *(str(d.get("text") or "") for d in docs), tenant_name, tenant_profile]


class Responder:
    def __init__(self, settings: Settings, encoder: Encoder, store: KnowledgeStore, llm: OllamaClient, gate: InferenceGate):
        self.s = settings
        self.encoder = encoder
        self.store = store
        self.llm = llm
        self.gate = gate

    async def retrieve(self, tenant_id: str, query: str, top_k: int, mode: str) -> list[dict]:
        vec = (await asyncio.to_thread(self.encoder.encode_queries, [query]))[0]
        return await self.store.search(tenant_id, vec, query, top_k, mode, self.s.retrieval_min_score)

    async def respond(self, req: RespondRequest, tenant_id: str, tenant: dict) -> RespondResponse:
        started = time.perf_counter()
        message = req.message[: self.s.message_max_chars]
        biz = Business.from_context(req.business_context)
        opts = req.options

        def done(text: str, level: str, **kw) -> RespondResponse:
            return RespondResponse(
                request_id=req.request_id, tenant_id=tenant_id, text=text, level=level,
                latency_ms=int((time.perf_counter() - started) * 1000),
                model=kw.pop("model", None), usage=kw.pop("usage", Usage()),
                timings=kw.pop("timings", Timings()), retrieval=kw.pop("retrieval", RetrievalInfo()), **kw,
            )

        handoff = detect_handoff(message)
        if handoff:
            return done(HANDOFF_TEXT[handoff], "handoff", actions=[Action(type="handoff_required", reason=handoff)])

        if opts.allow_deterministic:
            det = answer_deterministic(message, biz)
            if det:
                return done(det.text, "deterministic")

        model = opts.model or self.s.llm_model
        if model not in self.s.allowed_model_list:
            raise ValueError("model_not_allowed")

        mode = opts.retrieval_mode or self.s.retrieval_mode
        t0 = time.perf_counter()
        docs = await self.retrieve(tenant_id, message, self.s.retrieval_top_k, mode)
        retrieval_ms = int((time.perf_counter() - t0) * 1000)

        history = trim_history([m.model_dump() for m in req.recent_history], self.s.history_max_messages, self.s.history_max_chars)
        messages = build_messages(PromptParts(
            tenant_name=tenant.get("display_name", tenant_id),
            tenant_profile=tenant.get("profile", ""),
            flow_state=render_flow_state(req.flow_context),
            structured=biz.render() if not biz.is_empty() else "",
            documents=docs,
            history=history,
            summary=str(req.flow_context.get("conversation_summary", "")),
            message=message,
        ))

        deadline = started + opts.deadline_ms / 1000 if opts.deadline_ms else None

        def remaining() -> float | None:
            if deadline is None:
                return None
            left = deadline - time.perf_counter()
            if left < MIN_GENERATION_S:
                raise DeadlineExceeded()
            return left

        async with self.gate.slot(tenant_id, timeout_s=remaining()) as queue_ms:
            budget = remaining()
            call = self.llm.chat(
                model, messages,
                num_ctx=opts.num_ctx or self.s.llm_num_ctx,
                temperature=opts.temperature if opts.temperature is not None else self.s.llm_temperature,
                max_tokens=opts.max_tokens or self.s.llm_max_tokens,
                keep_alive=self.s.llm_keep_alive,
            )
            try:
                # Cancelling the stream closes the HTTP connection, which makes Ollama abort the generation.
                gen = await (asyncio.wait_for(call, timeout=budget) if budget is not None else call)
            except asyncio.TimeoutError:
                raise DeadlineExceeded() from None

        text, guard = gen.text, None
        context_texts = authorized_context_texts(
            biz.render() if not biz.is_empty() else "", docs,
            tenant.get("display_name", ""), tenant.get("profile", ""),
        )
        # Customer wording, conversation history and collected flow fields are not business evidence.
        allowed_prices = biz.known_prices() | {c for t in context_texts for c in price_cents_in(t)}
        allowed_numbers = {n for t in context_texts for n in numbers_in(t)}
        if not text:
            text, guard = FALLBACK_TEXT, "empty_generation"
        elif price_cents_in(text) - allowed_prices:
            text, guard = FALLBACK_TEXT, "price_not_in_context"
        elif numbers_in(text) - allowed_numbers:
            text, guard = FALLBACK_TEXT, "number_not_in_context"
        elif unsupported_claims(text, context_texts):
            text, guard = FALLBACK_TEXT, "claim_not_in_context"
        elif unsupported_existence_claims(text, context_texts, closed_payment_list=bool(biz.payment_methods)):
            text, guard = FALLBACK_TEXT, "existence_not_in_context"
        elif ungrounded_names(text, context_texts):
            text, guard = OFF_TOPIC_TEXT.format(name=tenant.get("display_name", "empresa")), "entity_not_in_context"
        if is_offtopic_deflection(text) and asks_about_offering(message):
            # "Do you have/offer X?" is about the business; unknown X must get the standard unknown answer.
            text, guard = FALLBACK_TEXT, "offering_question_without_data"

        return done(
            text, "rag" if docs else "llm",
            model=gen.model,
            usage=Usage(prompt_tokens=gen.prompt_tokens, completion_tokens=gen.completion_tokens),
            timings=Timings(queue_ms=queue_ms, retrieval_ms=retrieval_ms, load_ms=gen.load_ms,
                            first_token_ms=gen.first_token_ms, generation_ms=gen.total_ms, tokens_per_s=gen.tokens_per_s),
            retrieval=RetrievalInfo(documents_used=len(docs), mode=mode, chunks=[
                {"chunk_id": d["chunk_id"], "document_id": d["document_id"], "section": d["section"], "score": d["score"]}
                for d in docs]),
            guard=guard,
        )
