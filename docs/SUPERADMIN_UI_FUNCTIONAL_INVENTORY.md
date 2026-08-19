# Inventário funcional da UI Super Admin — Atenda Ai

Documento de auditoria. Fonte de verdade para redesign (Stitch).

Escopo: o que o painel Flutter e a API **fazem hoje** para o perfil Super Admin. Sem propostas de produto.

Data da auditoria: 2026-08-14.

Código lido: `admin-panel/lib/**`, `backend-api/app/api/**`, serviços e modelos citados em cada seção.

---

## Como o Super Admin entra e o que isso significa

Não há rotas nomeadas após o login. `admin-panel/lib/main.dart` monta `DashboardScreen` se `authService.isAuthenticated`.

Roles tratadas como Super Admin (Flutter `auth_service.dart` e API `app/api/access.py`):

- `superadmin`
- `system-admin`
- `system_admin`
- `systemadmin`

Login: `POST /api/v1/auth/login`. Sessão: `GET /api/v1/auth/me`.

O usuário Super Admin pertence a um **tenant home** (`AppUser.tenantId`, em geral `default` / `DEFAULT_TENANT_ID`). Esse registro é um tenant no banco, não um “cliente comercial”.

Contexto ativo:

- `authService.tenantId` = tenant selecionado (`x-tenant-id` em todas as chamadas HTTP do `ApiClient`).
- Super Admin pode trocar o contexto ao clicar uma empresa em Clientes (`authService.setActiveTenantId`).
- Enquanto o contexto for o tenant home, várias telas tratam **conta interna do sistema** (`_isSystemHomeContext` / `_isSystemTenantContext`).

Não existe item de menu chamado “Tenant”. O menu chama **Clientes**; a API e o banco chamam **tenant** (`tenants.external_key` = `tenant_id`).

---

## Conceitos de domínio (como o código usa hoje)

Estes nomes **não são sinônimos**. Relação atual:

| Conceito | Onde aparece na UI | Onde aparece no código/API | Relação |
| --- | --- | --- | --- |
| **Cliente** | Item de sidebar “Clientes”; texto “Selecione um cliente para ver a cobrança”; “Abrir área de clientes” | Apenas rótulo de UI. Não há entidade `Cliente`. | Aponta para a tela de **tenants** (`BackofficeScreen`). |
| **Tenant** | Campo “Tenant ID (slug)” no dialog de conversão de lead; header `x-tenant-id` | Tabela `tenants`; `tenant_id` / `external_key`; `GET/POST /api/v1/admin/tenants` | Unidade SaaS. Uma empresa comercial **é** um tenant. A conta interna `default` também é um tenant. |
| **Empresa** | Tabs “Empresas”; “Nova empresa”; cards com `tenant.name` | Mesmo registro de tenant (`name`, `email`, `plan`, `status`) | Rótulo de UI para o tenant comercial (e para o tenant sistema, com badge “Sistema”). |
| **Lead** | Tab “Leads” em Clientes | Tabela/API de leads; `GET/PATCH /api/v1/admin/leads`; criação pública `POST /api/v1/public/leads` | Prospecto da landing. **Não** é tenant até “Cadastrar empresa”. |
| **Proposta** | Dialog “Gerar proposta” no card do lead | `GET/POST/PATCH /api/v1/admin/proposals`; recomendação `GET /api/v1/admin/leads/{id}/recommendation` | Documento comercial ligado a um `lead_id`. Pode ter `tenant_id` nulo. **Não há tela de listagem de propostas.** |
| **Assinatura** | Painel “Assinatura e cobrança” no detalhe da empresa; tela Cobrança | Tabela `subscriptions`; `GET/PATCH /api/v1/subscriptions/{tenant_id}`; resumo Stripe `GET /api/v1/billing/summary` | 1:1 com tenant comercial. Campos: `plan`, `status`, `renewal_date`, `monthly_message_limit`, uso de mensagens. |

Fluxo existente: Landing cria **Lead** → Super Admin gera **Proposta** (opcional) e/ou **converte** o lead em **tenant/empresa** (`POST /api/v1/admin/leads/{id}/convert`) com **assinatura** inicial.

---

## Shell (comum a todas as telas autenticadas)

**Arquivo:** `admin-panel/lib/screens/dashboard_screen.dart` + `admin-panel/lib/widgets/app_sidebar.dart`

