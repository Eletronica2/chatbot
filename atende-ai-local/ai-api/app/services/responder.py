import asyncio
import hashlib
import re
import time

from app.config.settings import Settings
from app.domain.models import Action, RespondRequest, RespondResponse, RetrievalInfo, Timings, Usage
from app.embeddings.encoder import Encoder
from app.inference.gate import InferenceGate
from app.inference.ollama_client import OllamaClient
from app.logging import log_event
from app.prompts.builder import (
    PromptParts,
    StickyHistory,
    build_messages,
    render_flow_state,
    style_rules_for,
    trim_history,
)
from app.retrieval.store import KnowledgeStore
from app.retrieval.text import strip_accents
from app.services.full_context import FullContextCache
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
COLD_POLICY_TOKENS = 650  # policy + tenant header, when not yet measured by a warm-up
COLD_ESTIMATE_FACTOR = 1.35  # chars/3 under-counts markup, numbers and emoji (measured: 1036 estimated vs 1374 real)
COLD_REQUEST_TOKENS = 150  # flow state + history + question after the stable prefix
COLD_MARGIN_S = 8.0  # decode of a short answer plus network/queue slack
COLD_RAG_TOP_K = 2  # fewer chunks when not even the prompt head is cached


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
    stripped = text.strip()
    for m in _PROPER_NOUN_RE.finditer(stripped):
        # Sentence and line starts are not names, also when Markdown puts spaces or a bullet before the word
        # ("…62,90.  \nPreço: …", "- Tamanho: …"); only mid-sentence capitals are checked.
        before = stripped[: m.start()].rstrip(" \t*-•–—")
        if not before or before[-1] in ".!?:\n":
            continue
        parts = strip_accents(m.group(1).lower()).split("-")
        if not all(p in ctx or _singular(p) in ctx for p in parts if p):
            names.append(m.group(1))
    return names


def unsupported_claims(text: str, context_texts: list[str]) -> list[str]:
    """Commercial benefits (free items, discounts, gifts) must exist in the authorized context."""
    out = strip_accents(text.lower())
    ctx = strip_accents(" ".join(context_texts).lower())
    return [w for w in COMMERCIAL_CLAIMS if w in out and w not in ctx]


_OFFER_START = re.compile(
    r"^(quer|querem|gostaria|gostariam|deseja|desejam|que tal|vai querer|bora|aproveit|"
    r"posso (te |lhe )?(mostrar|sugerir|oferecer|indicar|recomendar|ajudar a escolher))\b")
_ASKS_FOR_SUGGESTION = re.compile(r"suger|indic|recomend|opc(ao|oes)|combo|promoc|o que (voces |vcs )?(tem|vende)")
_SENTENCE_START = re.compile(r"(?<=[.!?…])\s+(?=\S)")
_FIRST_WORD_CHAR = re.compile(r"[0-9A-Za-zÀ-ÿ]")
_MISSING_DATA = re.compile(r"nao (esta|estao|consta|constam|aparece|aparecem) (listad|nos dados|no cardapio|nas informacoes)"
                           r"|nos dados (da empresa|fornecidos)|nas informacoes (fornecidas|disponiveis)")


def strip_unsolicited_offer(text: str, message: str) -> str:
    """Concise style: drop a final sales question the customer did not ask for ("Quer saber de outro sabor?").

    Only the last sentence, only when it is a question opening with an offer verb, never the handoff offer, and never
    when the customer asked for suggestions/options. The rest of the answer is returned untouched.
    """
    if _ASKS_FOR_SUGGESTION.search(strip_accents(message.lower())):
        return text
    # A sentence starts at the first letter/digit after the boundary: emoji stay with the previous sentence and a
    # trailing emoji is not a sentence of its own.
    starts = []
    for m in _SENTENCE_START.finditer(text):
        letter = _FIRST_WORD_CHAR.search(text, m.end())
        if letter and (not starts or letter.start() != starts[-1]):
            starts.append(letter.start())
    if not starts:
        return text
    head, last = text[: starts[-1]].rstrip(), text[starts[-1]:]
    plain = strip_accents(last.lower()).lstrip(" -•*\u2022").strip()
    plain = re.sub(r"^[^a-z0-9]+", "", plain)
    if not head or "encaminh" in plain or "equipe" in plain or "atendente" in plain:
        return text
    if re.search(r"\?[^a-z0-9]*$", plain) and _OFFER_START.match(plain):
        return head
    return text


def authorized_context_texts(business_text: str, docs: list[dict], tenant_name: str,
                             tenant_profile: str) -> list[str]:
    """Only tenant-controlled business data may ground factual/commercial claims."""
    return [business_text, *(str(d.get("text") or "") for d in docs), tenant_name, tenant_profile]


