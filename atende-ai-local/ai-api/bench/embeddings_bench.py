"""Compare local embedding models on the tenants' pt-BR fixtures (tenant-scoped retrieval, like production)."""

import gc
import json
import sys
import time

import numpy as np

from app.embeddings.encoder import Encoder
from app.retrieval.chunking import chunk_document
from bench.common import TENANTS, documents, summary

# (tenant, query, expected section substring)
QUERIES = [
    ("pizzaria_bella_massa", "qto sai uma calabresa g?", "Pizzas tradicionais"),
    ("pizzaria_bella_massa", "tem refri 2l?", "Bebidas"),
    ("pizzaria_bella_massa", "posso tirar cebola?", "Personalização"),
    ("pizzaria_bella_massa", "vcs entrega no centro?", "Área atendida"),
    ("pizzaria_bella_massa", "faz meio a meio?", "Personalização"),
    ("pizzaria_bella_massa", "tem borda recheada", "Borda"),
    ("pizzaria_bella_massa", "quanto tempo demora pra chegar", "Pedidos"),
    ("pizzaria_bella_massa", "da pra cancelar depois q pedi?", "Cancelamento"),
    ("pizzaria_bella_massa", "tem pizza doce?", "Sobremesas"),
    ("pizzaria_bella_massa", "qual o tamanho da grande? quantas fatias", "Tamanhos"),
    ("pizzaria_bella_massa", "onde fica a loja", "Endereço"),
    ("pizzaria_bella_massa", "frango c catupiri", "Pizzas especiais"),
    ("pizzaria_bella_massa", "vende cerveja?", "Bebidas"),
    ("pizzaria_bella_massa", "margerita tem manjericao?", "Pizzas tradicionais"),
    ("pastelaria_do_ze", "qto ta o pastel de carne", "Pastéis salgados"),
    ("pastelaria_do_ze", "aceita pix?", "Pagamento"),
    ("pastelaria_do_ze", "tem caldo de cana?", "Bebidas"),
    ("pastelaria_do_ze", "entrega no centro?", "Entrega"),
    ("pastelaria_do_ze", "tem pastel de palmito hj?", "Pastéis salgados"),
    ("pastelaria_do_ze", "tem coca?", "Bebidas"),
]


def rss_mb() -> float:
    for line in open("/proc/self/status"):
        if line.startswith("VmRSS:"):
            return int(line.split()[1]) / 1024
    return 0.0


def run(model_name: str) -> dict:
    gc.collect()
    before = rss_mb()
    t0 = time.perf_counter()
    enc = Encoder(model_name, threads=4)
    load_s = time.perf_counter() - t0
    after_load = rss_mb()

    corpus: dict[str, list] = {}
    doc_times = []
    for tenant in TENANTS:
        chunks = [c for d in documents(tenant) for c in chunk_document(d["title"], d["content"], max_chars=600)]
        t = time.perf_counter()
        vecs = np.array(enc.encode_documents([(c.section, c.text) for c in chunks]))
        doc_times.append((time.perf_counter() - t) * 1000 / len(chunks))
        corpus[tenant] = (chunks, vecs)

    enc.encode_queries(["aquecimento"])
    q_lat, hits1, hits3, rr, rows = [], 0, 0, 0.0, []
    for tenant, query, expected in QUERIES:
        t = time.perf_counter()
        q = np.array(enc.encode_queries([query])[0])
        q_lat.append((time.perf_counter() - t) * 1000)
        chunks, vecs = corpus[tenant]
        order = np.argsort(-(vecs @ q))
        sections = [chunks[i].section for i in order]
        rank = next((i + 1 for i, s in enumerate(sections) if expected in s), None)
        hits1 += rank == 1
        hits3 += bool(rank and rank <= 3)
        rr += 1 / rank if rank else 0
        rows.append({"tenant": tenant, "query": query, "expected": expected, "rank": rank, "top1": sections[0]})
    n = len(QUERIES)
    result = {
        "model": model_name, "revision": enc.revision, "params_loaded_M": round(enc.param_count() / 1e6, 1),
        "dim": enc.dim, "load_s": round(load_s, 2), "rss_delta_mb": round(after_load - before, 1),
        "rss_after_mb": round(rss_mb(), 1), "query_latency_ms": summary(q_lat),
        "doc_ms_per_chunk": round(sum(doc_times) / len(doc_times), 1),
        "hit@1": round(hits1 / n, 3), "hit@3": round(hits3 / n, 3), "mrr": round(rr / n, 3), "queries": rows,
    }
    del enc
    gc.collect()
    return result


if __name__ == "__main__":
    print(json.dumps(run(sys.argv[1]), ensure_ascii=False, indent=1))