**Rota/estado:** `home:` autenticado → `DashboardScreen`. Navegação interna: `_selectedNav`.

**Sidebar Super Admin (itens `visible`):**

| Item | `id` | Visível Super Admin | Visível tenant comum |
| --- | --- | --- | --- |
| Marca “Atenda Ai” (home) | `home` | sim (tap no brand) | sim |
| Conversas | `conversations` | sim | sim |
| Automações | `automations` | sim | sim |
| Ações | `actions` | sim | sim |
| Templates | `templates` | sim | sim |
| WhatsApp | `whatsapp` | **não** | sim |
| Equipe | `team` | **não** | sim |
| Clientes | `clients` | **sim** | não |
| Cobrança | `billing` | **sim** | não |

Footer: e-mail truncado, role humanizada (`Superadministrador` / `Administrador do sistema`), `tenantId` ativo, logout (`authService.logout()`).

Header de página (`_ShellHeader`): título + subtítulo + pill do `tenantId` ativo. **Não aparece na home** quando a sidebar é persistente (`width >= 1100`).

Logout: implementado.

---

## 1. Visão geral (home)

### Identificação

- Nome exibido: `overview.tenantName` da API, ou “Visão geral”. No contexto sistema a API devolve `tenant_name`: **"Operacao SaaS"**.
- Arquivo: `admin-panel/lib/screens/overview_screen.dart` + `operation_hub_panel.dart`
- Estado: `_selectedNav == 'home'` (brand)
- Menu: marca Atenda Ai
- Role: qualquer autenticado; layout Super Admin no tenant home é o ramo `_isSystemHomeContext`

### Conteúdo realmente pintado

**Faixa de KPIs (`AppKpiStrip`) — cinco cards.** Estes são os únicos KPIs da faixa. Origem:

| Rótulo na UI | Valor | Origem real |
| --- | --- | --- |
| Fila | `conversations.where(unreadCount > 0).length` | `GET /api/v1/conversations` no tenant do header `x-tenant-id` (no home, o tenant sistema) |
| Hoje | Se existir KPI da API cujo `label` contém `"mensag"`, usa `kpi.value`; senão conta conversas com `updatedAt` no dia civil local | No home Super Admin a API global envia KPI **"Mensagens do mes"** (entradas `messages.direction = incoming` desde o 1º dia do mês, excluindo tenant `default`). A UI **rotula isso como “Hoje”**. |
| Consumo | Se `monthlyMessageLimit <= 0`: `"{usedMessages} msgs"`; senão `"{pct}% do limite"` | No home Super Admin **não chama** `GET /api/v1/subscriptions/{id}`. Usa `SubscriptionInfo` **hardcoded** no Flutter: `plan: enterprise`, `status: active`, `monthlyMessageLimit: 0`, `usedMessages: 0` → valor **"0 msgs"**. |
| WhatsApp | Sem contas: “Não configurado”; senão `"{n} conectada(s)"` se `status == active` | No home Super Admin **não chama** listagem WhatsApp; lista vazia forçada → sempre **“Não configurado”**. |
| Plano | `operationPlanLabel(subscription.plan)` | Mesmo hardcoded `enterprise` → **“Empresarial”**. Hint: `operationStatusLabel("active")` → **“Ativo”**. |

A API `GET /api/v1/dashboard/overview` no home Super Admin (`requested_tenant_id == DEFAULT_TENANT_ID`) **calcula** também:

- Tenants ativos (`subscriptions.status in active, trialing`, excluindo `default`)
- Planos em atraso (`past_due`)
- MRR estimado (`billing_service.estimate_plan_mrr_cents` × contagem por plano)
- `plan_breakdown`

**Nenhum desses quatro é renderizado na faixa de KPIs.** `plan_breakdown` não é usado em widget algum da overview.

**Tabela “Conversas recentes”**

- Colunas implícitas (sem header): telefone (`phoneNumber`), última mensagem, data (`formattedUpdatedAt`)
- Até 8 itens de `GET /api/v1/conversations`
- Link “Abrir fila” → `_selectNav(conversations)`

**Painel “Atividade recente”** (se `overview.recentEvents` não vazio)

- Texto: `summary` de até 5 eventos
- Origem: `admin_audit_logs` dos tenants ≠ `default`, últimos 10 na API (UI mostra 5)

**Painel “Empresas com maior uso”** (só Super Admin e se `topTenants` não vazio)

