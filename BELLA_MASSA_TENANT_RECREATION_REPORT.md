# Atende Ai — Recriação do tenant Bella Massa (produção AWS)

Data: 2026-10-22 (UTC 00:43–00:50)
Resultado: **Bella Massa recriada no MySQL de produção e pronta para o onboarding WhatsApp pelo painel.**
Nenhuma senha, token ou hash aparece neste relatório.

| Item | Estado |
| --- | --- |
| Tenant | `pizzaria_bella_massa` (ID interno 5), "Bella Massa", ativo |
| Usuário | `admin@bellamassa.com.br`, role `owner` (Admin da empresa), ID 3 |
| Login | Funcionando (API interna e URL pública `painel.meuatendeai.com.br`) |
| Painel | Acessível; Embedded Signup com coexistência disponível |
| WhatsApp | Aguardando conexão pelo proprietário (0 contas) |
| Respostas automáticas | **Desligadas** (`auto_reply_mode=off`) |
| Provider local | Não ativado (`gemini`, `local_ai_enabled=0`; AI Engine `LOCAL_AI_ENABLED=false`) |
| Outros tenants | Inalterados (verificado por impressão digital antes/depois) |

## 1. Banco MySQL utilizado

MySQL 8.4.11, banco `atenda`, container `mysql` do projeto Compose `atende-prod` em `/opt/atende-ai` (EC2 3.218.194.130). Saúde verificada (`mysqld is alive`, container healthy). Nenhum banco novo foi criado.

## 2. Versão do schema

`schema_migrations` antes: 001, 003, 005, 006, 007, 008, 009, 011 (002/004 — dados demo — nunca aplicadas em produção; 010 é aplicada pelo bootstrap do backend).
Aplicada nesta etapa: **`012_tenant_auto_reply_mode.sql`** (aditiva, idempotente; registrada em `schema_migrations` às 00:44:32). Adiciona a `tenant_settings`:
- `auto_reply_mode VARCHAR(16) NOT NULL DEFAULT 'on'`
- `auto_reply_allowlist JSON NULL`

Os quatro tenants existentes ficaram com `on` (comportamento idêntico ao anterior).

## 3. Tenant criado ou recuperado

**Criado.** Antes da operação não havia nenhum vestígio da Bella Massa em produção: zero registros em `tenants` (por `external_key`, nome ou e-mail), zero usuários `@bellamassa.com.br` e zero entradas de auditoria. A recriação usou o procedimento oficial do backend, `TenantAdminService.ensure_bootstrap_tenant(..., copy_default_flows=False)`, que é o mesmo caminho do bootstrap de demo do `main.py`. O `BOOTSTRAP_DEMO_DATA` continua `false` em produção, porque ativá-lo também criaria `loja_centro_demo`. A execução foi feita pelo script versionado `backend-api/scripts/provision_bella_massa.py`, dentro do container `backend-api`. Antes de gravar, o script valida três pontos:
- a credencial do container é a documentada;
- o e-mail do owner não pertence a outro tenant (o serviço oficial moveria o usuário, por isso essa checagem bloqueia);
- o e-mail da empresa não está em uso.

Tenant e owner são gravados numa única transação pelo serviço oficial. Configurações e assinatura vêm em seguida, de forma idempotente.

## 4. ID interno do tenant

`tenants.id = 5`.

## 5. external_key

`pizzaria_bella_massa`. A unicidade é garantida pela constraint `uq_tenants_external_key`, e há 1 único registro.

## 6. Usuário vinculado

`users.id = 3`, `admin@bellamassa.com.br`, display name "Admin Bella Massa", status `active`, vinculado somente ao tenant 5. É o único usuário do tenant.

## 7. Papel do usuário

`owner` (rótulo no painel: "Admin da empresa"). Não é Superadmin. Capacidades validadas:
- **Pode:** gerenciar WhatsApp, automações, conversas, equipe e templates do próprio tenant.
- **Não pode:** acessar o backoffice (`canAccessBackoffice=false`).

