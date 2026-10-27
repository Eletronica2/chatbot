"""num_batch trade-off on CPU: cold prefill throughput and how fast Ollama yields after a cancelled prefill.

For each num_batch: (1) a cold ~2000-token prompt (unique first line) -> prefill tok/s; (2) start another cold prompt,
cancel it after 3 s, then time a tiny request -> cancel latency. Ends with the production option set loaded.
Usage (lock + timeout held by the caller):  docker compose exec -T ai-api python - 512 256 128 < bench/batch_bench.py
"""
import asyncio
import json
import sys
import time
import uuid

import httpx

from app.config.settings import get_settings
from app.prompts.builder import GLOBAL_POLICY

FILLER = "\n".join(f"- Item {i}: broto R$ {30 + i},90, média R$ {40 + i},90, grande R$ {50 + i},90" for i in range(60))


async def chat(c, s, content, num_batch, max_tokens=1):
    options = {"num_ctx": s.llm_num_ctx, "temperature": 0.0, "num_predict": max_tokens}
    if num_batch:
        options["num_batch"] = num_batch
    r = await c.post("/api/chat", json={"model": s.llm_model, "stream": False, "keep_alive": s.llm_keep_alive,
                                        "messages": [{"role": "system", "content": content}, {"role": "user", "content": "ok"}],
                                        "options": options})
    r.raise_for_status()
    return r.json()


async def main(batches):
    s = get_settings()
    async with httpx.AsyncClient(base_url=s.ollama_url, timeout=600) as c:
        for nb in batches:
            await chat(c, s, "ok", nb)  # load the runner with this option set
            d = await chat(c, s, f"[{uuid.uuid4().hex}]\n{GLOBAL_POLICY}\n{FILLER}", nb)
            pe_ms = d.get("prompt_eval_duration", 0) / 1e6
            task = asyncio.create_task(chat(c, s, f"[{uuid.uuid4().hex}]\n{GLOBAL_POLICY}\n{FILLER}", nb))
            await asyncio.sleep(3.0)
            task.cancel()
            try:
                await task
            except (asyncio.CancelledError, Exception):
                pass
            t = time.perf_counter()
            await chat(c, s, "ok", nb)
            print(json.dumps({"num_batch": nb, "prompt_tokens": d.get("prompt_eval_count"), "prefill_ms": int(pe_ms),
                              "prefill_tok_s": round(d.get("prompt_eval_count", 0) / (pe_ms / 1000), 1),
                              "cancel_to_next_ms": int((time.perf_counter() - t) * 1000)}))
        await chat(c, s, "ok", 0)


asyncio.run(main([int(a) for a in sys.argv[1:]] or [512, 256, 128]))
