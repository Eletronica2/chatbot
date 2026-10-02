# BILLING V2 DUAL MODE — Relatório

Data: 2026-10-02 (UTC). Ambiente: produção EC2 `i-0f8a52f8c7982590c` (stack `atende-prod`).
Evidências: `billing-v2-evidencias/` (sanitizadas; varredura de segredos = 0 ocorrências).
Modelo comercial em linguagem simples: `docs/BILLING_V2_COMMERCIAL_MODEL.md`.

## Arquitetura (resumo)

```
outbound (IA / manual / template)
   └─ BillingGate.reserve()  ──► 402 se sem saldo
        └─ gateway /send-message|/send-template  (428 sem decisão de billing)
             └─ Meta retorna wamid ─► /internal/billing/accepted
                  └─ webhook status ─► /internal/billing/status
                       delivered/read ─► COMMIT (1x)   failed ─► RELEASE
inbound ─► nunca passa pelo gate de consumo
```

- **BillingGate** (`backend-api/app/services/billing_gate.py`): ponto único. Cada mudança de saldo acontece numa transação MySQL com `SELECT … FOR UPDATE` nos buckets do tenant, `UPDATE … WHERE available >= n` e chaves únicas de idempotência. Status chegam por uma inbox (`billing_message_status`, `INSERT IGNORE`) e são reaplicados fora de ordem em `mark_accepted`.
- **MetaRateEngine**: rate cards versionados por vigência (insert-only), resolve tarifa por categoria/mercado/data e suporta franquia gratuita por escopo (ex.: por `phone_number_id`).
- **CatalogService**: catálogo V2 (planos, recargas, crédito de marketing) e config de custos.
- **Margin Guard**: `compute_margin` + `evaluate_discount` (domínio), aplicado em proposta, atualização de proposta, conversão de lead e atribuição de plano.
- **Housekeeping** (a cada 600 s): expira buckets vencidos e move reservas paradas há mais de 1440 min para `pending_reconciliation`. Nunca estorna automaticamente.
- Sem microserviço novo: tudo dentro do `backend-api` existente, com o gateway apenas exigindo a decisão de billing.

## Semântica de uso

| Evento | Efeito |
|---|---|
| inbound | nenhum consumo |
| reserve (antes do envio) | available −1, reserved +1 |
| accepted (wamid) | vincula provider_message_id |
| delivered / read | COMMIT exatamente 1x |
| duplicado / read após delivered | noop |
| failed | RELEASE (saldo volta) |
| failed após commit | flag de reconciliação (sem estorno automático) |
| status sem reserva | nunca consome (fica pendente na inbox) |
| erro do gateway antes da Meta | RELEASE |

## Ledger

`billing_ledger` registra GRANT / RESERVE / COMMIT / RELEASE / EXPIRE / ADJUST com chave idempotente, modo de cobrança, categoria, custo Meta e versão de catálogo da época.

---

# Relatório final (§155)

## 1. Status geral
Implementado, testado e implantado em produção com `BILLING_V2_ENABLED=true` e o padrão global `customer_direct`. Backend: 99 testes PASS; ai-engine: 5 PASS; Flutter analyze sem erros (6 infos antigas); build web OK; smoke em produção 33/33 PASS. Achado fora do escopo de billing: a chave Gemini de produção é inválida (ver 53).

## 2. Commit/baseline anterior
HEAD `9089d6cdf483f89e3e82a4e54d37e43ef4739f7b` (branch atual). Já havia 10 arquivos modificados não commitados antes do início; foram preservados (sem reset), ver `baseline.txt`.

## 3. Commit/estado implantado
Não commitado (decisão do dono do repositório). O estado implantado é a árvore de trabalho atual, cujo diff completo está em `billing-v2-evidencias/baseline.patch`. Checkpoints de código em produção: `~/deploy-backups/pre-billing-v2-20261002-031105.tgz` e `pre-billing-v2-r2-*.tgz`.

