# Project Status

## Visao geral
Este projeto e um SaaS de chatbot para WhatsApp com arquitetura em servicos e painel administrativo em Flutter Web.

Modulos atuais:
- `whatsapp-gateway`: recebe eventos do WhatsApp Cloud API e envia respostas.
- `backend-api`: orquestra autenticacao, tenants, sessoes, simulacao, fluxos e cobranca.
- `flow-engine`: interpreta fluxos YAML e decide quando a conversa foi tratada por fluxo.
- `ai-engine`: faz deteccao de intencao e fallback generativo.
- `database`: schema, migrations e seed MySQL.
- `admin-panel`: painel Flutter Web para operacao SaaS e configuracao dos chatbots.
- `infra`: `docker-compose` e subida local do ambiente.

## Stack atual
- Python + FastAPI
- Flutter Web
- MySQL 8
- Docker Compose
- WhatsApp Cloud API
- Fluxos YAML com persistencia em MySQL
- IA generativa com Google Gemini

## Arquitetura funcional
### Conversa hibrida
Fluxo da mensagem:
1. `backend-api` recebe a mensagem.
2. `ai-engine` pode detectar intencao antes do fluxo.
3. `flow-engine` tenta resolver pelo fluxo do tenant.
4. Se o fluxo nao resolver, o `ai-engine` responde por fallback.
5. O resultado e salvo em sessao, mensagens e logs.

### Sessao
Cada sessao armazena:
- `session_id`
- `tenant_id`
- `phone_number`
- `active_flow`
- `current_state`
- `detected_intent`
- `conversation_history`
- `last_interaction`

### Multi-tenant
Cada cliente possui isolamento por `tenant_id` para:
- usuarios
- sessoes
- mensagens
- configuracoes
- assinatura
- contas WhatsApp
- fluxos
- logs

## Banco de dados
Schema principal:
- `tenants`
- `users`
- `tenant_settings`
- `subscriptions`
- `email_deliveries`
- `billing_customers`
- `billing_invoices`
- `whatsapp_accounts`
- `sessions`
- `messages`
- `conversation_logs`
- `flows`
- `flow_states`
- `flow_transitions`
- `flow_documents`

Arquivos principais:
- `database/schema.sql`
- `database/seed.sql`
- `database/migrations/001_init_saas_mysql.sql`
- `database/migrations/002_seed_demo_mysql.sql`

## Autenticacao e perfis
Login padrao atual:
- Email: `admin@demo.local`
- Senha: `admin1234`

Perfis tratados pelo painel e backend:
- `owner`
- `manager`
- `agent`
- `superadmin`
- `system-admin` / `system_admin`

### Convites e reset de senha
Fluxo implementado:
1. `system-admin` ou gestor convida um usuario no backoffice.
2. O backend gera token temporario e `action_url`.
3. O backend tenta enviar o convite por SMTP em email real.
4. O usuario abre `/#/accept-invite?token=...` e define a senha.
5. Para reset, o fluxo equivalente usa `/#/reset-password?token=...`.
6. O painel conclui a acao e devolve o usuario para a tela de login.

Observacao:
- a variavel `ADMIN_PANEL_URL` do `backend-api` deve apontar para a URL real do painel Flutter Web, para que os links de convite e reset saiam corretos em cada ambiente.
- para envio real de email, configure `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM_EMAIL` e `SMTP_FROM_NAME`.

### Regra do system-admin
O `system-admin` funciona como operador interno do SaaS:
- nao depende de plano para operar o backoffice
- nao possui fluxo operacional proprio
- nao usa conta WhatsApp propria no atendimento
- pode visualizar e editar os tenants dos clientes
- pode abrir e visualizar os fluxos dos clientes no editor

## Admin Panel
### O que existe hoje
- login persistente com restauracao de sessao
- seletor de tenant ativo para `superadmin/system-admin`
- shell moderno com modulos de:
  - visao geral
  - conversas
  - fluxos
  - billing
  - backoffice