- Colunas: nome (`tenant_name` ou `tenant_id`) + `"{usedMessages} msgs"`
- Origem: query SQL global (mensagens incoming no mês, top 6, excluindo `default`)
- Campos `plan`, `status`, `monthly_message_limit` **vêm na API e não são pintados**

**Bloco “Operação da plataforma”** (somente tenant home Super Admin)

- Texto fixo: conta interna; selecionar empresa para WhatsApp/automações
- Botão “Gerenciar empresas” → Clientes

**Não aparece no home Super Admin:** Plano e consumo real, WhatsApp conectado, Integrações, Equipe e empresas (esses blocos de `OperationHubPanel` só existem fora do contexto sistema).

### Ações

| Nome | Comportamento | Endpoint / função | Estado |
| --- | --- | --- | --- |
| Tap KPI Fila / Hoje | Abre Conversas | nav local | implementado |
| Tap KPI Consumo / Plano | Abre Cobrança | nav local | implementado |
| Tap KPI WhatsApp | Abre Clientes (Super Admin) | nav local | implementado |
| Abrir fila | Abre Conversas | nav local | implementado |
| Tap linha da tabela | Abre Conversas (não abre a conversa específica) | nav local | implementado |
| Gerenciar empresas | Abre Clientes | nav local | implementado |
| Pull-to-refresh / Tentar novamente | Recarrega `_load()` | overview + conversations | implementado |

---

## 2. Clientes — tab Empresas

### Identificação

- Nome: header **Clientes**; chip **Empresas**
- Arquivo: `admin-panel/lib/screens/backoffice_screen.dart`
- Estado: `_selectedNav == 'clients'` e `_adminView == 'tenants'`
- Menu: Clientes
- Role: Super Admin (`visible: authService.isSuperadmin`). API `assert_superadmin` em `/api/v1/admin/tenants`.

### Conteúdo

**Chips de view:** Empresas | Leads | WhatsApp.

**Coluna esquerda — “Administração SaaS”**

- Busca local: “Buscar empresa, identificador ou email” (filtra lista já carregada; sem query na API)
- Card “Visão operacional” (contagens **no cliente**, sobre a lista `GET /api/v1/admin/tenants`):
  - `{n} empresa(s)` = `tenants.length`
  - `{n} ativo(s)` = `status == 'active'`
  - `{n} exibido(s)` = lista filtrada
  - “Empresa em foco”: `selected.name`
- Lista (não é tabela de colunas): por card
  - `name`
  - `tenant_id`
  - `email`
  - `owner_email` (se houver)
  - badges: “Sistema” se `tenantId == homeTenantId`; plano (`_planLabel`); status (`_statusLabel`)
  - “Em foco” se selecionado
  - “Atualizado em” `updatedAt` ou `createdAt`

**Coluna direita — tenant sistema**

- Título “Conta interna do sistema”
- Texto explicativo fixo
- Métricas: Conta interna (`tenantId`), Criado em, Tipo = “Administrador do sistema”
- Sem WhatsApp, sem plano, sem usuários, sem automações nesta vista

**Coluna direita — tenant comercial**

1. Hero: badges plano e status da **assinatura** (fallback: plano/status do tenant); percentual de uso
2. “Resumo da empresa”: Responsável, Plano atual, Status, Criado em, Última atualização
3. “Assinatura e cobrança”: selects Plano (`starter`, `growth`, `pro`, `enterprise`), Status (`active`, `trialing`, `inactive`), Limite mensal; barra de uso; renovação; aviso se `subscription.active == false`
4. “Contas de WhatsApp”: ver seção WhatsApp
5. “Usuários da empresa”: nome, e-mail, papel, status, último acesso, criado em
6. “Automações da empresa”: nome, descrição, `startState`
7. “Auditoria recente”: `summary`, `action | entityType | entityKey`, ator, data

### Ações