## 4. Arquivos alterados
- **Backend (novos):** `api/routes/billing_v2.py`, `db/billing_v2_schema.py`, `domain/billing_v2.py`, `domain/outbound_coalescer.py`, `services/{billing_gate,meta_rate_engine,billing_catalog_service,billing_dashboard_service,billing_topup_service,outbound_billing,ai_usage_service}.py`, `tests/test_billing_v2_{domain,mysql}.py`.
- **Backend (alterados):** `main.py`, `config/settings.py`, `db/mysql.py`, `services/{dependencies,conversation_service,proposal_service,lead_service,billing_service,whatsapp_template_service,tenant_user_service}.py`, `api/routes/{proposals,leads,conversations}.py`, `domain/{proposal,lead}.py`, `repositories/{proposal,lead}_repository.py`.
- **Gateway:** `main.py` (router `/send/*` sem autenticação desmontado), `webhook.py` (428 sem decisão de billing; accepted/release/status para o backend).
- **ai-engine:** `services/ai_service.py` (usage de tokens), `tests/test_ai_usage.py`.
- **Flutter:** `services/{billing_v2_service,proposal_service,lead_service}.dart`, `services/pdf/proposal_pdf.dart`, `widgets/billing_v2_panels.dart`, `screens/{billing_hub_screen,backoffice_screen,backoffice_empresas_panels,backoffice_lead_proposal_flow,signup_dialog}.dart`.
- **Infra:** `database/migrations/010_billing_v2_dual_mode.sql`, `docker-compose.production.yml` (5 variáveis BILLING_*).
- **Docs:** este arquivo e `docs/BILLING_V2_COMMERCIAL_MODEL.md`.

## 5. Migration criada
`010_billing_v2_dual_mode.sql`: aditiva e idempotente (aplicada 2x no MySQL de homologação sem erro), com procedures auxiliares para ADD/DROP condicional. Em produção o mesmo schema é aplicado pelo bootstrap Python (`billing_v2_schema.apply`) no start do backend: 11 tabelas verificadas e seeds presentes (`migration.txt`).

## 6. Tabelas reutilizadas
`tenants`, `subscriptions`, `meta_rate_cards` (estendida: `version_code`, `unit_price`, `billing_basis`, `free_allowance`, `allowance_scope`, `tier_min/max`, `needs_review`, `source_*`; índice único trocado de `uq_meta_rate` para `uq_meta_rate_v2`), `usage_events` (rate card), `proposals` (`plan_code`, `catalog_version`, `billing_mode`, volumes, snapshot de margem), `leads` (`operational_volume`, `marketing_volume`), `billing_customers`/`billing_invoices` (Stripe), `admin_audit_logs`.

## 7. Tabelas novas
`billing_catalog_items`, `tenant_billing_config`, `billing_entitlement_buckets`, `billing_reservations`, `billing_message_status`, `billing_ledger`, `billing_topup_purchases`, `billing_cost_config`, `ai_rate_cards`, `ai_usage_events`.

## 8. BillingGate
Reserve/commit/release com locks, idempotência por `(tenant_id, idempotency_key)` e `(tenant_id, provider_message_id)`, retry em deadlock, `reserve_batch` tudo-ou-nada para campanhas, `preflight` e dry-run sem escrita. Integrado nos três caminhos de saída: auto-resposta da IA (`conversation_service`), resposta manual (`routes/conversations.py`) e templates (`whatsapp_template_service`). O gateway rejeita envio sem decisão (428).

## 9. Customer Direct
Padrão global. Operacional consome franquia/recarga (se o tenant tiver plano V2). Marketing não consome crédito pré-pago: grava `entitlement=meta_direct_tracking`, custo Meta estimado e `product_units=0`. Texto exibido: "Tarifas da Meta são cobradas diretamente pela Meta." Smoke §137 PASS.

## 10. Solution Partner Credit Line
Marketing exige créditos pré-pagos (R$ 0,55 por entregue). Sem saldo, o envio é bloqueado. Smoke §136 PASS (100 → 99/1 → 99/0/1; failed libera).

## 11. Tenant override
`PATCH /api/v1/admin/billing/tenants/{id}/billing-mode` (superadmin, `confirm=true` e motivo obrigatório, auditado). `billing_mode=null` volta ao padrão global. Cada reserva guarda o modo da época (snapshot).

## 12. Default global
`META_BILLING_DEFAULT=customer_direct` (env de produção). Fallback no compose: `customer_direct`.

## 13. Plan Catalog V2
Inicial R$197/1.000 · Essencial R$297/3.000 · Crescimento R$497/6.000 · Profissional R$897/12.000 · Empresarial sob consulta. Catálogo legado preservado (`status=legacy`). Catálogo `2026_10` (`catalog.txt`).

