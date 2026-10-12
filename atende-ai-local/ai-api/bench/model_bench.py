"""Raw model benchmark straight against Ollama (inside the Docker network): load, TTFT, tok/s, totals."""

import asyncio
import json
import sys
import time

import httpx

from app.inference.ollama_client import OllamaClient
from app.prompts.builder import PromptParts, build_messages
from app.retrieval.chunking import chunk_document
from app.services.structured import Business
from bench.common import business, documents, summary

OLLAMA = "http://ollama:11434"
QUESTIONS = [
    "Quanto custa a pizza de calabresa? Tem média e grande?",
    "Vocês fazem pizza meio a meio?",
    "posso tirar cebola da calabresa?",
    "qual o tempo de entrega pro centro?",
    "tem borda recheada?",
    "tem alguma promoção hoje?",
    "vcs vendem cerveja?",
    "qual a diferença de tamanho entre a média e a grande?",
]


def realistic_messages(question: str) -> list[dict]:
    biz = Business.from_context(business("pizzaria_bella_massa"))
    chunks = [c for d in documents("pizzaria_bella_massa") for c in chunk_document(d["title"], d["content"], max_chars=600)]
    docs = [{"section": c.section, "text": c.text} for c in chunks[:3]]
    return build_messages(PromptParts("Pizzaria Bella Massa", "Pizzaria de bairro.", "", biz.render(), docs, [], "", question))


async def unload(model: str) -> None:
    async with httpx.AsyncClient(base_url=OLLAMA, timeout=60) as c:
        await c.post("/api/generate", json={"model": model, "keep_alive": 0})
        await asyncio.sleep(2)


async def bench(model: str, num_ctx: int, max_tokens: int = 192) -> dict:
    llm = OllamaClient(OLLAMA, 600)
    await unload(model)
    t = time.perf_counter()
    cold = await llm.chat(model, [{"role": "user", "content": "Diga apenas: ok"}], num_ctx=num_ctx, temperature=0.0,
                          max_tokens=4, keep_alive="30m")
    cold_wall_ms = int((time.perf_counter() - t) * 1000)
    rows = []
    for q in QUESTIONS:
        g = await llm.chat(model, realistic_messages(q), num_ctx=num_ctx, temperature=0.3, max_tokens=max_tokens,
                           keep_alive="30m")
        rows.append({
            "question": q, "answer": g.text, "prompt_tokens": g.prompt_tokens, "completion_tokens": g.completion_tokens,
            "first_token_ms": g.first_token_ms, "total_ms": g.total_ms, "tokens_per_s": g.tokens_per_s,
            "prompt_eval_tps": round(g.prompt_tokens / (g.prompt_eval_ms / 1000), 1) if g.prompt_eval_ms else None,
            "load_ms": g.load_ms, "has_think_tag": "<think>" in g.text.lower(),
        })
    async with httpx.AsyncClient(base_url=OLLAMA, timeout=30) as c:
        ps = (await c.get("/api/ps")).json()
    await llm.close()
    return {
        "model": model, "num_ctx": num_ctx, "cold_load_ms": cold.load_ms, "cold_first_call_wall_ms": cold_wall_ms,
        "first_token_ms": summary([r["first_token_ms"] for r in rows if r["first_token_ms"]]),
        "total_ms": summary([r["total_ms"] for r in rows]),
        "tokens_per_s": summary([r["tokens_per_s"] for r in rows if r["tokens_per_s"]]),
        "prompt_eval_tps": summary([r["prompt_eval_tps"] for r in rows if r["prompt_eval_tps"]]),
        "prompt_tokens": summary([r["prompt_tokens"] for r in rows]),
        "completion_tokens": summary([r["completion_tokens"] for r in rows]),
        "think_tags": sum(r["has_think_tag"] for r in rows),
        "ollama_ps": [{k: m.get(k) for k in ("name", "size", "size_vram", "context_length")} for m in ps.get("models", [])],
        "rows": rows,
    }


if __name__ == "__main__":
    print(json.dumps(asyncio.run(bench(sys.argv[1], int(sys.argv[2]))), ensure_ascii=False, indent=1))