| Nome | Comportamento | Endpoint / função | Estado |
| --- | --- | --- | --- |
| Nova empresa | Dialog criar tenant | `POST /api/v1/admin/tenants` → `adminTenantService.createTenant` | implementado |
| Selecionar card | `setActiveTenantId` + carrega detalhes | `GET /api/v1/subscriptions/{id}`; `GET .../whatsapp-accounts`; `GET .../users`; `GET /api/v1/flows`; `GET /api/v1/admin/audit-logs` | implementado |
| Reduzir / Aumentar plano | Só muda o select local (`_planOptions`) | nenhum até Salvar | implementado (UI) |
| Salvar plano | Grava plano, status, limite | `PATCH /api/v1/subscriptions/{tenant_id}` | implementado |
| Nova conta / Editar / Definir principal | ver WhatsApp | ver WhatsApp | implementado |
| Convidar usuário | Dialog + token | `POST /api/v1/tenants/{id}/users/invite` | implementado |
| Gerenciar (usuário) | Dialog nome/papel/status | `PATCH /api/v1/tenants/{id}/users/{user_id}` | implementado |
| Redefinir senha | Dialog com token/link | endpoint de reset do `tenant_user_service` (rota users) | implementado |
| Abrir editor | `_selectNav(automations)` se embedded | `GET /api/v1/flows` já usado na lista | implementado |
| Cancelar (dialogs) | Fecha | — | implementado |

Não existe na UI: editar nome/e-mail do tenant, apagar tenant, listar propostas da empresa.

Planos do dialog Nova empresa: mesmos `_planOptions` (`starter`, `growth`, `pro`, `enterprise`) com labels Inicial / Crescimento / Profissional / Empresarial.

---

## 3. Clientes — tab Leads

### Identificação

- Nome: chip **Leads**
- Arquivo: `backoffice_screen.dart` (`_buildLeadsView`, `_LeadCard`) + `backoffice_lead_proposal_flow.dart`
- Estado: `_adminView == 'leads'`
- Menu: Clientes → Leads
- Role: Super Admin; APIs `assert_superadmin`

### Conteúdo

**Pipeline comercial** (`GET /api/v1/admin/leads/summary`)

- Número grande: `total`
- Chips: contagens `new`, `contacted`, `qualified`, `won`, `lost` (labels Novo / Em contato / Qualificado / Fechado / Perdido)

**Filtros**

- Busca: “Buscar por empresa, nome, e-mail ou WhatsApp” → query `search` na listagem
- Botão Filtrar / chips Todos + status → `GET /api/v1/admin/leads?status=&search=&limit=200`
- Atualizar (no switcher, só na view leads)

**Card do lead (não é tabela)**

Exibido: `company`, `segment`, `monthlyVolume`, data, badge status, `name`, `email`, `whatsapp`, `objective`, `currentTools`, `bestContactTime`.

**Não pintados** embora existam no modelo/API: `teamSize`, `notes`, `assignedTo`, `source`, `metadata`.

Empty state: “Ainda não há leads”.

### Ações

| Nome | Comportamento | Endpoint / função | Estado |
| --- | --- | --- | --- |
| Filtrar / chips de status | Recarrega lista | `GET /api/v1/admin/leads` | implementado |
| Atualizar | `_loadLeads` | GET leads + GET summary | implementado |
| Gerar proposta | Dialog | `GET /api/v1/admin/leads/{id}/recommendation`; `POST /api/v1/admin/proposals` (status `sent`); PDF local `printing` + `buildProposalPdf` (sem API) | implementado |
| Cadastrar empresa | Dialog conversão | `GET /api/v1/admin/proposals?lead_id=` (pré-preenche); `POST /api/v1/admin/leads/{id}/convert` | implementado |
| Atualizar status | chips new/contacted/qualified/won/lost | `PATCH /api/v1/admin/leads/{id}` só `status` | implementado |

Campos do dialog proposta: plano (`starter`, `growth_basic`, `growth`, `pro`, `enterprise`), mensalidade, implantação, limite, validade (dias), itens, observações. Botões: gerar PDF (local), salvar como enviada.

Campos do dialog cadastrar empresa: Tenant ID (slug), e-mail da empresa, nome admin, e-mail admin, plano, limite. Botão criar + convite. **Não envia `owner_password`** no convert (API aceita opcional).

Não há tela “Propostas”. `GET /api/v1/admin/proposals` só é usado para pré-preencher a conversão.

---

## 4. Clientes — tab WhatsApp (Super Admin)

### Identificação

- Nome: chip **WhatsApp**
- Arquivo: `backoffice_screen.dart` (`_buildWhatsAppView`) + `whatsapp_meta_panels.dart` + `coexistence_wizard.dart`
- Estado: `_adminView == 'whatsapp'` (embedded em Clientes; **não** o item de sidebar WhatsApp, que está oculto)
- Role: Super Admin nesta tab; as APIs de contas usam `resolve_tenant_scope` (Super Admin pode o tenant no path/header)