## 14. Operational Topups
+500 por R$49,90 e +1.000 por R$89,90, sem expiração. Consumo usa primeiro a franquia (que expira) e depois as recargas. A compra fica pendente até o pagamento; a liberação é idempotente.

## 15. Marketing Prepaid
`MARKETING_CREDIT_2026_10` a R$0,55, com pacotes. Créditos ficam guardados se o modo mudar, mas só são usados em solution_partner.

## 16. Outbound Delivered
Consome 1 unidade no primeiro delivered/read. Smoke §134 PASS.

## 17. Inbound behavior
Não consome. Smoke §133 PASS (used 0→0, 0 commits). A reserva da auto-resposta foi liberada porque o smoke não envia.

## 18. RESERVE
Antes do envio: available −1 / reserved +1 e linha RESERVE no ledger com custo Meta, versão da tarifa e preço comercial.

## 19. COMMIT
Em delivered/read: reserved −1 / consumed +1 e linha COMMIT. Exatamente uma vez (lock da reserva e estado).

## 20. RELEASE
Em failed ou erro antes da Meta: reserved −1 / available +1 e linha RELEASE.

## 21. Idempotency
Reserve repetido devolve a mesma reserva. Status duplicado vira noop via inbox. Grants de ciclo e de compra têm chave única. Testes e smoke PASS.

## 22. Concurrency
`FOR UPDATE` nos buckets e update condicional. Testes: 20 threads disputando 5 unidades nunca deixam saldo negativo; delivered paralelo duplicado commita 1x.

## 23. Pending reconciliation
Reserva sem status final há mais de 24 h vira `pending_reconciliation` (housekeeping), sem estorno automático. Divergências (failed após commit, categoria Meta ≠ gate, delivered após release) ligam a flag. A aba "Reconciliação" do console superadmin permite confirmar consumo, estornar ou marcar como verificado, com motivo e auditoria.

## 24. Rate Cards
Versões `RATE_BR_2026_07_01` e `RATE_BR_2026_10_01` (MARKETING 0,3217; UTILITY 0,035; AUTHENTICATION 0,035; SERVICE 0). Todas com `needs_review=1`. UI permite criar nova vigência e marcar como revisada.

## 25. Historical pricing
Insert-only: nova vigência nunca altera a anterior, e cada reserva grava `meta_rate_card_id`, custo unitário e `meta_rate_version`. Corrigido nesta fase: a flag "vigente" agora aponta só a versão mais recente por categoria (teste incluído).

## 26. Free allowance support
`free_allowance` + `allowance_scope` no rate card. `effective_unit_cost` zera o custo dentro da franquia gratuita.

## 27. Phone number scope
A contagem de uso prévio pode ser escopada por `phone_number_id`. Não há FK para a tabela de números (texto livre).

## 28. Meta cost tracking
Custo estimado gravado por reserva e no ledger nos dois modos. Em customer_direct entra como estimativa do cliente; em solution_partner, como custo da Atende Ai.

## 29. AI cost tracking
Pipeline pronto: o ai-engine extrai tokens de Gemini/OpenAI e o backend grava em `ai_usage_events` (testes PASS). **Em produção: 0 eventos**, porque a chave Gemini está inválida (toda chamada retorna 400) e `ai_rate_cards` está vazio (custo ficaria nulo). P1.

## 30. Margin Guard
Vermelho bloqueia (mesmo com motivo); amarelo exige motivo de superadmin (auditado); verde só com custos completos; senão "Estimativa parcial". Aplicado em: criação e atualização de proposta, **conversão de lead** e **atribuição de plano** (estes dois fechados nesta fase, pois antes aceitavam preço customizado sem guarda). Smoke §132 PASS (inclui R$10/12.000 rejeitado com 422).

## 31. Margin formula
Margem de contribuição = (preço − custos variáveis) ÷ preço. Exemplo: 130 de custo sobre 169 dá 23,08%, não markup.

## 32. Discounts
Preço abaixo do catálogo com estimativa parcial exige motivo. Amarelo exige motivo. Vermelho nunca passa.

## 33. Proposal flow
O lead informa volume operacional e volume de campanhas. A sugestão segue só o operacional: 800 → Inicial; 2.500 → Essencial; 5.000 → Crescimento; 10.000 → Profissional; 20.000 → Empresarial. Marketing gera estimativa separada (100 → R$55; 500 → R$275). Dialog com chips de plano, seletor de modo, margem ao vivo (debounce), motivo quando exigido, e PDF/salvar desabilitados se bloqueado. Smoke §131 PASS.

