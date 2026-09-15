# PRODUCT_HARDENING_REPORT

## 1. Status geral

**IMPLEMENTADO (P0–P2 core)** — dry-run de automação, RBAC, inbox operacional (IA/humano/transfer/grupos), quick replies, templates (pt_BR + categorias), billing tenant + on-demand + usage ledger, fiscal stub, WhatsApp sem Assistente, login/logo/favicon. Validado com testes unitários (6), dart analyze (infos), flutter release build, compose config, schema MySQL e rotas no backend recriado.

Não é deploy AWS. Stripe/NFS-e reais dependem de credenciais externas.

## 2. Baseline

- Path: `/home/arthur/Área de trabalho/chatbot`
- Branch: `main`
- HEAD: `0788c57 Refactor billing hub and team screens…`
- Dirty tree pré-existente: production readiness (compose/nginx/docs/env)

## 3. Arquivos alterados (principais)

**Backend:** `access.py`, `execution_context.py`, `conversation_service.py`, `conversations.py`, `simulation.py`, `billing.py`, `subscription_service.py`, `billing_service.py`, `session.py`, `session_repository.py`, `session_service.py`, `mysql.py`, `main.py`, `dependencies.py`, `settings.py`, novos services/routes (groups, quick_replies, usage, fiscal), `009_product_hardening.sql`, `tests/test_product_hardening.py`

**Gateway:** `webhook.py` (delivered → usage)

**Flutter:** capabilities, dashboard/sidebar, groups/quick_replies/billing_plan screens, conversation list/detail, templates, whatsapp (sem Assistente), login/logo/favicon/manifest

**Docs:** `OPERATIONAL_INBOX.md`, `RBAC.md`, `BILLING_AND_USAGE.md`

## 4. Migrations

- `database/migrations/009_product_hardening.sql`
- Bootstrap idempotente em `MySQLDatabase._ensure_product_hardening_schema`
- Tabelas confirmadas: conversation_groups, quick_replies, usage_events, meta_rate_cards, fiscal_documents
- Colunas sessions: assignment_mode, assigned_user_id, group_id

## 5. Bug Testar Automação

Corrigido. `POST /simulation/send` usa `ExecutionContext.dry_run()` → `persist=False` (sem session/message/log DB, sem billing). Resposta visual preservada.

## 6. RBAC

`capabilities_for` + `assert_capability` / `assert_tenant_admin`. Mutations de flows/actions/templates/groups/billing exigem capability.

## 7. Roles

Reuso: `owner`/`manager` = tenant admin; `agent`/`member` = agente; superadmin aliases preservados.

## 8. Sidebar Admin

Visão Geral, Conversas, Automações, Ações, Templates, Grupos, Respostas rápidas, WhatsApp, Equipe, Plano e cobrança.

## 9. Sidebar Agent

Visão Geral, Conversas, Respostas rápidas (sem admin modules).

## 10. Conversation Assignment

`assignment_mode` ai|human + `assigned_user_id`. Default IA. Endpoints assume/transfer/return-to-ai.

## 11. AI Pause/Resume

Human-owned: inbound persiste, `reply_text=""`. Late-check antes de enviar flow/AI. Devolver → próximas mensagens.

## 12. Transferência

Mesmo tenant, usuário `active` apenas. Auditoria `conversation.transfer`.

## 13. Concorrência

Assume com 409 se outro humano já for owner (`Esta conversa foi assumida por …`).

## 14. Grupos

CRUD + membros. Admin only para mutations.

## 15. Grupo Geral

Criação idempotente `is_default=1`, não removível, backfill sessions.

## 16. Filtros

Backend: `filter=all|mine|ai|human` + `group_id`. Esconde phones de simulation legado.

## 17. Equipe

Sem reescrita; RBAC já bloqueava agent em user management.

## 18. Respostas rápidas

CRUD pessoal; composer `/` + ícone; insert sem auto-send.

## 19. Templates

`+ Novo template`; CRUD admin-only no backend create.

## 20. Categoria Meta

Cards MARKETING / UTILITY / AUTHENTICATION com textos explicativos + estimativa rate card.

## 21. pt_BR

Idioma fixo (sem dropdown).

## 22. WhatsApp

CTA **Assistente** removido da visão cliente.

## 23. Plano e cobrança

Menu tenant admin → `billing_plan_screen` + API summary/checkout/portal com `canManageBilling`.

## 24. On-demand

Plano `on_demand` no domínio/limites/billing; meter env-driven.

## 25. Meta Billing

Texto/docs: Meta cobra o cliente diretamente. Rate cards = estimativa.

## 26. Stripe Billing

Checkout/portal existentes; meter events best-effort; TEST mode via env.

## 27. Usage Ledger

`usage_events` idempotente; gateway `delivered` → internal endpoint.

## 28. Fiscal/NFS-e

`FiscalProvider` + UI “não configurado”. Sem PDF fake.

## 29. Login

Atmosfera dark + rede animada (reduced motion).

## 30. Nova marca

`AtendaLogo` vetorial (isotipo + wordmark).

## 31. Favicon

`web/favicon.png` + icons/manifest/title atualizados; release build inclui favicon não-Flutter.

## 32. Stitch utilizado

MCP disponível; implementação visual no DS V2 + assets locais (sem entidades fictícias de mock).

## 33. Tests backend

6 passed: dry_run, RBAC, on_demand, shortcut, usage unique, human_owned helper.

## 34. Tests Flutter

Analyzer limpo de errors (6 infos legados). Sem golden suite completa (escopo).

## 35. Multi-tenant

resolve_tenant_scope + ownership em groups/quick replies/transfer.

## 36. Builds

`flutter build web --release` PASS.

## 37. Docker regression

`docker-compose.production.yml config` PASS. Backend infra recriado com novas rotas.

## 38. Smoke Admin

Parcial automatizado (health/routes/schema/build). Smoke UI completo depende sessão autenticada local.

## 39. Smoke Agent

Capabilities/sidebar preparados; smoke UI com user agent pendente de sessão.

## 40. Screenshots

Diretório criado; capturas UI manuais listadas no README de evidências.

## 41. Findings

- `.dockerignore` do backend exclui `tests/` (pytest precisa docker cp ou ajuste).
- Billing summary ainda depende Stripe provider_ready para dados ricos.
- Sessões antigas de simulation-user podem existir; lista agora filtra.

## 42. Blockers externos

- Stripe TEST keys / meter IDs para cobrança on-demand live-test.
- Provider NFS-e + dados fiscais homologados.
- Conta AWS/DNS/TLS (fora de escopo).

## 43. Pendências

**P0 residual:** evidência runtime “Testar” com count conversas antes/depois via UI autenticada.

**P1:** proration Stripe detalhada; export CSV na UI; transfer picker polish.

**P2:** mais variantes de logo; golden tests Flutter.

**P3:** remover `tests` do dockerignore ou imagem de CI dedicada.

## 44. Produto pronto para primeiro cliente?

**Quase — com caveats.** Funcionalmente pronto para piloto local/homolog com tenant admin + agentes, desde que Stripe test e WhatsApp Meta estejam configurados. Fiscal e cobrança Meta continuam externos. Não declarar “produção AWS” sem deploy.

## 45. Próximo passo

1. Smoke autenticado: Testar automação (counts), assume/transfer/devolver, grupos, quick replies, billing screen.
2. Configurar Stripe TEST + `STRIPE_ON_DEMAND_PRICE_ID`.
3. Escolher provider NFS-e quando autorizado.
4. Deploy EC2 conforme `docs/DEPLOY_AWS_EC2.md` (fora desta etapa).