### Dados que o Super Admin vê/edita hoje

Modelo `WhatsAppAccount` / `WhatsAppAccountModel`:

- `account_id`, `tenant_id`, `account_key`, `display_name`
- `phone_number_id` (rótulo UI: “ID do número no WhatsApp”)
- `display_phone_number` (rótulo: “Número exibido”)
- `status`: na UI do dialog, apenas `active` | `inactive` (labels Ativo / Inativo). Lista também trata `pending` em outros widgets tenant (`whatsappStatusLabel` → Pendente), mas o select do backoffice não inclui `pending`.
- `is_default` / “Principal”
- `has_access_token`, `masked_access_token` (não o token completo)
- `verify_token` no formulário criar/editar

**Não existem** no modelo nem na UI desta tab:

- instância Evolution/Baileys
- health / online / offline
- WABA ID (o ID de WABA que aparece em Templates é outra tela, via templates Meta)
- webhook health

Dropdown “Empresa selecionada”: tenants **exceto** `homeTenantId`. Texto: `{name}  ({tenantId})`.

Card de conta: nome, número, phone_number_id, badges status e Principal, identificador, token mascarado.

Empty: “Cadastre uma empresa…” ou lista vazia + “Vincular manualmente”.

### Ações

| Nome | Comportamento | Endpoint / função | Estado |
| --- | --- | --- | --- |
| Dropdown empresa | `_selectTenant` | mesmos GETs de detalhe | implementado |
| Assistente coexistência | `showCoexistenceWizard` | onboarding Meta local/API coexistência; **não** clica FB.login sozinho na captura | implementado (wizard) |
| Conectar via Meta (Coexistência) | `WhatsAppMetaConnectButton` | fluxo Embedded Signup (`whatsapp_onboarding`) | implementado; depende de HTTPS/Meta |
| Vincular WhatsApp / Vincular manualmente / Nova conta | dialog criar | `POST /api/v1/tenants/{tenant_id}/whatsapp-accounts` | implementado; **desabilitado** se nenhum tenant ou tenant sistema |
| Editar | dialog patch | `PATCH /api/v1/tenants/{id}/whatsapp-accounts/{account_key}` | implementado |
| Definir principal | `is_default: true` | mesmo PATCH | implementado; desabilitado se já principal |
| Salvar conta | submit dialog | POST ou PATCH | implementado |

Campos do dialog: Identificador da conta (só na criação), Nome amigável, ID do número, Número exibido, Token de verificação, Access token (opcional na edição), Status, switch conta principal.

---

## 5. Cobrança

### Identificação

- Nome: **Cobrança**
- Arquivo: `admin-panel/lib/screens/billing_hub_screen.dart`
- Estado: `_selectedNav == 'billing'`
- Menu: Cobrança
- Role: Super Admin na sidebar. API `GET/POST /api/v1/billing/*` também `assert_superadmin`.

### Dois estados de UI

**A) Contexto = tenant home (system-admin)**  
Não chama billing. Card: “Selecione um cliente para ver a cobrança”. Botão “Abrir administração SaaS” → Clientes.

**B) Contexto = tenant comercial** (depois de focar uma empresa em Clientes)

`GET /api/v1/billing/summary` (escopo `x-tenant-id`).

Campos / blocos:

- Hero: “Cobrança e assinatura”; badge `Status: {label}`; texto se `provider_ready` ou não
- Pill “Cliente no provedor: {provider_customer_id}” se existir
- Métricas: Plano atual, Renovação (+ `{graceDays} dias de tolerância` de `BILLING_GRACE_DAYS`, default 3), Mensagens usadas, Mensagens restantes
- Catálogo de planos: `available_plans` da API ou fallback `starter, growth, pro, enterprise`
  - Labels: Inicial, Crescimento, Profissional, Empresarial
  - Descrições **fixas no Flutter** (`_planDescription`) — não vêm da API
  - Badge “Atual” no plano corrente
- Uso do período: barra `used/limit`
- Faturas: `provider_invoice_id`, status, valores, links se houver; empty: “Ainda não existem faturas sincronizadas…”

### Stripe (o que existe no backend)

