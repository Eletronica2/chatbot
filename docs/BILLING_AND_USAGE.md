# Billing e uso — Atenda Ai vs Meta

```
CLIENTE
 ├── Método de pagamento Meta → Meta
│     └── Uso WhatsApp (templates / mensagens cobráveis Meta)
│
 └── Método de pagamento Stripe → Atenda Ai
       └── Assinatura (Starter/Growth/…) ou On-demand (meter)
```

## Planos Atenda Ai

- `starter`, `growth`, `pro`, `enterprise` — limites mensais de mensagens inbound (gate operacional).
- `on_demand` — allowance ilimitado no gate; cobrança via ledger `usage_events` + Stripe Meter Events (TEST mode).

Env (sem secrets no repo):

- `STRIPE_SECRET_KEY`
- `STRIPE_ON_DEMAND_PRICE_ID`
- `STRIPE_METER_EVENT_NAME`
- `FISCAL_PROVIDER` / `FISCAL_PROVIDER_READY`

## Usage ledger

Tabela `usage_events`. Evento ideal: status Meta **`delivered`**.

- Unique `(tenant_id, provider_message_id, event_type)` → idempotente.
- Gateway chama `POST /api/v1/internal/usage/delivered`.
- Falha Stripe → `stripe_status=pending`; **não** bloqueia WhatsApp.

## Estimativa Meta

`meta_rate_cards` (vigência). UI mostra “Estimativa Meta — Brasil”. **Não** é fatura Atenda Ai.
Consulta docs oficiais Meta: 2026-09-03 (`developers.facebook.com/docs/whatsapp/pricing`).

## Fiscal / NFS-e

Interface `FiscalProvider`. Sem provider: UI “Emissão fiscal ainda não configurada”. **Nunca** gerar PDF fake de NF.