## 8. Credenciais reaproveitadas?

**Sim, integralmente.** O e-mail do owner, o e-mail da empresa e o identificador do tenant são os do `CREDENCIAIS_TESTE.md`. A senha documentada é idêntica ao default `BOOTSTRAP_PIZZARIA_ADMIN_PASSWORD` do backend. Isso foi verificado por comparação de hash, sem exibir o valor, tanto no repositório quanto dentro do container de produção. Ela foi gravada com o hashing do próprio backend (`pbkdf2_`).

Diferenças em relação ao documento:
- **Nome da empresa:** o documento diz "Pizzaria Bella Massa"; usei "Bella Massa", conforme o pedido desta etapa.
- **Plano:** o documento diz `professional`, que não existe no catálogo atual (nem no legado `starter/growth/pro/enterprise/on_demand`, nem no 2026-10 `inicial/essencial/crescimento/profissional/empresarial`). Por isso não foi reutilizado; veja a seção 10.

**Proteção necessária (achado de segurança, valores não divulgados):**
- `CREDENCIAIS_TESTE.md` está **versionado no Git** (commits `be3ffc4` e `f9da5d0`) e contém senhas em texto puro: do Superadmin, do owner da Loja Centro e do owner da Bella Massa.
- `backend-api/app/config/settings.py` também contém senhas default em texto puro.

Recomendações:
- remover as senhas do arquivo (manter só usuários e papéis), mover as credenciais para um cofre;
- trocar a senha do Superadmin se ela coincidir com a documentada;
- avaliar a limpeza do histórico do Git.

A senha da Bella Massa já está exposta no histórico e deve ser tratada como **senha fraca de homologação**: troque-a antes de qualquer uso real. Durante esta execução, a senha da Bella Massa apareceu uma vez na saída interna de uma ferramenta de leitura. Não foi gravada em nenhum arquivo, log ou commit.

## 9. Login validado?

**Sim.** Validação feita sem expor a senha (executada dentro do container):

| Teste | Resultado |
| --- | --- |
| Login com a credencial documentada, API interna | 200, `tenant_id=pizzaria_bella_massa`, `role=owner` |
| Login pela URL pública (DNS, TLS, Nginx, backend) | 200 |
| Senha errada | 401 |
| `GET /api/v1/auth/me` | tenant `pizzaria_bella_massa`, role `owner` |
| Configurações do próprio tenant | 200 |
| `GET /api/v1/dashboard/overview` | 200 |
| Contas WhatsApp do próprio tenant | 200, lista vazia |
| `GET /api/v1/meta/embedded-signup/config` | 200; `app_id` e `config_id` presentes; `coexistence_feature_type` disponível |
| `GET /api/v1/meta/embedded-signup/preflight` | 200 |
| Painel `https://painel.meuatendeai.com.br/` e `main.dart.js` | 200 |

O fluxo Embedded Signup **não** foi iniciado nem concluído.

## 10. Plano / status de homologação

A plataforma **não possui um modo "homologação" dedicado**. A representação adotada foi a mínima, usando apenas recursos existentes:

- **Assinatura legada:** `subscriptions.plan=starter` (default do sistema), `status=trialing` (período de avaliação), `monthly_message_limit=1000`, `renewal_date=2026-11-21`.
- **Billing V2:** **nenhum** `tenant_billing_config`, nenhum bucket, nenhum ledger, nenhuma reserva. Isso significa:
  - não há plano comercial;
  - não há franquia concedida;
  - não há Stripe;
  - não há transação fictícia.

Limitação documentada: sem `plan_code`, o Billing V2 trata mensagens operacionais como `LEGACY_UNMETERED`, ou seja, permitidas e sem medição. Por isso o bloqueio de automação **não** depende de billing. Ele é feito pelo novo controle `auto_reply_mode` (seção 13). Quando a homologação avançar, um Superadmin deve atribuir um plano do catálogo 2026-10 pelo fluxo normal (`configure_plan`).