- Provider: `BILLING_PROVIDER == stripe` **e** `STRIPE_SECRET_KEY` não vazio → `provider_ready`
- Checkout: `POST /api/v1/billing/checkout-session` `{plan}` → Stripe Checkout (`mode=subscription`)
- Portal: `POST /api/v1/billing/portal-session`
- Webhook: `billing_webhooks.py` sincroniza assinatura/faturas
- Price IDs: `STRIPE_PRICE_STARTER|GROWTH|PRO|ENTERPRISE`
- MRR interno (só overview API, não na tela Cobrança): `_PLAN_PRICES_CENTS` starter 9900, growth 24900, pro 59900, enterprise 149900 (centavos). **A UI de Cobrança não mostra esses valores.**

### Ações

| Nome | Comportamento | Endpoint | Estado |
| --- | --- | --- | --- |
| Abrir administração SaaS | Nav Clientes | — | implementado (só estado A) |
| Portal de cobrança | Abre URL Stripe | `POST /api/v1/billing/portal-session` | implementado; **desabilitado** se não há `provider_customer_id` ou enquanto abre |
| Contratar plano / Trocar plano | `launchUrl` checkout | `POST /api/v1/billing/checkout-session` | implementado; **desabilitado** se `!providerReady` |
| Pull-to-refresh | Recarrega summary | GET summary | implementado |

Não há preços listados na UI. Não há plano `growth_basic` nesta tela.

---

## 6. Conversas / Automações / Ações / Templates (acessíveis ao Super Admin)

Não são exclusivas do Super Admin. Operam no **tenant do header**.

| Tela | Arquivo | APIs principais | Comportamento no tenant home |
| --- | --- | --- | --- |
| Conversas | `dashboard_screen.dart`, `conversation_list.dart`, `conversation_detail_screen.dart` | `GET /api/v1/conversations`, messages, flow, `POST .../reply` | Lista sessões do tenant `default` (pode ser vazia ou residual) |
| Automações | `settings_screen.dart` | `GET/PUT /api/v1/flows`, simulation, settings IA | `_isSystemAdminHomeContext`: lista vazia, criar fluxo desabilitado, toggle IA desabilitado |
| Ações | `actions_screen.dart` | `/api/v1/.../actions` (tenant) | CRUD no tenant ativo |
| Templates | `template_dispatch_screen.dart` | templates Meta do tenant | WABA/phone da conta WhatsApp do tenant ativo |

Menu Equipe e menu WhatsApp **não existem** para Super Admin; gestão equivalente está em Clientes.

`settings_hub_screen.dart` existe no repositório e **não é montado** em `DashboardScreen`.

---

## 7. Navegação completa Super Admin

| Menu | Tela | Existe hoje? | Dados reais | Ações reais | Arquivo Flutter | API |
| --- | --- | --- | --- | --- | --- | --- |
| Marca Atenda Ai | Visão geral | sim | Parcial: conversas + audit + top tenants; KPIs da faixa misturam API global, conversas e **subscription hardcoded** no home | Nav + refresh | `overview_screen.dart` | `GET /api/v1/dashboard/overview`, `GET /api/v1/conversations` |
| Conversas | Inbox | sim | Sessões do `x-tenant-id` | Abrir, filtrar, responder | `dashboard_screen.dart` | `/api/v1/conversations*` |
| Automações | Builder de fluxos | sim | Fluxos do tenant; vazio no home | CRUD/simulação se tenant comercial | `settings_screen.dart` | `/api/v1/flows*`, tenant settings |
| Ações | Ações reutilizáveis | sim | Do tenant ativo | CRUD | `actions_screen.dart` | actions do tenant |
| Templates | Templates WhatsApp | sim | Do tenant ativo | Criar/listar/disparar teste | `template_dispatch_screen.dart` | templates Meta |
| WhatsApp (sidebar) | — | **não** (oculto) | — | — | — | — |
| Equipe (sidebar) | — | **não** (oculto) | — | — | — | — |
| Clientes → Empresas | Lista + detalhe tenant | sim | `GET /admin/tenants` + subscription + users + WA + flows + audit | Criar empresa, salvar plano, WA, users | `backoffice_screen.dart` | `/api/v1/admin/tenants`, subscriptions, users, whatsapp-accounts, flows, audit-logs |
| Clientes → Leads | Pipeline | sim | summary + list | status, proposta, converter | `backoffice_screen.dart`, `backoffice_lead_proposal_flow.dart` | `/api/v1/admin/leads*`, proposals, convert |
| Clientes → WhatsApp | Contas por empresa | sim | contas do tenant escolhido | CRUD conta, Meta connect, wizard | `backoffice_screen.dart` | whatsapp-accounts, onboarding |
| Cobrança | Hub Stripe | sim | summary se tenant ≠ home | checkout, portal | `billing_hub_screen.dart` | `/api/v1/billing/*` |
| Propostas (menu) | Listagem | **não** | API existe | Só dialog no lead | — | `GET /api/v1/admin/proposals` |
| Configurações (hub) | SettingsHub | **não no nav** | arquivo órfão | — | `settings_hub_screen.dart` | — |
| Integrações | Bloco overview | só fora do home; **Coming soon** | nenhum endpoint | nenhum | `operation_hub_panel.dart` | nenhum |