## 34. Lead flow
Formulário público com as duas perguntas (volume de atendimento e campanhas). Backend grava `operational_volume`/`marketing_volume` (`monthly_volume` mantido por compatibilidade). O e-mail de notificação mostra os dois volumes.

## 35. Existing proposals
Preservadas (1 proposta legado com `plan_code` nulo em produção) e marcadas como legado na UI.

## 36. Existing tenants
Sem migração automática. Tenants sem plano V2 ficam em `legacy_unmetered` para o operacional (nunca bloqueados pelo gate). Mudança para V2 só via "Atribuir plano V2" (auditado). Tenants com plano V2 não enviam mais meter event legado do Stripe.

## 37. Billing UI tenant
Card "Créditos e consumo" em Cobrança: plano, modo, barra de uso por nível, disponível/recargas/em envio, aviso de bloqueio, compra de recargas (Stripe TEST ou pendente), créditos de campanha (SP) ou aviso Meta direto (CD) e movimentações.

## 38. Billing UI superadmin
- Empresas → empresa → Assinatura: painel V2 com modo e origem, plano, troca de modo com motivo, atribuir plano, concessões manuais, consumo (recebidas não consomem), receita, custos, contribuição, margem e compras ("Marcar paga").
- Chip "Cobrança V2": console com visão geral, tarifas Meta, custos e margem, e reconciliação.

## 39. Rate Card UI
Tabela por versão/categoria/valor/vigência ("vigente"), situação Revisar/Revisada, "Nova vigência" (insert-only, motivo obrigatório) e "Marcar revisada".

## 40. Ledger
Ver seção "Ledger" acima. Exposto em `/api/v1/billing/v2/ledger` e na UI.

## 41. RBAC
Endpoints do tenant exigem `canManageBilling` (owner/admin) com escopo de tenant. Endpoints admin exigem superadmin. Agente/atendente recebem 403 (testes). Endpoints internos exigem `X-Internal-API-Key` (403 sem). Sem token: 401 (verificado em produção).

## 42. AI message consolidation
`coalesce_text_parts` consolida a resposta da IA numa única mensagem de saída (1 unidade), evitando consumo fragmentado.

## 43. Stripe TEST
Checkout de recarga só com chave de teste (senão a compra fica pendente). Webhook com `livemode=true` é rejeitado para recargas V2. Grant idempotente. Stripe LIVE não foi ativado nem alterado.

## 44. Dry-run
Simulação do painel e `reserve(dry_run=True)` não criam reserva nem ledger e não alteram saldo. Smoke §138 PASS.

## 45. Backend tests
99 passed (`tests-backend.txt`). Cobrem domínio, MySQL real descartável (`billing_v2_test`), concorrência, idempotência, modos, marketing, margem, propostas, RBAC, dry-run, reconciliação, rate cards insert-only e logs de billing.

## 46. Flutter analyze
`dart analyze lib`: 0 erros e 0 warnings; 6 infos antigas (deprecated `value` em outras telas).

## 47. Flutter build
`flutter build web --release` OK. O bundle em produção é idêntico ao local (md5 `95d1e8ca595fc3cb06efd0238f3293d2`).

## 48. Compose
`config --quiet` OK. Novas variáveis com defaults seguros (`BILLING_V2_ENABLED` com default false; `META_BILLING_DEFAULT` com default customer_direct). Nenhuma porta nova.

## 49. Production deploy
1. Backup do banco (gzip -t OK, 28 tabelas) e checkpoint de código.
2. Sync de backend, gateway, ai-engine, migrations, compose e build web.
3. Build sequencial com memória monitorada; up na ordem backend → ai-engine → gateway; todos healthy.
4. Verificação do schema.
5. `BILLING_V2_ENABLED=true` e `META_BILLING_DEFAULT=customer_direct` acrescentados ao env, sem ler o arquivo (backup chmod 600; `cmp` prova que só houve acréscimo).
6. Restart controlado da stack: persistência OK.
7. Segundo deploy (backend + web) com novo backup.

## 50. Public smoke
meuatendeai.com.br 200, painel 200, api/health 200 (healthy). Billing em produção: 33/33 (`production-smoke.txt`). O tenant fixture `[SMOKE] Billing V2` ficou marcado `inactive/canceled` (sem exclusão) e a proposta smoke como `rejected`.

