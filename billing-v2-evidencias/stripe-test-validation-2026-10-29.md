# Validação Stripe TEST — 2026-10-29 (sem segredos)

- Configuração: `/opt/atende-ai/.env.production` (600) com `STRIPE_SECRET_KEY` (sk_test_), `STRIPE_WEBHOOK_SECRET` (whsec_) e `STRIPE_ALLOW_LIVE=false`, gravados pelo proprietário com `scripts/set-stripe-test-keys.sh`. Foi recriado somente o `backend-api`.
- Conectividade: `GET /v1/account` retornou 200 (BR, brl). Webhook `https://api.meuatendeai.com.br/api/v1/billing/webhooks/stripe` com status enabled, api_version `2026-09-30.endive`, livemode false e os 6 eventos esperados.
- Checkout (empresa `stripe-teste-inicial`): modo subscription, livemode false, R$ 197,00/mês, "Atende Ai — Plano Inicial", metadata plan_code `PLAN_INICIAL_2026_10`.
- Antes do pagamento: assinatura inactive, franquia 0, bloqueado.
- Pagamento aprovado (4242…): `checkout.session.completed`, `customer.subscription.created` e `invoice.paid` entregues (pending_webhooks=0; backend 200). Resultado: assinatura active, franquia **1000** (1 concessão), fatura paga de 19700.
- Webhook duplicado: reenvio assinado de `checkout.session.completed` e `invoice.paid` retornou 200. Franquia continuou 1000, com 1 concessão e 1 fatura. Assinatura falsa retornou 400.
- Cancelamento (API TEST): Stripe canceled e status local canceled via webhook. Próximo ciclo: `subscription_not_paid`.
- Pagamento recusado (empresa `stripe-teste-recusa`, cartão 0341): a Stripe recusou no Checkout (sessão open/unpaid, sem assinatura). Local: inactive, franquia 0, bloqueado, sem fatura.
- Limpeza: o checkout pendente foi expirado. As duas empresas de teste foram inativadas sem exclusão, com auditoria. Pedidos inalterados (2).
- Não validado ao vivo: falha de pagamento em **renovação** (`invoice.payment_failed`). Esse caso está coberto pelos testes automatizados (MySQL) e pode ser exercitado com Stripe Test Clocks.