class Responder:
    def __init__(self, settings: Settings, encoder: Encoder, store: KnowledgeStore, llm: OllamaClient, gate: InferenceGate,
                 full_context: FullContextCache | None = None):
        self.s = settings
        self.encoder = encoder
        self.store = store
        self.llm = llm
        self.gate = gate
        self.full_context = full_context
        # Ollama runs one slot, so its KV cache holds only the last prompt. We track which full-context prefix that
        # is; a cold prefix costs ~1 min of CPU prefill, so a request that cannot afford it uses RAG and the prefix is
        # rebuilt in the background while idle. This is a prediction, never a correctness assumption.
        self._kv_key: str | None = None
        self._kv_tenant: tuple[str, dict] | None = None
        # Every prompt of a tenant starts with the same head (policy + tenant + style); after any request or head
        # warm-up that head is resident, so a cold full/RAG prompt only pays for what follows it.
        self._kv_head: str | None = None
        self._head_tenants: dict[str, dict] = {}
        self._prefix_tokens: dict[str, dict[str, int]] = {}
        self._rewarm: asyncio.Task | None = None
        self._rewarm_target: tuple[str, dict] | None = None
        self.last_success_at = 0.0
        self.sticky_history = StickyHistory()

    def note_kv(self, key: str | None) -> None:
        self._kv_key = key
        if key is None:
            self._kv_head = None

    @staticmethod
    def _prefix_messages(tenant_id: str, tenant: dict, docs: list[dict]) -> list[dict]:
        return build_messages(PromptParts(
            tenant_name=tenant.get("display_name", tenant_id), tenant_profile=tenant.get("profile", ""), flow_state="",
            structured="", documents=docs, history=[], summary="", message="ok", documents_first=bool(docs),
            style_rules=style_rules_for(tenant)))

    @staticmethod
    def prefix_key(model: str, tenant_id: str, docs: list[dict], tenant: dict) -> str:
        system = Responder._prefix_messages(tenant_id, tenant, docs)[0]["content"]
        return hashlib.sha256(f"{model}|{tenant_id}|{system}".encode()).hexdigest()

    def cold_prefill_s(self, tenant_id: str, docs: list[dict]) -> float:
        """Predicted prefill time of a full-context prompt with what is (probably) resident in the KV cache."""
        measured = self._prefix_tokens.get(tenant_id, {})
        full = measured.get("full") or int(self.full_context.estimate_tokens(docs) * COLD_ESTIMATE_FACTOR) + COLD_POLICY_TOKENS
        head = measured.get("head", COLD_POLICY_TOKENS) if self._kv_head == tenant_id else 0
        return (max(full - head, 0) + COLD_REQUEST_TOKENS) / self.s.cold_prefill_tokens_per_s

    async def warm_prefix(self, tenant_id: str, tenant: dict, stage: str = "full") -> dict:
        """Compute the tenant's stable prefix in Ollama: "head" (policy + tenant + style, every prompt starts with it)
        or "full" (head + whole knowledge base, for full-context tenants). Startup, idle re-warm and readiness."""
        docs, mode = [], "rag"
        if stage == "full":
            docs, mode, _ = await self.context_documents(tenant_id, tenant, "ok", self.s.retrieval_mode)
            if mode != "full_context":
                docs = []
        async with self.gate.slot(tenant_id, timeout_s=self.s.llm_timeout_s) as _:
            self._kv_key = None
            gen = await self.llm.chat(self.s.llm_model, self._prefix_messages(tenant_id, tenant, docs),
                                      num_ctx=self.s.llm_num_ctx, temperature=0.0, max_tokens=1,
                                      keep_alive=self.s.llm_keep_alive)
            self._kv_key = self.prefix_key(self.s.llm_model, tenant_id, docs, tenant) if docs else None
            self._kv_tenant = (tenant_id, tenant) if docs else None
            self._kv_head = tenant_id
            self._head_tenants[tenant_id] = tenant
            self._prefix_tokens.setdefault(tenant_id, {})["full" if docs else "head"] = gen.prompt_tokens
            self.last_success_at = time.monotonic()
        return {"mode": mode if docs else "head", "documents": len(docs), "prompt_tokens": gen.prompt_tokens,
                "total_ms": gen.total_ms, "load_ms": gen.load_ms}

    async def keepalive_probe(self) -> str | None:
        """Readiness inference that re-uses (and keeps) the resident prefix instead of evicting it."""
        if self._kv_key is not None and self._kv_tenant is not None:
            tenant_id, tenant = self._kv_tenant
            result = await self.warm_prefix(tenant_id, tenant)
        elif self._kv_head is not None and self._kv_head in self._head_tenants:
            tenant_id = self._kv_head
            result = await self.warm_prefix(tenant_id, self._head_tenants[tenant_id], stage="head")
        else:
            return None
        return f"prefix_probe tenant={tenant_id} prompt_tokens={result['prompt_tokens']} total_ms={result['total_ms']}"

    def request_rewarm(self, tenant_id: str, tenant: dict) -> asyncio.Task | None:
        """Background, cancellable prefix warm-up (customer requests always pre-empt it)."""
        self._rewarm_target = (tenant_id, tenant)
        self._schedule_rewarm()
        return self._rewarm

    def _schedule_rewarm(self) -> None:
        if self._rewarm_target is None or (self._rewarm is not None and not self._rewarm.done()):
            return
        tenant_id, tenant = self._rewarm_target

        async def run():
            await asyncio.sleep(self.s.full_context_rewarm_delay_s)
            try:
                result = await self.warm_prefix(tenant_id, tenant)
                self._rewarm_target = None
                log_event("rewarm", tenant_id=tenant_id, mode=result["mode"], documents=result["documents"],
                          detail=f"prompt_tokens={result['prompt_tokens']} total_ms={result['total_ms']}")
            except asyncio.CancelledError:
                log_event("rewarm", tenant_id=tenant_id, detail="cancelled: customer request")
                raise
            except Exception as exc:
                log_event("rewarm", tenant_id=tenant_id, detail=f"error: {str(exc)[:120]}")

        self._rewarm = asyncio.create_task(run())

    async def _cancel_rewarm(self) -> None:
        task = self._rewarm
        if task is not None and not task.done():
            task.cancel()
            try:
                await task
            except (asyncio.CancelledError, Exception):
                pass

    async def _model_unloaded(self, model: str) -> bool:
        lister = getattr(self.llm, "loaded_models", None)
        if lister is None:
            return False
        try:
            return model not in await lister()
        except Exception:
            return False  # unknown is not "unloaded"; the deadline logic still protects the request

    async def context_documents(self, tenant_id: str, tenant: dict, message: str, mode: str) -> tuple[list[dict], str, str]:
        """(documents, retrieval mode, fallback reason). Full context only for opted-in tenants whose base fits."""
        if str(tenant.get("context_mode") or "rag").lower() == "full" and self.full_context is not None:
            ctx = await self.full_context.get(tenant_id)
            if ctx.eligible:
                return ctx.documents, "full_context", ""
            reason = ctx.reason
        else:
            reason = ""
        return await self.retrieve(tenant_id, message, self.s.retrieval_top_k, mode), mode, reason

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

        await self._cancel_rewarm()  # a customer request always wins over background re-warming
        t0 = time.perf_counter()
        docs, mode, fallback_reason = await self.context_documents(
            tenant_id, tenant, message, opts.retrieval_mode or self.s.retrieval_mode)
        kv_key = self.prefix_key(model, tenant_id, docs, tenant) if mode == "full_context" else None
        if kv_key is not None and opts.deadline_ms and await self._model_unloaded(model):
            self.note_kv(None)  # Ollama restarted or keep_alive expired behind our back: the cache is empty
        if kv_key is not None and kv_key != self._kv_key and opts.deadline_ms:
            cold_s = self.cold_prefill_s(tenant_id, docs)
            if cold_s + COLD_MARGIN_S > (opts.deadline_ms / 1000) - (time.perf_counter() - started):
                self._rewarm_target = (tenant_id, tenant)
                # Without even the prompt head cached the whole RAG prompt is prefilled: keep it smaller.
                top_k = self.s.retrieval_top_k if self._kv_head == tenant_id else min(COLD_RAG_TOP_K, self.s.retrieval_top_k)
                docs = await self.retrieve(tenant_id, message, top_k, opts.retrieval_mode or self.s.retrieval_mode)
                mode, fallback_reason, kv_key = opts.retrieval_mode or self.s.retrieval_mode, "kv_cold", None
        retrieval_ms = int((time.perf_counter() - t0) * 1000)

        raw_history = [m.model_dump() for m in req.recent_history]
        if mode == "full_context":
            # Callers often include the current message as the last history item; it is sent as the final user turn
            # anyway, and dropping the copy makes this prompt a strict prefix of the next turn's prompt.
            if raw_history and raw_history[-1]["role"] == "user" and raw_history[-1]["content"].strip() == message.strip():
                raw_history = raw_history[:-1]
            history = self.sticky_history.select(req.conversation_id, raw_history, self.s.history_max_messages,
                                                 self.s.history_max_chars)
        else:
            history = trim_history(raw_history, self.s.history_max_messages, self.s.history_max_chars)
        messages = build_messages(PromptParts(
            tenant_name=tenant.get("display_name", tenant_id),
            tenant_profile=tenant.get("profile", ""),
            flow_state=render_flow_state(req.flow_context),
            structured=biz.render() if not biz.is_empty() else "",
            documents=docs,
            history=history,
            summary=str(req.flow_context.get("conversation_summary", "")),
            message=message,
            documents_first=mode == "full_context",
            style_rules=style_rules_for(tenant),
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
            self._kv_key = None
            try:
                # Cancelling the stream closes the HTTP connection, which makes Ollama abort the generation.
                gen = await (asyncio.wait_for(call, timeout=budget) if budget is not None else call)
            except asyncio.TimeoutError:
                self._kv_head = None  # aborted mid-prefill: nothing about the cache can be assumed
                raise DeadlineExceeded() from None
            except Exception:
                self._kv_head = None
                raise
            finally:
                self._schedule_rewarm()
            self._kv_key = kv_key
            self._kv_tenant = (tenant_id, tenant) if kv_key else None
            self._kv_head = tenant_id
            self._head_tenants[tenant_id] = tenant
            self.last_success_at = time.monotonic()

        text, guard = gen.text, None
        context_texts = authorized_context_texts(
            biz.render() if not biz.is_empty() else "", docs,
            tenant.get("display_name", ""), tenant.get("profile", ""),
        )
        # Customer wording, conversation history and collected flow fields are not business evidence.
        allowed_prices = biz.known_prices() | {c for t in context_texts for c in price_cents_in(t)}
        allowed_numbers = {n for t in context_texts for n in numbers_in(t)}
        # guard_detail names only the offending business term (price/number/entity), never message text.
        guard_detail = None
        if not text:
            text, guard = FALLBACK_TEXT, "empty_generation"
        elif price_cents_in(text) - allowed_prices:
            guard_detail = sorted(price_cents_in(text) - allowed_prices)[:3]
            text, guard = FALLBACK_TEXT, "price_not_in_context"
        elif numbers_in(text) - allowed_numbers:
            guard_detail = sorted(numbers_in(text) - allowed_numbers)[:3]
            text, guard = FALLBACK_TEXT, "number_not_in_context"
        elif unsupported_claims(text, context_texts):
            guard_detail = unsupported_claims(text, context_texts)[:3]
            text, guard = FALLBACK_TEXT, "claim_not_in_context"
        elif unsupported_existence_claims(text, context_texts, closed_payment_list=bool(biz.payment_methods)):
            text, guard = FALLBACK_TEXT, "existence_not_in_context"
        elif ungrounded_names(text, context_texts):
            guard_detail = [n[:30] for n in ungrounded_names(text, context_texts)[:3]]
            text, guard = OFF_TOPIC_TEXT.format(name=tenant.get("display_name", "empresa")), "entity_not_in_context"
        if is_offtopic_deflection(text) and asks_about_offering(message):
            # "Do you have/offer X?" is about the business; unknown X must get the standard unknown answer.
            guard_detail = guard_detail or ([guard] if guard else ["model_deflected"])
            text, guard = FALLBACK_TEXT, "offering_question_without_data"
        if guard:
            log_event("guard", request_id=req.request_id, tenant_id=tenant_id, guard=guard, mode=mode,
                      detail=str(guard_detail)[:120] if guard_detail else None)
        elif _MISSING_DATA.search(strip_accents(text.lower())):
            # Rule 4 mandates the standard unknown answer; "não está listada nos dados" leaks internals.
            text, guard = FALLBACK_TEXT, "unknown_normalized"
        elif style_rules_for(tenant):
            text = strip_unsolicited_offer(text, message)

        return done(
            text, "rag" if docs else "llm",
            model=gen.model,
            usage=Usage(prompt_tokens=gen.prompt_tokens, completion_tokens=gen.completion_tokens),
            timings=Timings(queue_ms=queue_ms, retrieval_ms=retrieval_ms, load_ms=gen.load_ms,
                            first_token_ms=gen.first_token_ms, generation_ms=gen.total_ms, tokens_per_s=gen.tokens_per_s,
                            prompt_eval_ms=gen.prompt_eval_ms, eval_ms=gen.eval_ms),
            retrieval=RetrievalInfo(documents_used=len(docs), mode=mode, fallback_reason=fallback_reason or None, chunks=[
                {"chunk_id": d["chunk_id"], "document_id": d["document_id"], "section": d["section"], "score": d["score"]}
                for d in docs]),
            guard=guard,
        )