## 11. Billing preservado

**Sim.** Comparação de impressão digital antes e depois:

| Tabela | Antes = depois |
| --- | --- |
| `tenant_billing_config` | sim |
| `billing_ledger` | sim (28) |
| `billing_entitlement_buckets` | sim (4) |
| `billing_reservations` | sim (12) |
| `usage_events` | sim (7) |
| `billing_catalog_items` | sim (13) |

Além disso:
- `META_BILLING_DEFAULT` continua `customer_direct`;
- o catálogo e os planos não foram alterados;
- o Stripe não foi tocado;
- a Bella Massa tem 0 reservas e 0 buckets.

## 12. Fluxo Bella Massa

`flow-engine/app/flows/tenants/pizzaria_bella_massa/atendimento_pizzaria_delivery.yaml` existe na versão atual. A cópia na imagem de produção do Flow Engine é idêntica à do repositório (sha256 igual, ignorando CRLF).

**Associação:** o Flow Engine associa fluxos pelo nome da pasta (= `tenant_id`), então não há registro no MySQL a criar. Validado em produção: `GET /flow/admin/flows?tenant_id=pizzaria_bella_massa` retorna `atendimento_pizzaria_delivery` (etapa inicial `boas_vindas`), e `teste_empresa` não o enxerga. Os fluxos default **não** foram copiados para a Bella Massa (`copy_default_flows=False`), e nenhum fluxo de outra empresa foi tocado.

**Ações:** os `hook: action: confirmar_pedido / consultar_status_pedido / verificar_status_pedido` são devolvidos apenas como metadados e nenhum serviço os executa. Também não existe nenhuma `flow_actions` cadastrada, então não há como gerar pedidos ou cobranças reais.

## 13. WhatsApp Accounts antes e depois

- Antes: 0 contas em `whatsapp_accounts` (todos os tenants).
- Depois: 0 contas.
- Bella Massa: `whatsapp_phone_number = NULL`, sem `whatsapp_token`.

O WABA 1299741078262298 e o Phone Number ID 1155710810954749 **não** foram inseridos. Nenhum token foi cadastrado e `META_PHONE_NUMBER_ID`/`META_ACCESS_TOKEN` globais continuam **ausentes** no Gateway e no backend. Sem conta conectada, o Gateway não tem como enviar nada para esse número.

## 14. Coexistência pendente

Pendente, a ser feita pelo proprietário. O tenant está pronto para o fluxo oficial: o assistente de coexistência do painel usa `embedded-signup/config` e `preflight`, ambos respondendo 200 para o usuário da Bella Massa. Se a Meta indicar que o número já está vinculado, **nenhuma** ação automática de desconexão ou registro será feita: o resultado deve ser trazido para análise antes de qualquer operação que mexa na coexistência.

**Proteção implementada para o teste (menor solução segura):** não existia nenhum mecanismo por tenant para impedir respostas automáticas. A allowlist da IA-03 existe apenas localmente (não implantada) e só controla o provider local, não fluxos nem Gemini. Foi implementado e implantado `tenant_settings.auto_reply_mode`:

| Modo | Comportamento |
| --- | --- |
| `on` | Comportamento anterior; default de todos os tenants. |
| `off` | A mensagem recebida é gravada, a conversa vai para atendimento humano (`human_handoff_pending`) e **nada é enviado**: sem fluxo, sem IA, sem reserva de billing. |
| `allowlist` | Responde automaticamente só aos números listados (máximo 20, E.164). Prepara o teste com o celular final 5547. |

Regras de acesso:
- Somente Superadmin altera o modo, e a alteração é auditada (`tenant.auto_reply.update`).
- O owner vê o modo, mas não o altera (PATCH → 403, validado em produção).
- A API nunca devolve os números da allowlist, apenas a contagem.
- Modo desconhecido falha fechado (`off`).

O bloqueio foi validado em produção com uma mensagem interna ao endpoint do backend, sem passar pelo Gateway:

