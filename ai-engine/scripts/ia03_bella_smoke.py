"""IA-03 private smoke: AWS AI Engine -> HMAC -> WireGuard -> local API -> Qdrant -> Qwen3.

Run inside the ai-engine container (reads the operational credential from its environment, never prints it):
    docker compose ... exec -T ai-engine python - < scripts/ia03_bella_smoke.py
"""
import asyncio
import base64
import time

from app.clients.local_ai_client import LocalAIClient, LocalAIError
from app.config.settings import settings

TENANT = "pizzaria_bella_massa"
QUESTIONS = ["Quanto custa a pizza de calabresa grande?", "Vocês oferecem Wi-Fi?", "Tem estacionamento próprio?",
             "Quem ganhou o jogo do Flamengo ontem?"]


def client(secret_b64=None):
    return LocalAIClient(base_url=settings.LOCAL_AI_BASE_URL, key_id=settings.LOCAL_AI_KEY_ID,
                         secret_b64=secret_b64 or settings.LOCAL_AI_SECRET_B64, total_budget_s=60, max_attempts=1)


def body(request_id, tenant, message):
    return {"request_id": request_id, "tenant_id": tenant, "message": message, "recent_history": [],
            "flow_context": {}, "business_context": {}, "options": {}}


async def main():
    c = client()
    probe = await c.probe()
    network = (probe.get("status") or {}).get("network") or {}
    print("probe:", {k: probe.get(k) for k in ("reachable", "ready", "latency_ms")},
          "vpn_peer_ok:", network.get("vpn_peer_ok"), "wifi_signal_dbm:", network.get("wifi_signal_dbm"))
    for i, question in enumerate(QUESTIONS, 1):
        started = time.monotonic()
        rid = f"ia03-smoke-{int(time.time())}-{i}"
        data, stats = await c.respond(TENANT, rid, body(rid, TENANT, question))
        usage, timings, retrieval = data["usage"], data["timings"], data["retrieval"]
        print(f"Q{i}: {question}")
        print(f"  -> {data['text']}")
        print(f"  level={data['level']} model={data['model']} guard={data.get('guard')} "
              f"tokens_in={usage['prompt_tokens']} tokens_out={usage['completion_tokens']} "
              f"retrieval_docs={retrieval['documents_used']} queue_ms={timings['queue_ms']} "
              f"retrieval_ms={timings['retrieval_ms']} load_ms={timings['load_ms']} gen_ms={timings['generation_ms']} "
              f"server_ms={data['latency_ms']} aws_total_ms={int((time.monotonic() - started) * 1000)} attempts={stats.attempts}")
    for label, cl, tenant in (("chave da Bella usada para outro tenant", c, "pastelaria_do_ze"),
                              ("segredo errado", client(base64.b64encode(b"x" * 32).decode()), TENANT)):
        try:
            await cl.respond(tenant, "ia03-neg", body("ia03-neg", tenant, "oi"))
            print(f"NEG {label}: ACEITO (FALHA)")
        except LocalAIError as exc:
            print(f"NEG {label}: recusado {exc.status} {exc.code}")
        if cl is not c:
            await cl.close()
    await c.close()


asyncio.run(main())
