"""N simultaneous LLM-bound requests through the API (deterministic level disabled) to exercise queue/backpressure."""

import asyncio
import json
import sys
import time

import httpx

from bench.common import API, TOKENS, headers, respond_payload, summary

QUESTIONS = ["posso tirar cebola da calabresa?", "vcs fazem meio a meio?", "tem borda recheada?",
             "quanto tempo demora a entrega?", "vende cerveja?", "qual a diferença entre média e grande?"]


async def one(c: httpx.AsyncClient, i: int, model: str) -> dict:
    tenant = "pizzaria_bella_massa"
    body = respond_payload(tenant, QUESTIONS[i % len(QUESTIONS)], options={"model": model, "allow_deterministic": False})
    t = time.perf_counter()
    r = await c.post("/v1/respond", headers=headers(TOKENS[tenant]), json=body)
    wall = int((time.perf_counter() - t) * 1000)
    data = r.json()
    return {"i": i, "status": r.status_code, "wall_ms": wall, "error_code": data.get("error_code"),
            "queue_ms": (data.get("timings") or {}).get("queue_ms"), "latency_ms": data.get("latency_ms"),
            "completion_tokens": (data.get("usage") or {}).get("completion_tokens"),
            "retry_after": r.headers.get("retry-after")}


async def level(n: int, model: str) -> dict:
    async with httpx.AsyncClient(base_url=API, timeout=600) as c:
        t = time.perf_counter()
        rows = await asyncio.gather(*(one(c, i, model) for i in range(n)))
        total = int((time.perf_counter() - t) * 1000)
    ok = [r for r in rows if r["status"] == 200]
    return {"concurrency": n, "model": model, "batch_wall_ms": total, "ok": len(ok),
            "saturated_503": sum(r["status"] == 503 for r in rows),
            "other_errors": sum(r["status"] not in (200, 503) for r in rows),
            "wall_ms": summary([r["wall_ms"] for r in ok]), "queue_ms": summary([r["queue_ms"] or 0 for r in ok]),
            "rows": rows}


if __name__ == "__main__":
    model = sys.argv[1]
    out = [asyncio.run(level(int(n), model)) for n in sys.argv[2].split(",")]
    print(json.dumps(out, ensure_ascii=False, indent=1))
