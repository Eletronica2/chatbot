"""Stripe TEST readiness (run inside backend-api). Never prints secret values.

    docker compose ... exec -T backend-api python scripts/stripe_test_check.py
"""
import httpx

from app.config.settings import settings as s

EXPECTED_URL = "https://api.meuatendeai.com.br/api/v1/billing/webhooks/stripe"
EXPECTED_EVENTS = {"checkout.session.completed", "customer.subscription.created", "customer.subscription.updated",
                   "customer.subscription.deleted", "invoice.paid", "invoice.payment_failed"}

key = s.STRIPE_SECRET_KEY.strip()
mode = "TEST" if key.startswith(("sk_test_", "rk_test_")) else ("LIVE" if key.startswith(("sk_live_", "rk_live_")) else "AUSENTE/INVÁLIDA")
print("chave secreta:", mode)
print("segredo do webhook:", "ok (whsec_…)" if s.STRIPE_WEBHOOK_SECRET.strip().startswith("whsec_") else "AUSENTE/INVÁLIDO")
print("STRIPE_ALLOW_LIVE:", s.STRIPE_ALLOW_LIVE)
if mode != "TEST":
    raise SystemExit("Interrompido: somente chave TEST é aceita nesta etapa.")

client = httpx.Client(base_url="https://api.stripe.com/v1", headers={"Authorization": f"Bearer {key}"}, timeout=20)
account = client.get("/account")
print("conectividade Stripe:", account.status_code, "| país:", account.json().get("country"),
      "| moeda padrão:", account.json().get("default_currency"))
hooks = client.get("/webhook_endpoints", params={"limit": 20}).json().get("data", [])
match = [h for h in hooks if h.get("url") == EXPECTED_URL]
print("endpoints de webhook na Stripe:", len(hooks), "| com a URL esperada:", len(match))
for hook in match:
    events = set(hook.get("enabled_events") or [])
    print("  status:", hook.get("status"), "| api_version:", hook.get("api_version"), "| livemode:", hook.get("livemode"))
    print("  eventos faltando:", sorted(EXPECTED_EVENTS - events) or "nenhum", "| extras:", sorted(events - EXPECTED_EVENTS) or "nenhum")
