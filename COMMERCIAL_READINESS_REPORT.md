# Atende Ai — Prontidão comercial (Stripe)

Data: 2026-10-29. Nenhum valor real foi cobrado e o Stripe LIVE não foi ativado.

## Bloqueios corrigidos nesta auditoria

1. **O checkout vendia planos legados sem franquia.** Starter R$ 99, Growth R$ 249… não estavam ligados ao Catálogo V2, e o pagamento não liberava mensagens: o cliente ficava "legacy_unmetered", ou seja, ilimitado. Agora o checkout vende os planos V2 com o preço do catálogo, e o webhook atribui o plano e libera a franquia **somente quando o pagamento é confirmado**.
2. **A conversão de lead liberava a franquia e marcava a assinatura como ativa sem pagamento.** Isso se renovaria todo mês. Agora a empresa convertida fica `inactive` (aguardando pagamento), sem franquia e com as auto-respostas bloqueadas até o primeiro `invoice.paid`.
3. **Sem trava de LIVE.** Uma chave `sk_live_` cobraria assinaturas imediatamente. Agora cobrança LIVE exige `STRIPE_ALLOW_LIVE=true`, com padrão `false`.
4. Uma empresa com assinatura ativa não consegue abrir um segundo checkout; ela é direcionada ao portal.

## Testes

260 aprovados (MySQL real, 0 pulados), sendo 7 novos do fluxo Stripe: preço do catálogo, trava LIVE, pagamento ativa, retry de webhook não duplica, não pago não ativa, past_due/cancelado sem novo ciclo. A verificação em produção listou os 4 planos no painel e o checkout recusou limpo sem chave.

Deploy feito com backup `pre-commercial-20261029T010454Z`.
