"""Dense vs hybrid (dense + BM25 + RRF) retrieval through /v1/knowledge/search."""

import json

from bench.common import TOKENS, client, headers, summary
from bench.embeddings_bench import QUERIES

EXTRA = [
    ("pizzaria_bella_massa", "Coca-Cola", "Bebidas"),
    ("pizzaria_bella_massa", "catupiry", "Pizzas especiais"),
    ("pizzaria_bella_massa", "35 cm", "Tamanhos"),
    ("pizzaria_bella_massa", "taxa vila nova", "Área atendida"),
    ("pizzaria_bella_massa", "Rua das Oliveiras", "Endereço"),
    ("pizzaria_bella_massa", "broto", "Tamanhos"),
    ("pastelaria_do_ze", "Jardim das Flores", "Entrega"),
    ("pastelaria_do_ze", "500 ml", "Bebidas"),
    ("pastelaria_do_ze", "credito", "Pagamento"),
]


def run() -> dict:
    out = {}
    with client() as c:
        for mode in ("dense", "hybrid"):
            rows, lat, h1, h3, rr = [], [], 0, 0, 0.0
            for tenant, query, expected in QUERIES + EXTRA:
                r = c.post("/v1/knowledge/search", headers=headers(TOKENS[tenant]),
                           json={"query": query, "top_k": 3, "mode": mode})
                body = r.json()
                sections = [h["section"] for h in body["results"]]
                assert all(h["tenant_id"] == tenant for h in body["results"])
                rank = next((i + 1 for i, s in enumerate(sections) if expected in s), None)
                h1 += rank == 1
                h3 += rank is not None
                rr += 1 / rank if rank else 0
                lat.append(body["latency_ms"])
                rows.append({"tenant": tenant, "query": query, "expected": expected, "rank": rank,
                             "top1": sections[0] if sections else None})
            n = len(rows)
            out[mode] = {"n": n, "hit@1": round(h1 / n, 3), "hit@3": round(h3 / n, 3), "mrr": round(rr / n, 3),
                         "latency_ms": summary(lat), "misses": [r for r in rows if r["rank"] != 1]}
    return out


if __name__ == "__main__":
    print(json.dumps(run(), ensure_ascii=False, indent=1))