- tela de conversas
- dashboard SaaS com metricas por tenant e por plano
- editor visual de fluxos com geracao automatica de YAML
- simulador de conversa ligado ao backend real
- configuracao de IA por tenant
- card de plano e consumo
- card de contas WhatsApp
- backoffice SaaS para listar e criar tenants
- visualizacao de tenants, plano, uso, contas WhatsApp e fluxos sem Workbench
- backoffice com usuarios do tenant e auditoria recente
- aceite de convite e redefinicao de senha por link/token no Flutter Web

### Backoffice SaaS
A tela de backoffice permite:
- listar tenants
- pesquisar tenants
- criar novo tenant
- selecionar um tenant ativo
- ver resumo do tenant
- fazer upgrade e downgrade de plano
- alterar status da assinatura
- alterar limite mensal
- visualizar bloqueio visual por assinatura
- criar conta WhatsApp
- editar conta WhatsApp existente
- trocar conta principal
- listar usuarios do tenant
- convidar usuarios do tenant
- editar perfil e status dos usuarios
- gerar reset de senha por usuario
- ver status de entrega de email ao convidar/resetar usuario
- acompanhar auditoria administrativa recente
- abrir o editor de fluxos do cliente selecionado

### Acabamento visual e UX fino
Ultima rodada focada em polish visual do `Flow Builder` e do `Backoffice`:
- sidebar do editor com resumo do workspace e melhor leitura do contexto atual
- cards de passos com cabecalho mais forte, resumo da mensagem e badges de botoes, palavras-chave e intencoes
- secoes internas do passo com linguagem mais simples para usuarios nao tecnicos
- preview da conversa com estado vazio mais explicativo e leitura mais proxima de um simulador real
- backoffice com card-resumo operacional na coluna de tenants
- cards de tenants com melhor hierarquia visual, selo de contexto ativo e informacao de atualizacao
- topo do detalhe do tenant transformado em hero card com plano, status, uso e atalhos
- card de cobranca com melhor responsividade em larguras menores

### Dashboard SaaS
O dashboard agora possui:
- visao global para `superadmin/system-admin`
- visao operacional por tenant para clientes
- KPIs de uso, plano e status
- distribuicao por plano
- ranking de tenants por consumo
- eventos administrativos recentes
- atalhos rapidos para conversas, fluxos, billing e backoffice

### Bloqueio visual
Quando a assinatura do tenant esta inativa:
- o painel mostra aviso visual de bloqueio
- o editor continua visivel para consulta
- salvar fluxo fica bloqueado
- alterar IA fica bloqueado
- criar fluxos novos fica bloqueado

## Billing
### Camada comercial implementada
Hoje o backend ja possui:
- resumo de billing por tenant
- checkout de assinatura
- portal do cliente
- sincronizacao de customer e invoices
- webhook Stripe para eventos de:
  - `checkout.session.completed`
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
  - `invoice.paid`
  - `invoice.payment_failed`
- mudanca automatica para `past_due` apos janela de tolerancia
- bloqueio automatico de processamento quando a assinatura deixa de ser valida

Endpoints novos:
- `GET /api/v1/dashboard/overview`
- `GET /api/v1/billing/summary`
- `POST /api/v1/billing/checkout-session`
- `POST /api/v1/billing/portal-session`
- `POST /api/v1/billing/webhooks/stripe`