## 51. Security
`ss -lntp`: 22/80/443 públicos, 8080 só loopback, 3306 não exposto. Nenhum segredo em evidências. `.env.production` nunca lido. Meta (App/WABA/Webhook/Embedded Signup/Coexistence) inalterada. Centralized billing não ativado. Nenhuma campanha real disparada.

## 52. Performance
Reserve: cerca de 8–10 queries indexadas numa transação (tenant, ciclo, config, tarifa, lock de buckets, update, insert, ledger, nível). Status: inbox + lock + update. Índices por status/data, tenant/data, categoria, modo e telefone. Rate cards não são cacheados, por consistência entre vigências. Volume atual não justifica cache.

## 53. Findings
1. **Chave Gemini de produção inválida** (`API_KEY_INVALID`, 400 em toda chamada). Pré-existente: o env está inalterado desde 2026-09-25 (provado por `cmp` com o backup). Efeito: as auto-respostas de IA em produção caem no fallback e o custo de IA não é registrado. Precisa de uma chave nova (ação do dono; não lida nem alterada aqui).
2. Corrigido: índice antigo `uq_meta_rate` não era removido após a migration SQL.
3. Corrigido: `marketing_lite` era classificado como SERVICE.
4. Corrigido: a flag "vigente" marcava todas as versões passadas.
5. Corrigido: conversão de lead e atribuição de plano aceitavam preço com prejuízo (margin guard ausente).
6. Migration 009 falha num banco vazio (`s.group_id`). Pré-existente; o bootstrap Python cobre. Não alterada.
7. O gateway aceita `billing_enforced=false` de chamadores internos (o backend só envia isso com V2 desligado). Endurecer na próxima iteração.
8. `scripts/test-whatsapp-api.ps1` vai receber 428 (sem decisão de billing).
9. Ainda não existe feature de campanha em massa; `reserve_batch` está pronto para ela.
10. §129: login interativo do superadmin e inspeção visual das telas não foram executados por mim (sem a senha). Validados: 401/403, endpoints superadmin com token efêmero e bundle novo servido.

## 54. P0
Nenhum. Verificados: saldo não fica negativo sob concorrência, webhook duplicado não cobra duas vezes, inbound não consome, failed libera, marketing não excede o pré-pago, todos os caminhos de saída passam pelo gate, migration não perdeu dados, isolamento por tenant, agente sem acesso a billing, Stripe LIVE desligado, Meta inalterada, produção healthy, nenhum segredo exposto.

## 55. P1
- Chave Gemini inválida (bloqueia o passo de IA do Meta E2E) e `ai_rate_cards` vazio (custo de IA nulo).
- Custos de impostos e de taxa de pagamento não configurados, o que deixa as margens como "Estimativa parcial".
- Todas as tarifas Meta com `needs_review=1` (conferir na fonte oficial, especialmente SERVICE = 0).
- Endurecer o gateway para exigir reserva quando V2 estiver ativo.

## 56. P2
Gráficos avançados, exportações, forecast, recomendação por ML, S3, PDF de fatura customizado, analytics avançado.

## 57. Billing V2 pronto?
Sim. Todos os critérios do §154 foram atendidos: migrations, testes, Flutter, produção healthy, inbound/delivered/failed/duplicado, dual mode, marketing pré-pago, rate cards versionados, margin guard, proposta V2, legado preservado, dry-run sem cobrança e nenhum P0.

## 58. Pronto para Meta E2E?
Sim do lado do billing. **Pré-requisito antes do E2E:** trocar a chave Gemini de produção (hoje inválida). Sem isso, o passo "AI" do fluxo E2E responde com fallback e não registra custo de IA.

## 59. Próximo passo recomendado
1. Configurar uma chave Gemini válida (e, idealmente, um `GEMINI_MODEL` atual) e recriar o ai-engine.
2. Cadastrar `ai_rate_cards`, a taxa de pagamento e os impostos; revisar as tarifas Meta.
3. Fazer o login visual do superadmin.
4. Iniciar a fase META LIVE E2E: WhatsApp real → inbound → webhook → backend → IA → BillingGate → outbound → Meta → delivered/read → COMMIT real, validando customer_direct contra solution_partner_credit_line.
5. Depois, Stripe LIVE; por fim, backup S3.

**BILLING V2 DUAL MODE — IMPLEMENTADO E PRONTO PARA META E2E**
