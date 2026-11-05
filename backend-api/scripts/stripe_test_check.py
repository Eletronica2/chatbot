"""Stripe readiness (run inside backend-api). Never prints secret values; read-only (no Stripe writes).

    ... exec -T backend-api python scripts/stripe_test_check.py                    # active TEST config
    scripts/stripe-live-preflight.sh  (runs this file with --live-preflight)       # staged LIVE keys
"""
import sys

import httpx

from app.config.settings import settings as s

EXPECTED_URL = "https://api.meuatendeai.com.br/api/v1/billing/webhooks/stripe"
EXPECTED_EVENTS = {"checkout.session.completed", "customer.subscription.created", "customer.subscription.updated",
                   "customer.subscription.deleted", "invoice.paid", "invoice.payment_failed"}
EXPECTED_PRICES = {"PLAN_INICIAL_2026_10": 197, "PLAN_ESSENCIAL_2026_10": 297, "PLAN_CRESCIMENTO_2026_10": 497,
                   "PLAN_PROFISSIONAL_2026_10": 897}
live_preflight = "--live-preflight" in sys.argv

key = s.STRIPE_SECRET_KEY.strip()
mode = "TEST" if key.startswith(("sk_test_", "rk_test_")) else ("LIVE" if key.startswith(("sk_live_", "rk_live_")) else "AUSENTE/INVÁLIDA")
print("chave:", mode, "(restrita rk_)" if key.startswith("rk_") else "")
print("segredo do webhook:", "ok (whsec_…)" if s.STRIPE_WEBHOOK_SECRET.strip().startswith("whsec_") else "AUSENTE/INVÁLIDO")
print("STRIPE_ALLOW_LIVE:", s.STRIPE_ALLOW_LIVE)
if mode != ("LIVE" if live_preflight else "TEST"):
    raise SystemExit(f"Interrompido: esperado {'LIVE' if live_preflight else 'TEST'}.")

client = httpx.Client(base_url="https://api.stripe.com/v1", headers={"Authorization": f"Bearer {key}"}, timeout=20)


def get(path, **params):
    response = client.get(path, params=params)
    return response.status_code, (response.json() if response.headers.get("content-type", "").startswith("application/json") else {})


status, account = get("/account")
print("conta:", status, "| país:", account.get("country"), "| moeda:", account.get("default_currency"),
      "| cobranças habilitadas:", account.get("charges_enabled"), "" if status == 200 else "(rk_ sem leitura de conta: ok)")

status, hooks = get("/webhook_endpoints", limit=20)
match = [h for h in hooks.get("data", []) if h.get("url") == EXPECTED_URL] if status == 200 else []
print("webhook:", status, "| com a URL esperada:", len(match), "" if status == 200 else "(dar leitura de Webhook Endpoints à rk_)")
for hook in match:
    events = set(hook.get("enabled_events") or [])
    print("  status:", hook.get("status"), "| api_version:", hook.get("api_version"), "| livemode:", hook.get("livemode"),
          "| faltando:", sorted(EXPECTED_EVENTS - events) or "nenhum", "| extras:", sorted(events - EXPECTED_EVENTS) or "nenhum")

if live_preflight:
    status, configs = get("/billing_portal/configurations", limit=10, active="true")
    default = next((c for c in configs.get("data", []) if c.get("is_default")), None) if status == 200 else None
    if default is None:
        print("portal:", status, "| SEM configuração padrão ativa (Dashboard → Configurações → Billing → Portal do cliente)")
    else:
        f = default.get("features") or {}
        print("portal: atualizar cartão =", (f.get("payment_method_update") or {}).get("enabled"),
              "| cancelar =", (f.get("subscription_cancel") or {}).get("enabled"),
              "| trocar plano =", (f.get("subscription_update") or {}).get("enabled"), "(deve ser False)",
              "| faturas =", (f.get("invoice_history") or {}).get("enabled"))
    for path, label in (("/customers", "Customers"), ("/checkout/sessions", "Checkout Sessions"),
                        ("/subscriptions", "Subscriptions")):
        code, _ = get(path, limit=1)
        print(f"permissão leitura {label}:", "ok" if code == 200 else f"{code} (a rk_ precisa de escrita em {label})")

    from app.db.mysql import MySQLDatabase

    rows = MySQLDatabase(s.DATABASE_URL).fetch_all(
        "SELECT code, price FROM billing_catalog_items WHERE kind='plan' AND status='active'")
    found = {r["code"]: float(r["price"]) for r in rows if r["price"] is not None}
    wrong = {c: found.get(c) for c, p in EXPECTED_PRICES.items() if found.get(c) != p}
    print("preços do catálogo:", "ok (197/297/497/897 por mês)" if not wrong else f"DIVERGENTES {wrong}")