| Verificação | Resultado |
| --- | --- |
| Envio | `source=auto_reply_disabled`, texto vazio, `requires_handoff=true` |
| Reenvio | Detectado como duplicado |
| Mensagens enviadas pela Bella | 0 |
| Reservas de billing | 0 |

Essa mensagem de teste (remetente fictício `5500000000000`, texto "[TESTE INTERNO] … pode ignorar") aparece como uma conversa não lida no painel da Bella Massa.

Observação: mesmo em `off`, o Gateway marca a mensagem recebida como lida (confirmação azul no WhatsApp do cliente). É comportamento existente, anterior ao backend.

## 15. Provider local desativado

- Bella Massa: `ai_provider=gemini`, `local_ai_enabled=0`.
- AI Engine: `AI_PROVIDER=gemini`, `LOCAL_AI_ENABLED=false`.

O owner não consegue ativar o provider local (PATCH → 403); somente o Superadmin, com auditoria (`tenant.ai_provider.update`). Com `auto_reply_mode=off`, nem Gemini nem Qwen3 são chamados em conversas reais da Bella Massa. WireGuard, Qwen3, Qdrant e o servidor local não foram tocados.

## 16. Outros tenants preservados

Impressão digital (MD5 por tabela, sem conteúdo) antes e depois. Tudo idêntico em:
- `tenants` (4);
- `subscriptions`;
- `tenant_settings` (colunas originais);
- tabelas de billing;
- `whatsapp_accounts`;
- `messages` e `sessions` dos outros tenants.

Única diferença: `users.id=1` (Superadmin) teve o `password_hash` re-salgado às 00:45:29. A causa é o comportamento existente `AuthService.ensure_default_user()`, que regrava o hash a partir de `DEFAULT_ADMIN_PASSWORD` a cada inicialização do backend (o `updated_at` anterior, 12/10, coincide com o restart da IA-02). Foi verificado que o hash anterior valida com a mesma senha atual: **a credencial do Superadmin não mudou**. O usuário de `teste_empresa` está byte a byte idêntico.

Achado (P2): esse re-hash a cada restart também desfaria uma troca de senha do Superadmin feita pelo painel.

## 17. Testes realizados

**Unitários** (container descartável da imagem do backend, sem rede): **86 passed**, incluindo os 16 novos em `tests/test_auto_reply_mode.py`. Eles cobrem:
- modos e allowlist com formatos variados;
- falha fechada;
- RBAC do PATCH;
- ocultação dos números;
- inbound bloqueado sem billing e sem envio;
- duplicado;
- remetente autorizado seguindo o fluxo normal;
- simulação (dry-run) não bloqueada.

**Integração em MySQL isolado** (MySQL 8.4 descartável, já removido; schema construído com as mesmas migrations de produção mais o bootstrap): **117 passed** (inclui as 31 de Billing V2 com MySQL real). O ensaio completo do provisionamento passou 28 de 28 verificações:
- criação;
- idempotência (2ª execução sem ações, sem duplicidade, sem redefinir senha);
- senha com hash do backend;
- assinatura `trialing`;
- `auto_reply off`;
- provider desligado;
- sem billing e sem WhatsApp;
- validação de modo/allowlist inválidos;
- persistência da allowlist;
- outros tenants inalterados;
- login certo/errado;
- RBAC (próprio tenant sim, outro tenant 403, sem backoffice, Superadmin acessa).

**Produção:**
- `check` sem problemas;
- `apply`, seguido de reexecução idempotente (`actions=[]`);
- login interno e público;
- isolamento: `teste_empresa`/`default` → 403, inclusive via cabeçalho `x-tenant-id`;
- backoffice 403;
- Embedded Signup config/preflight 200;
- bloqueio de auto-resposta;
- Flow Engine;
- impressão digital;
- 0 erros no log do backend;
- todos os serviços healthy.

Não houve testes destrutivos em produção.

Flutter: o painel não foi alterado, então analyze/build não foram necessários. O modo de resposta automática ainda não tem controle visual: hoje é alterado pela API, como Superadmin.

