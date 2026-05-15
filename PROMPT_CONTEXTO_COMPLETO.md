# Prompt de Continuidade do Projeto Chatbot SaaS

Use este prompt em uma nova conversa para retomar exatamente o contexto atual do projeto.

## Prompt

Você está atuando como engenheiro(a) full-stack responsável por manter e evoluir um SaaS de chatbot para WhatsApp com arquitetura em microsserviços.

### Objetivo geral
- Garantir estabilidade operacional do sistema.
- Corrigir problemas no painel administrativo (Flutter Web).
- Manter o fluxo conversacional YAML funcional por tenant.
- Preservar isolamento multi-tenant e regras de billing/assinatura.

### Contexto técnico do projeto
- Arquitetura: serviços separados com Docker Compose.
- Principais módulos:
  - `admin-panel` (Flutter Web): painel SaaS, fluxo, billing, backoffice.
  - `backend-api` (FastAPI): autenticação, tenants, sessões, billing, APIs centrais.
  - `flow-engine` (FastAPI): interpretação de fluxos YAML por tenant.
  - `ai-engine` (FastAPI): intenção e fallback generativo.
  - `whatsapp-gateway` (Python): integração WhatsApp Cloud API.
  - `database` (SQL): schema, migrations, seed.
  - `infra`: orquestração local via `docker compose`.

### Fluxo funcional da conversa
1. `backend-api` recebe a mensagem.
2. `ai-engine` pode detectar intenção.
3. `flow-engine` tenta resolver via fluxo YAML do tenant.
4. Se não resolver, `ai-engine` responde em fallback.
5. Resultado persiste em sessão/mensagens/logs.

### Multi-tenant e regras de acesso
- Isolamento por `tenant_id` para usuários, sessões, mensagens, fluxos, configurações e contas WhatsApp.
- Perfis: `owner`, `manager`, `agent`, `superadmin`, `system-admin`.
- `system-admin` opera tenants de clientes no backoffice, sem fluxo próprio de atendimento.

### Estado atual validado (última sessão)
- `admin-panel` voltou a compilar e gerar build web com sucesso.
- Correção aplicada em `admin-panel/lib/screens/settings_screen.dart` na view de teste de fluxo (`_FlowTestView`).
- Erro crítico corrigido: tipagem inválida de mapa no histórico da simulação de chat.
- Resultado da validação:
  - `flutter analyze`: sem erros bloqueantes (apenas infos/warnings não críticos).
  - `flutter build web --release`: sucesso.

### Problemas que foram tratados no simulador de fluxo
- Não exibir botões de opções como botões clicáveis no chat de teste.
- Não mostrar mensagem de boas-vindas automaticamente ao abrir “Testar”; deve esperar primeira interação do usuário.
- Não “sumir” mensagens enviadas por falta de rebuild do diálogo (estado movido para widget stateful dedicado).
- Tratar transição wildcard `*` como fallback de rota quando aplicável.

### Fluxo YAML principal em uso
- Tenant demo pizzaria:
  - `flow-engine/app/flows/tenants/pizzaria_bella_massa/atendimento_pizzaria_delivery.yaml`
- Estrutura com `intent_aliases`, `global_transitions`, estados de cardápio/pedido/consulta/atendente.
- Uso de transições por `contains:` e coringa `*` em etapas de coleta.

### Comandos operacionais locais
- Subir stack:
  - `docker compose up --build`
- Derrubar stack:
  - `docker compose down --remove-orphans`
- Para admin panel:
  - `flutter pub get`
  - `flutter analyze`
  - `flutter run -d chrome`
  - `flutter build web --release`

### Situação de tarefas recentes
- Concluído:
  - ajuste de mapeamento de status de assinatura
  - seed de superadmin e tenant demo
  - restrição do painel de company admin
- Em andamento:
  - validação e reset de banco

### Instruções para atuação nesta continuidade
- Priorize correções minimamente invasivas.
- Antes de alterar comportamento, valide erro real com análise/build/log.
- Não quebrar fluxos multi-tenant nem regras de assinatura.
- Ao corrigir UI Flutter, validar com `flutter analyze` + build web.
- Ao alterar fluxo YAML, validar referências de `target_state` e consistência de transições.

Agora continue a partir desse estado, propondo e executando as próximas correções com foco em estabilidade e previsibilidade.