---

## 8. Divergências (somente registro)

1. **Menu “Clientes” vs entidade tenant.** A UI diz Cliente/Empresa; a API e o banco dizem `tenant`. Não há recurso REST `/clients`.
2. **KPIs globais da API não estão na faixa da home.** `Tenants ativos`, `Planos em atraso`, `MRR estimado` e `plan_breakdown` são calculados em `dashboard_service._build_global_overview` e ignorados pela faixa Flutter. “Hoje” reutiliza o KPI “Mensagens do mes”.
3. **Home Super Admin ignora subscription e WhatsApp reais.** Hardcode `enterprise` / `active` / zero mensagens / zero contas, enquanto a API global tem outros números.
4. **Não há tela de Propostas** apesar de CRUD na API. `growth_basic` existe no dialog de proposta e **não** no catálogo Stripe / `_planOptions` de assinatura (`starter, growth, pro, enterprise`).
5. **Preços:** `_PLAN_PRICES_CENTS` e fallbacks do dialog de proposta (ex.: 197/397/…) **não** são exibidos na Cobrança. A UI de proposta usa fallbacks locais se a recomendação falhar.
6. **PATCH lead** aceita `notes` e `assigned_to`; a UI só envia `status`.
7. **Billing só Super Admin** na API e no menu. Tenant comum não tem item Cobrança.
8. **Sidebar WhatsApp oculto** para Super Admin; a gestão está na tab dentro de Clientes.
9. **`SettingsHubScreen` não está ligado** ao `DashboardScreen`.
10. **Integrações:** `PremiumComingSoonStrip` explícito; sem endpoint.
11. **Tap em conversa recente na home** não seleciona aquele ID; só muda o nav para Conversas.
12. **Status WhatsApp `pending`** existe em labels tenant; o dialog Super Admin só `active`/`inactive`.
13. **WABA:** não é campo da conta WhatsApp do backoffice; IDs de WABA/phone em Templates vêm do fluxo de templates Meta, outra tela.
14. Documentação em `docs/` (Meta, webhook, cadastro WhatsApp) descreve onboarding operacional; **não documenta** este mapa de telas Super Admin. Este arquivo passa a ser essa fonte.

---

## 9. Contratos de API usados pelo Super Admin (índice)

- `POST /api/v1/auth/login`, `GET /api/v1/auth/me`
- `GET /api/v1/dashboard/overview` (global se `x-tenant-id` = `DEFAULT_TENANT_ID`)
- `GET /api/v1/conversations` (+ messages, flow, reply)
- `GET/POST /api/v1/admin/tenants`
- `GET/PATCH /api/v1/subscriptions/{tenant_id}`
- `GET/POST/PATCH /api/v1/tenants/{tenant_id}/whatsapp-accounts`
- `GET/POST invite/PATCH/reset /api/v1/tenants/{tenant_id}/users`
- `GET /api/v1/flows`
- `GET /api/v1/admin/audit-logs`
- `GET /api/v1/admin/leads`, `GET .../summary`, `PATCH .../{id}`
- `GET /api/v1/admin/leads/{id}/recommendation`
- `POST /api/v1/admin/leads/{id}/convert`
- `GET/POST/PATCH /api/v1/admin/proposals`
- `GET /api/v1/billing/summary`, `POST .../checkout-session`, `POST .../portal-session`
- `POST /api/v1/public/leads` (landing, não é tela Super Admin)

Header obrigatório de escopo: `x-tenant-id`.