## 18. Backup

`/var/backups/atende-ai-ia02/pre-bella-massa-20261022T004355Z/` (diretório 700, arquivos 600, fora da rotina que apaga backups com mais de 7 dias):

| Arquivo | Conteúdo |
| --- | --- |
| `mysql.sql.gz` | `mysqldump --single-transaction` do banco `atenda`; `gzip -t` ok, 38 tabelas, trailer "Dump completed" |
| `backend-api-code.tgz` | código do backend anterior ao deploy |
| `database-migrations.tgz` | migrations |
| `SHA256SUMS` | verificado com `sha256sum -c` |

Imagem anterior preservada: `atende-prod-backend-api:pre-bella-20261022` (ID `9249870356cf`).
IDs envolvidos: tenant 5, usuário 3, `admin_audit_logs` 16.

## 19. Rollback

Do menor para o maior impacto. Nenhum passo foi executado.

1. **Pausar a Bella Massa sem apagar nada:** `UPDATE users SET status='inactive' WHERE id=3;` e `UPDATE tenants SET status='inactive' WHERE id=5;`.
2. **Voltar o código do backend:**
   ```bash
   docker tag atende-prod-backend-api:pre-bella-20261022 atende-prod-backend-api:latest
   ```
   depois `docker compose -p atende-prod --env-file .env.production -f docker-compose.production.yml up -d --no-deps backend-api`, e restaurar `backend-api/` a partir de `backend-api-code.tgz`. As colunas novas podem permanecer (aditivas, ignoradas pelo código antigo).
3. **Remover a Bella Massa:** `DELETE FROM tenants WHERE id=5` (cascata para usuário, assinatura, settings, sessões e mensagens do tenant). É destrutivo: somente com autorização explícita.
4. **Restaurar o dump completo:** só em desastre e com autorização, porque descartaria tudo que for gravado depois de 00:43 UTC.

## 20. Próxima etapa

**Para o proprietário:**
1. Entrar em `https://painel.meuatendeai.com.br` com o usuário Bella Massa e conectar o WhatsApp Business 3594 pelo fluxo oficial de coexistência (Embedded Signup).
2. Se a Meta indicar que o número já está vinculado, parar e trazer a mensagem exibida.

Depois da conexão (não executado):
1. Confirmar que `whatsapp_accounts` tem uma conta, do tenant 5, e que nada foi enviado. As mensagens ao 3594 devem aparecer no painel como "aguardando humano".
2. Para testar respostas, um Superadmin define `auto_reply_mode=allowlist` com o número completo do celular final 5547: `PATCH /api/v1/tenants/pizzaria_bella_massa/settings`, auditado.
3. Só depois avaliar provider Gemini ou local para a Bella Massa.
4. Atribuir um plano Billing V2 de homologação pelo fluxo normal.
5. Tratar os achados:
   - **P1:** `preflight` devolve o `META_VERIFY_TOKEN` a qualquer usuário autenticado. Não alterei porque o assistente de coexistência usa esse endpoint; corrigir após o onboarding.
   - **P1:** senhas em texto puro em `CREDENCIAIS_TESTE.md` e em `settings.py`.
   - **P2:** re-hash da senha do Superadmin a cada restart.
   - **P2:** a allowlist da IA-03 continua não implantada.

## Arquivos alterados (não commitados)

- `backend-api/app/domain/tenant.py`, `app/services/tenant_settings_service.py`, `app/services/conversation_service.py`, `app/api/routes/tenant_settings.py`, `app/db/mysql.py`: controle `auto_reply_mode`.
- `database/migrations/012_tenant_auto_reply_mode.sql`.
- `backend-api/tests/test_auto_reply_mode.py`.
- `backend-api/scripts/provision_bella_massa.py` (provisionamento) e `backend-api/scripts/rehearse_bella_massa.py` (ensaio, nunca em produção).
- Este relatório.

Nenhum desses arquivos contém senhas.