Configuracoes de ambiente:
- `BILLING_PROVIDER`
- `BILLING_GRACE_DAYS`
- `BILLING_SUCCESS_URL`
- `BILLING_CANCEL_URL`
- `BILLING_PORTAL_RETURN_URL`
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRICE_STARTER`
- `STRIPE_PRICE_GROWTH`
- `STRIPE_PRICE_PRO`
- `STRIPE_PRICE_ENTERPRISE`

## Fluxos
### Estado atual
- o editor visual gera YAML automaticamente
- nomes tecnicos foram simplificados
- IDs internos de passos e botoes sao gerados automaticamente
- passos aceitam:
  - mensagem
  - botoes
  - proximo passo
  - palavras digitadas pelo cliente
  - `intent_triggers`
  - encaminhamento para atendente humano
  - hook de integracao

### Observacao importante
Quando o usuario loga como `system-admin`, o editor deve ser aberto a partir do backoffice com um tenant cliente selecionado. O tenant interno do sistema nao e usado para atendimento.

## WhatsApp accounts
Cada tenant pode possuir multiplas contas WhatsApp.

Campos principais:
- `account_key`
- `display_name`
- `phone_number_id`
- `display_phone_number`
- `verify_token`
- `access_token` criptografado
- `status`
- `is_default`

O painel hoje permite criar, editar e definir a conta principal.

## Auditoria
Eventos administrativos hoje registrados:
- criacao de tenant
- alteracao de assinatura/plano
- criacao e edicao de conta WhatsApp
- convite de usuario
- geracao de reset de senha
- salvamento de fluxo

Endpoints relacionados:
- `GET /api/v1/admin/audit-logs`
- `GET /api/v1/tenants/{tenant_id}/users`
- `POST /api/v1/tenants/{tenant_id}/users/invite`
- `PATCH /api/v1/tenants/{tenant_id}/users/{user_id}`
- `POST /api/v1/tenants/{tenant_id}/users/{user_id}/reset-password`
- `POST /api/v1/auth/complete-invite`
- `POST /api/v1/auth/reset-password/confirm`

## IA
### Regras implementadas
- fallback generativo com Gemini
- lista de modelos configuravel por tenant
- suporte a varios modelos de fallback
- `debug_mode` por tenant
- prompt com data atual
- instrucoes para nao assumir acesso a internet ou fatos recentes

## Docker e execucao local
Subida local:
```bash
cd infra
docker compose up --build -d
```

Health checks esperados:
- `http://localhost:8000/health`
- `http://localhost:8002/health`
- `http://localhost:8003/health`
- `http://localhost:40000/health`

## MySQL Workbench
Configuracao local atual:
- Host: `127.0.0.1`
- Porta: `3310`
- Usuario: `chatbot`
- Senha: `chatbot`
- Schema: `chatbot`

Usuario root:
- Usuario: `root`
- Senha: `root`

## Tenants demo provisionados
Ja existem tenants de demonstracao criados para smoke test e UX review:
- `default`
- `loja_centro_demo`
- `restaurante_sabor_demo`

Dados de exemplo provisionados:
- `loja_centro_demo`: plano `growth`, fluxos base clonados, conta WhatsApp demo, usuario owner e um usuario manager de teste
- `restaurante_sabor_demo`: plano `pro`, fluxos base clonados, conta WhatsApp demo

## Principais arquivos alterados recentemente
Backend:
- `backend-api/app/api/access.py`
- `backend-api/app/api/routes/admin_audit_logs.py`
- `backend-api/app/api/routes/admin_tenants.py`
- `backend-api/app/api/routes/admin_users.py`
- `backend-api/app/api/routes/auth.py`
- `backend-api/app/api/routes/billing.py`
- `backend-api/app/api/routes/billing_webhooks.py`
- `backend-api/app/api/routes/dashboard.py`
- `backend-api/app/api/routes/flows_admin.py`
- `backend-api/app/api/routes/subscriptions.py`
- `backend-api/app/api/routes/tenant_settings.py`
- `backend-api/app/api/routes/whatsapp_accounts.py`
- `backend-api/app/domain/admin_audit.py`
- `backend-api/app/domain/billing.py`
- `backend-api/app/domain/dashboard_metrics.py`
- `backend-api/app/domain/email_dispatch.py`
- `backend-api/app/domain/user_admin.py`
- `backend-api/app/domain/whatsapp_account.py`
- `backend-api/app/services/admin_audit_service.py`
- `backend-api/app/services/billing_service.py`
- `backend-api/app/services/dashboard_service.py`
- `backend-api/app/services/email_service.py`
- `backend-api/app/services/tenant_admin_service.py`
- `backend-api/app/services/tenant_user_service.py`
- `backend-api/app/services/subscription_service.py`
- `backend-api/app/services/whatsapp_account_service.py`

Frontend:
- `admin-panel/lib/main.dart`
- `admin-panel/lib/models/admin_audit_entry.dart`
- `admin-panel/lib/models/billing_summary.dart`
- `admin-panel/lib/models/dashboard_overview.dart`
- `admin-panel/lib/models/tenant_user.dart`
- `admin-panel/lib/services/auth_service.dart`
- `admin-panel/lib/services/admin_audit_service.dart`
- `admin-panel/lib/services/admin_tenant_service.dart`
- `admin-panel/lib/services/billing_service.dart`
- `admin-panel/lib/services/dashboard_service.dart`
- `admin-panel/lib/services/subscription_service.dart`
- `admin-panel/lib/services/tenant_user_service.dart`
- `admin-panel/lib/services/whatsapp_account_service.dart`
- `admin-panel/lib/widgets/app_sidebar.dart`
- `admin-panel/lib/screens/billing_hub_screen.dart`
- `admin-panel/lib/screens/dashboard_screen.dart`
- `admin-panel/lib/screens/overview_screen.dart`
- `admin-panel/lib/screens/token_action_screen.dart`
- `admin-panel/lib/screens/settings_screen.dart`
- `admin-panel/lib/screens/backoffice_screen.dart`

## Ponto atual do produto
O projeto ja esta em um ponto forte para demonstracao comercial e onboarding inicial de clientes:
- multi-tenant funcional
- painel com backoffice
- configuracao visual dos fluxos
- simulacao integrada
- contas WhatsApp por tenant
- plano e bloqueio visual no painel
- gestao de usuarios por tenant
- convite e reset de senha com tentativa de envio real por email
- auditoria administrativa basica
- dashboard SaaS com metricas e atalhos
- billing real preparado para Stripe
- tenants demo prontos para validacao visual

## Proximos passos recomendados
Para deixar o produto ainda mais forte para venda recorrente:
1. incluir exclusao/desativacao segura de contas WhatsApp via painel
2. integrar provedor de email transacional com reputacao e templates versionados
3. concluir conciliacao financeira e status via webhook em ambiente real Stripe
4. registrar auditoria tambem para aceite de convite, login e alteracoes de IA
5. criar testes automatizados para fluxo, assinatura, usuarios e backoffice
6. adicionar dashboard financeiro com receita realizada e churn por periodo
- `admin@demo.local` / `admin1234`

## Admin Panel - rodada visual mais recente
O `admin-panel` passou por uma rodada focada em UX visual e traducao para portugues.

Principais mudancas:
- nova identidade visual com design system compartilhado em:
  - `admin-panel/lib/theme/app_tokens.dart`
  - `admin-panel/lib/theme/app_theme.dart`
  - `admin-panel/lib/widgets/ui_kit.dart`
- dashboard transformado em `Central de Acao`
- nova navegacao principal:
  - `Conversas`
  - `Automações`
  - `Clientes`
  - `Cobrança`
  - `Configurações`
- sidebar reformulada com destaque de empresa em foco
- tela de conversas com visual mais proximo de WhatsApp Web
- tela de detalhes da conversa com:
  - bolhas redesenhadas
  - input fixo
  - status de IA / atendimento humano
  - painel lateral de resumo
- nova tela `Configurações` para IA, plano e contexto da empresa
- `Flow Builder` com termos simplificados:
  - `Fluxos` -> `Automações`
  - `Passos` -> `Etapas`
  - simulador com envio de mensagens
- backoffice com linguagem orientada a `Empresa`

Arquivos visuais principais desta rodada:
- `admin-panel/lib/main.dart`
- `admin-panel/lib/screens/dashboard_screen.dart`
- `admin-panel/lib/screens/overview_screen.dart`
- `admin-panel/lib/screens/conversation_detail_screen.dart`
- `admin-panel/lib/screens/settings_hub_screen.dart`
- `admin-panel/lib/screens/settings_screen.dart`
- `admin-panel/lib/screens/backoffice_screen.dart`
- `admin-panel/lib/widgets/app_sidebar.dart`
- `admin-panel/lib/widgets/conversation_list.dart`
- `admin-panel/lib/widgets/message_bubble.dart`
