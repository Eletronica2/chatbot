# Atende Ai — IA-03: ativação do Qwen3 local para a Bella Massa

Data: 2026-10-22 (UTC 01:05–01:58). Configuração final aplicada às 01:57:29 UTC.
Resultado: **pronta para a primeira mensagem real**, somente do celular autorizado, somente para a Bella Massa.
Este relatório não contém senhas, tokens nem segredos HMAC.

| Item | Valor validado |
| --- | --- |
| Tenant | `pizzaria_bella_massa` (ID 5), "Bella Massa", active |
| WhatsApp | conta ID 1 → tenant 5, +55 34 3195-3594, Phone Number ID 1155710810954749, WABA 1299741078262298, active |
| Modo | `auto_reply_mode=allowlist`, allowlist = `["5534992665547"]` (1 número) |
| Provider | `ai_provider=local`, `local_ai_enabled=1` (somente tenant 5) |
| Modelo | `qwen3:4b-instruct-2507-q4_K_M`, CPU, contexto 4096, keep-alive 24h |
| Comunicação | AI Engine AWS → HMAC → WireGuard 10.77.0.1 ↔ 10.77.0.2 → FastAPI local |
| Conhecimento | Qdrant, 8 documentos da Bella derivados do fluxo de produção, filtrados por `tenant_id` |
| Outros tenants | inalterados (`gemini`, `on`, sem conta WhatsApp) |

## 1. Tenant confirmado
`tenants.id=5`, `external_key=pizzaria_bella_massa`, nome "Bella Massa", status `active`, owner `admin@bellamassa.com.br` (user 3, role `owner`, não Superadmin). Nada foi recriado ou duplicado.

## 2. WhatsApp vinculado
`whatsapp_accounts.id=1`:
- vínculo: `tenant_id=5`, `status=active`, `is_default=1` (o padrão é por tenant, sem efeito em outras empresas);
- token: cifrado, não exibido;
- criação: pelo Embedded Signup em 00:55:51 UTC (auditoria 17).

Recebimento real comprovado:
- o Gateway resolveu `phone_number_id=1155710810954749 → resolved_tenant=pizzaria_bella_massa`;
- a mensagem real (message 8, sessão 12) foi armazenada e bloqueada pelo modo `off` daquele momento.

Resolução do Gateway:
- é **exata por `phone_number_id`**;
- sem correspondência, não há envio (`META_ACCESS_TOKEN`/`META_PHONE_NUMBER_ID` globais continuam ausentes);
- os ecos do app Business (`smb_message_echoes`) só são registrados em log e nunca chegam ao backend.

## 3. WABA
`1299741078262298` (`account_key` da conta; confirmado também no evento `PARTNER_APP_INSTALLED`). Não alterado.

## 4. Phone Number ID
`1155710810954749`, exibido como +55 34 3195-3594. Não alterado; nada global foi configurado.

## 5. Allowlist
Implementação reutilizada: `tenant_settings.auto_reply_mode` / `auto_reply_allowlist` (backend). A verificação roda no servidor, **antes** de fluxo, IA e billing:
- **Remetente não autorizado:** a mensagem recebida é guardada, a conversa vai para atendimento humano, nada é enviado e nada é cobrado.
- **Remetente autorizado:** segue o fluxo normal.

Comportamento de falha segura:
- modo desconhecido equivale a `off`;
- allowlist vazia bloqueia todos;
- não existe curinga, prefixo nem sufixo.

A allowlist da IA-03 no Gateway e o trecho da IA-03 no AI Engine (que mantinha o "provider global" para remetentes não autorizados, ou seja, **Gemini**) existiam só na árvore de trabalho. Eles **não foram implantados**, porque o controle do backend já cobre esse papel e não há fallback para Gemini. Ficam pendentes de revisão (seção 24).

## 6. Normalização de telefone
O `wa_id` real enviado pela Meta é **`553492665547`** (12 dígitos, sem o nono dígito; está codificado no `wamid`). O Gateway o converte para `5534992665547`.

O backend passou a usar a mesma forma canônica: para celulares do Brasil com 12 dígitos, insere o 9. `+5534992665547`, `5534992665547`, `553492665547` e `+55 (34) 99266-5547` são o mesmo remetente.

Bloqueados (testes unitários):

| Caso | Valor |
| --- | --- |
| Outro número | `5534999999999` |
| Vazio | `""` |
| Nulo | `None` |
| Malformado | `abc` |
| Só o sufixo | `992665547` |
| Truncado | `553499266554` |
| Dígito extra | `55349926655470` |
| Final do número | `5547` |
| Curinga | `*` |

## 7. RBAC Superadmin
As alterações foram feitas pela API administrativa existente (`PATCH /api/v1/tenants/pizzaria_bella_massa/settings`), autenticada como Superadmin dentro do container (credencial lida do ambiente, nunca exibida). Não houve escrita direta no banco.

O owner da Bella recebe 403 ao tentar alterar `auto_reply_mode`, a allowlist ou o provider (validado em produção na etapa anterior). A API devolve apenas `auto_reply_allowlist_count`, nunca os números.

## 8. Auditoria de alteração

| ID | Ação | Conteúdo |
| --- | --- | --- |
| 18 | `tenant.ai_provider.update` | `ai_provider=local` |
| 19 | `tenant.auto_reply.update` | `mode=allowlist`, `count=1` |

Ambas no tenant 5, feitas pelo Superadmin.

## 9. Provider local
O backend envia `ai_provider=local` **somente** quando o tenant tem `ai_provider=local` **e** `local_ai_enabled=1`, o que hoje vale apenas para o tenant 5. Os demais tenants recebem `gemini`.

O AI Engine em produção é o HEAD (`86d4980`), sem o trecho da IA-03. Uma falha local resulta em `handled=false` e texto vazio: **nunca há fallback para Gemini** (18 testes no código implantado).

## 10. Feature flag
`LOCAL_AI_ENABLED` funciona como **interruptor mestre** da infraestrutura local. Não é roteamento padrão: `AI_PROVIDER` global continua `gemini`. Agora está `true` no `.env.production`.

O roteamento por tenant vem do backend. Com a flag `false`, um tenant `local` recebe `local_ai_disabled`: atendimento humano, sem Gemini. Isso funciona como kill switch.

## 11. HMAC
As credenciais da IA-02 estavam revogadas: o AI Engine estava com `LOCAL_AI_KEY_ID` vazio e o servidor local sem chave.

Nova chave operacional `aws-ai-engine-bella-pilot-20261022`:
- 256 bits, gerada com `secrets.token_bytes`;
- **somente** o tenant `pizzaria_bella_massa`;
- escopos `respond`, `knowledge:read` e `knowledge:write`;
- validade até 2027-01-31.

Armazenamento:
- servidor local: `.env` (600, dono `atendeai`);
- AWS: `.env.production` (600);
- o arquivo temporário foi destruído com `shred`;
- não está no Git nem em logs.

Testes negativos pela VPN:
- a chave da Bella usada para outro tenant recebe **403**;
- um segredo errado recebe **401**.

## 12. WireGuard
`wg0` ativo nos dois lados, `vpn_peer_ok=true`, RTT do túnel em torno de 190–230 ms, Wi-Fi a −56 dBm. O monitor de rede está ativo. Nada foi alterado.

## 13. FastAPI local
`/ready=true` em todas as verificações. A API escuta somente em `127.0.0.1:8100` e no proxy `10.77.0.2:8100`. Externamente, as portas 8100, 8003, 8000, 3306, 11434, 6333 e 40000 da AWS estão fechadas.

Correções implantadas (`ai-api`, imagem anterior marcada `pre-ia03-20261022`):
- **Sonda de prontidão com o mesmo `num_ctx` (4096) das requisições reais.** Antes ela usava 512, o que obrigava o Ollama a recarregar o modelo (cerca de 29 s) depois de cada sonda.
- **Pergunta sobre algo que a empresa oferece nunca recebe a resposta "fora do assunto".** Foram ajustados a política (regra 8) e um guard determinístico (`offering_question_without_data`).
- **Guard de entidades com tolerância a singular/plural.** Antes "Pizza" era tratada como nome desconhecido quando só "pizzas" aparecia nos documentos.
- **Configuração:** `LLM_KEEP_ALIVE=24h`, `HISTORY_MAX_MESSAGES=4`, `HISTORY_MAX_CHARS=700`. O histórico com textos longos do fluxo fazia o prompt passar de 1.600 tokens e atingir o timeout de 45 s.

## 14. Qdrant
**Conflito encontrado:**

| Fonte | Calabresa grande | Tamanho grande |
| --- | --- | --- |
| Fixtures da IA-01 | R$ 65,00 | 35 cm |
| Fluxo de produção da Bella | R$ 62,90 | 45 cm |

Na resposta `fallback_ai`, o texto da IA e a mensagem do fluxo aparecem juntos, então os dois precisam ter exatamente os mesmos dados. O fluxo é a fonte oficial do tenant.

**Ação:**
- 8 documentos foram gerados do YAML do fluxo, com cópia literal dos textos. A única transformação foi tornar explícitas as colunas de preço broto/média/grande, conforme a legenda do próprio fluxo. Gerador: `atende-ai-local/scripts/build_bella_flow_knowledge.py`; operações em `atende-ai-local/knowledge/pizzaria_bella_massa.sync.json`.
- Foram sincronizados pelo caminho oficial: `/v1/knowledge/sync` com HMAC e versionamento.
- As fixtures `cardapio`, `regras` e `entrega` foram retiradas **somente** da Bella, com tombstone.
- A reexecução retornou `unchanged` nas 11 operações (idempotente).

Resultado:
- Qdrant: 8 pontos na Bella e 4 na `pastelaria_do_ze` (intocada).
- Snapshot anterior: `atende_knowledge-…-2026-10-22-01-44-50.snapshot`.

## 15. Qwen3
Chamadas reais da AWS ao Qwen3 local (`provider=local`, `model=qwen3:4b-instruct-2507-q4_K_M`, RAG com 3 documentos):

| Pergunta | Resposta | Tempo |
| --- | --- | --- |
| Quanto custa a pizza de calabresa grande? | "A pizza de calabresa grande custa R$ 62,90." | 20,6 s |
| Vocês oferecem Wi-Fi? | "Não tenho essa informação confirmada no momento. Posso encaminhar sua dúvida para a equipe?" | 18,5 s |
| Tem estacionamento próprio? | Mesma resposta padrão de informação não confirmada | 13,9 s |
| Quem ganhou o jogo do Flamengo ontem? | Resposta "fora do assunto" (correta) | 15,7 s |

Com o modelo aquecido e o histórico reduzido, o caminho completo levou de 3,5 a 10,7 s (referência da IA-01: 13,3 s típico, p95 16,9 s). A primeira inferência depois de um período ocioso pode chegar a cerca de 25 s. O limite total é de 45 s; depois disso, a conversa vai para atendimento humano.

## 16. Flow Engine
O fluxo `atendimento_pizzaria_delivery` (início `boas_vindas`) tem `fallback_ai` no fluxo e nos estados informativos. Execução simulada (dry-run) do pipeline real: FlowService, AIService do backend com os metadados reais da Bella e a mesma composição de resposta. Não houve persistência, envio nem billing.

| Mensagem | Caminho | Resposta |
| --- | --- | --- |
| "Boa noite" | fluxo `boas_vindas`, determinístico, sem IA (35 ms) | Boas-vindas do fluxo |
| "Quanto custa a pizza de calabresa grande?" | a transição `contains:pizza` leva ao estado `cardapio_principal` (determinístico) | Cardápio por categoria, **sem o preço exato** |
| "Vocês oferecem Wi-Fi?" | `fallback_ai`, Qwen3 (4,0 s) | "Não tenho essa informação confirmada…" seguida do cardápio |
| "Tem pizza grande?" | `fallback_ai`, Qwen3 (3,7 s) | "Sim, temos pizza grande (45cm), pra 3-4 pessoas." |
| "De calabresa" | `fallback_ai`, Qwen3 (5,2 s) | "Sim, temos calabresa grande: R$ 62,90." |
| "Quanto custa?" | `fallback_ai`, Qwen3 (10,7 s) | "Calabresa grande: R$ 62,90." |

Não houve contradições. Os hooks `confirmar_pedido` e similares são apenas metadados: não executam pedidos.

## 17. Billing V2
Comportamento real auditado para a Bella, que está `trialing`, sem `tenant_billing_config` e em modo `customer_direct`:
- A verificação prévia (preflight) permite a mensagem; não existe crédito de plano.
- A resposta gera uma reserva `legacy_unmetered`, ou seja, rastreamento sem consumo de franquia. É o mecanismo oficial para tenants sem plano.
- O Gateway confirma a reserva com o `wamid` (`accepted`).
- O status `delivered` gera um `COMMIT` único; um `failed` libera a reserva.
- Não há Stripe nem fatura.

Testes em MySQL descartável (`test_billing_pilot_trial_mysql.py`, 4 testes):
- ciclo completo com `delivered` duplicado gerando um único `COMMIT`;
- reserva idempotente;
- falha antes da Meta libera a reserva;
- `failed` vindo da Meta libera a reserva;
- status de mensagem recebida sem reserva não consome nada;
- nenhum bucket nem fatura criados.

**Billing PASS** para o comportamento testado. A confirmação final com uma mensagem real será feita durante o teste.

## 18. Fallback humano
A falha de IA tem o mesmo efeito em todos os casos: a mensagem recebida é preservada, a conversa vai para atendimento humano (`human_handoff_pending`), nada é enviado e nenhuma reserva é criada.

Casos testados no código implantado (18 testes):

| Falha | Resultado |
| --- | --- |
| VPN indisponível | `local_ai_unreachable` |
| Timeout do Qwen3 | `local_ai_timeout` |
| Fila cheia ou 503 | `local_ai_saturated` |
| Ollama indisponível | `local_ai_inference_error` |
| Deadline estourado | 504 |
| HMAC inválido | sem nova tentativa |
| Flag desligada ou chave ausente | `local_ai_disabled` |

Em todos, a resposta legada do `/ai/respond` volta com texto vazio.

**Comprovado ao vivo:** dois timeouts reais de 45 s no dry-run, antes da redução do histórico, terminaram em atendimento humano, sem resposta e sem Gemini.

Atendimento já assumido por humano (`assignment_mode=human`) não gera resposta automática. Webhook duplicado não é processado duas vezes (testes H e G).

## 19. Testes realizados

| Suíte | Resultado |
| --- | --- |
| Backend | **142 passed** (inclui MySQL descartável: Billing V2 + piloto trial, allowlist A–H, normalização, máscara do preflight) |
| AI Engine (código HEAD implantado) | **18 passed** |
| API local | **79 passed** |
| Smoke privado AWS → Qwen3 | 4 perguntas, mais os 2 testes negativos de HMAC |
| Dry-run do pipeline | 6 mensagens, executado duas vezes |
| Portas | AWS fechadas; API local só em loopback e túnel |

Nenhuma mensagem real foi enviada por mim.

## 20. Deploy
Backups:
- `/var/backups/atende-ai-ia02/pre-ia03-bella-20261022T012139Z/` com dump MySQL (38 tabelas), código, compose e `.env.production` (600, com SHA256SUMS);
- imagens marcadas `atende-prod-*:pre-ia03-20261022` e `atende-ai-local/ai-api:pre-ia03-20261022`.

| Serviço | Mudança |
| --- | --- |
| backend-api (rebuild) | número canônico; máscara do `verify_token` no preflight; testes |
| backend-api, whatsapp-gateway (recriados, mesma imagem no gateway) | cadeia de timeouts no Compose: `AI_ENGINE_TIMEOUT=60`, `BACKEND_API_TIMEOUT=75`. Antes era 20 s, menor que a inferência. |
| ai-engine (recriado com a imagem HEAD, sem rebuild) | variáveis HMAC; `LOCAL_AI_ENABLED=true` |
| ai-api local (rebuild) | correções da seção 13 |

MySQL, Flow Engine, nginx, Ollama e Qdrant não foram reconstruídos. Nenhuma migration nesta etapa.

## 21. Serviços healthy
- **AWS:** ai-engine, backend-api, flow-engine, mysql e whatsapp-gateway healthy; nginx no ar.
- **Local:** ai-api, ollama e qdrant healthy; Qwen3 4B carregado (contexto 4096, mantido por 24h).

## 22. Outras empresas preservadas
Os tenants 1–4 continuam com `gemini`, `local_ai_enabled=0` e `auto_reply_mode=on`. Nenhuma conta WhatsApp, plano ou ledger deles foi alterado. A chave HMAC só autoriza `pizzaria_bella_massa`.

Mudanças que valem para todos, sem alterar comportamento:
- timeouts maiores;
- `verify_token` mascarado para usuários que não são Superadmin.

## 23. Kill switch
Em ordem de preferência:
1. **Imediato, sem restart:** `PATCH /api/v1/tenants/pizzaria_bella_massa/settings {"auto_reply_mode":"off"}` como Superadmin. As mensagens passam a ser guardadas e ir para atendimento humano.
2. **Desligar a IA local:** `LOCAL_AI_ENABLED=false` no `.env.production`, depois `docker compose ... up -d --no-build --no-deps --force-recreate ai-engine`. Um tenant `local` passa a cair em atendimento humano, sem Gemini.
3. **Revogar a chave:** remover `aws-ai-engine-bella-pilot-20261022` do `SERVICE_KEYS_JSON` local e recriar o `ai-api`.

Nenhum desses passos afeta outras empresas nem desliga o Gateway.

## 24. Pendências

- **Primeira pergunta de preço:** o fluxo intercepta "pizza" e mostra o cardápio por categoria. A pergunta repetida já no cardápio, ou "De calabresa", chega ao Qwen3 com o preço correto. Não alterei o fluxo do tenant.
- **Respostas `fallback_ai` longas:** a resposta junta o texto da IA com a mensagem completa do estado (por exemplo, o cardápio inteiro). É o comportamento atual da composição.
- **Mensagens consecutivas:** não há agrupamento (debounce). Mensagens em rajada viram inferências separadas (fila de no máximo 2 por tenant). Melhoria de desempenho futura.
- **`request_id` aleatório:** o AI Engine usa um `request_id` aleatório porque o backend não envia o `message_id` nos metadados. A deduplicação no servidor local não cobre novas tentativas entre camadas; o backend já deduplica webhooks.
- **Confirmação de leitura:** o Gateway marca como lidas as mensagens recebidas (confirmação azul), mesmo as bloqueadas.
- **Reset da senha do Superadmin:** o hash é regravado a cada restart do backend (P2, comportamento existente).
- **Alterações da IA-03 não implantadas:** Gateway e AI Engine continuam na árvore de trabalho. O trecho do AI Engine reintroduziria o fallback para Gemini e **não deve ser implantado** assim.
- **Senhas em texto puro:** `CREDENCIAIS_TESTE.md` e `settings.py` (P1, não tocado).
- **Marca de handoff antiga:** a sessão 12 ainda tem `human_handoff_pending=true`, do bloqueio anterior. Não impede a IA (`assignment_mode=ai`), só aparece como pendência no painel.
- **Commits:** nenhum foi feito.

## Incidente da primeira mensagem (02:00 UTC) — corrigido

**Sintoma:** o "Boa noite" das 02:00:43 UTC não teve resposta, e nada apareceu no Gateway nem no banco.

**Causa:**
- A Meta entregou o webhook seis vezes (02:00:43–02:01:15). O Nginx respondeu **502** em todas, com `connect() failed (111) upstream http://172.18.0.6:40000`.
- O Nginx em container usa blocos `upstream` estáticos (`backend_api`, `whatsapp_gateway`). Os IPs dos containers são resolvidos **uma vez**, quando o Nginx inicia (12/10).
- Ao recriar `whatsapp-gateway` e `backend-api` durante esta ativação, os containers receberam novos IPs: o Gateway passou de `.6` para `.7`, e o `.6` ficou com o backend, que não escuta na porta 40000. Com isso, o Nginx continuou mandando o tráfego para o endereço antigo.
- A mensagem nunca chegou ao Gateway. Allowlist, fluxo, IA e billing não chegaram a ser executados.

**Correção (02:05:05 UTC):**
- `nginx -t` seguido de `nginx -s reload` no container: reload gracioso que só refaz a resolução dos nomes. A configuração não foi alterada, não houve downtime e nenhum outro serviço foi tocado.
- Verificação pós-reload: `GET /webhook` chegou ao Gateway, que consultou o backend (403 esperado, porque usei um token inválido de propósito). `/api/*` do painel voltou a chegar ao backend (401 sem token), e os dois `/health` responderam 200.

**Prevenção:**
- Depois de qualquer `up -d`/recreate de `backend-api` ou `whatsapp-gateway`, executar `docker compose -p atende-prod ... exec nginx nginx -s reload` e testar `GET /webhook` (esperado 403, nunca 502).
- O monitor agora inclui o Nginx (POST `/webhook` e `connect() failed`).
- Solução definitiva, sem reload manual: `resolver 127.0.0.11` com `proxy_pass` via variável no Nginx. Fica pendente, porque esta fase não altera o Nginx.

**Reentrega:** a Meta reenvia webhooks que falharam, com intervalos crescentes. O "Boa noite" original pode chegar mais tarde. Se chegar, será processado uma única vez (deduplicação por `wamid`) e terá resposta normal.

## Incidente 2 — Meta recusou o envio (#10), 02:09–02:11 UTC — corrigido

**Percurso comprovado:**
- **"Boa noite" (wamid recebido às 02:09:30, reentregue pela Meta):**
  - Nginx → Gateway (`resolved_tenant=pizzaria_bella_massa`) → backend (allowlist liberou o remetente) → fluxo `boas_vindas`.
  - Billing: `RESERVE` legacy_unmetered.
  - **Envio recusado.** Em seguida, `RELEASE send_failed`.
- **"Vocês oferecem Wi-Fi?" (02:10:47):**
  - Fluxo → `fallback_ai` → AI Engine → HMAC/WireGuard → **Qwen3 gerou a resposta**: `local_ai_ok`, `qwen3:4b-instruct-2507-q4_K_M`, 1280→22 tokens, 9,9 s no servidor e 10,3 s vistos pela AWS. `ai_usage_events` registrado com custo NULL.
  - `RESERVE` → **envio recusado** → `RELEASE send_failed`.
- **Billing correto:** sem `COMMIT`, sem `usage_events`, sem cobrança. Não houve status de entrega porque nada foi aceito pela Meta.

**Erro exato no Gateway:**
`(#10) You do not have WhatsApp granular permission for sending messages on behalf of this WhatsApp Business Account`

**Diagnóstico (somente leitura):**
- O token salvo pelo Embedded Signup é válido (`SYSTEM_USER` do negócio cliente) e tem `whatsapp_business_messaging` para o WABA 1299741078262298.
- O WABA é `CLIENT_OWNED`: pertence ao negócio "Pizzaria Bella Massa" (1348385330573371), não ao negócio dono do app.
- O app ainda não tem **Advanced Access** (App Review pendente, conforme `docs/meta-proximos-passos.md`). Pela documentação da Meta, sem Advanced Access um parceiro não pode agir em ativos de outro negócio com o token do cliente.
- Prova sem enviar nada: a chamada `mark as read` em uma mensagem já recebida, que exige a mesma permissão, retornou **400 #10** com o token do Embedded Signup e **200** com o token System User do parceiro.
- `health_status`: número `CONNECTED`; WABA e APP `AVAILABLE`; BUSINESS `LIMITED` (141010, empresa não verificada, que limita volume mas não bloqueia).

**Correção (02:17 UTC, temporária, somente a conta da Bella):**
- A conta `whatsapp_accounts.id=1` passou a usar o token System User do parceiro (`META_SYSTEM_USER_TOKEN`).
- O mecanismo usado é o já existente, `WhatsAppAccountService.update_account`, com o token cifrado por `TokenCipher`. É o mesmo mecanismo do `ensure_fresh_access_token`.
- Auditoria 20: `whatsapp_account.sending_token.pilot_partner`.
- Nada global foi configurado. WABA, coexistência, webhook e Meta não foram alterados.
- Validação: `mark as read` com o token da conta retornou 200.

**Rollback / definitivo:**
- O valor anterior (cifrado) está em `/var/backups/atende-ai-ia02/pre-ia03-bella-20261022T012139Z/bella-sending-token-before.env` (600).
- Para restaurar: `PREVIOUS_ENCRYPTED_TOKEN=… python - restore < scripts/ia03_bella_sending_token.py` no backend.
- Definitivo: obter Advanced Access para `whatsapp_business_messaging` e `whatsapp_business_management` (App Review) e então voltar ao token do cliente.
- Este token do parceiro alcança todos os ativos compartilhados com o negócio do app. Por isso a medida é só do piloto.

**Pendências observadas:**
- As mensagens de saída 10 e 12 foram gravadas como respostas, mas **não foram entregues**. O painel não indica falha de envio: o Gateway só libera a reserva e não marca a mensagem.
- O `mark_as_read` do Gateway ignora erros em silêncio.
- A sessão 12 mantém `human_handoff_pending=true` desde o bloqueio anterior. Isso não impede a IA.
- As respostas não entregues **não serão reenviadas** automaticamente.

## Incidente 3 — entrega bloqueada pela Meta (#131031), 02:19 UTC — bloqueio externo

**Percurso comprovado ("Vocês oferecem Wi-Fi?", wamid recebido às 02:19:34):**
- Nginx 200 → Gateway (tenant `pizzaria_bella_massa`) → backend (allowlist liberou o remetente) → fluxo `fallback_ai` → AI Engine → WireGuard → **Qwen3**: `local_ai_ok`, `qwen3:4b-instruct-2507-q4_K_M`, 1379→22 tokens, 10,2 s no servidor e 10,6 s vistos pela AWS.
- Billing: `RESERVE` legacy_unmetered.
- **A Meta aceitou o envio** às 02:19:46. O wamid de saída foi gravado e a reserva passou para `accepted` às 02:19:47.
- Às 02:19:49 chegou o status **`failed` #131031 "Business Account locked"**. Não houve `sent` nem `delivered`.
- Billing: a reserva foi **liberada** (`released`, `last_provider_status=failed`), e o evento de status foi aplicado uma vez (`applied=1`). Não houve `COMMIT`, cobrança nem `usage_events`.
- Sem duplicidade: 1 mensagem recebida, 1 enviada, 1 reserva, 1 status.

**Causa (documentação oficial + leitura do Meta):**
- `131031` significa WABA restrita ou desativada pela Meta, ou dado da requisição que não confere com o WABA (por exemplo, o PIN). O PIN não se aplica: o número está em coexistência e `is_pin_enabled=false`.
- WABA 1299741078262298: `account_review_status=PENDING`, `ownership_type=CLIENT_OWNED`.
- Negócio dono "Pizzaria Bella Massa" (1348385330573371): `not_verified` (141010).
- Número: `LIVE`, `TIER_250`, nome exibido "Atende Ai".
- O relatório da IA-03 já registrava o WABA como `Restricted`, com a mensagem "verifique sua empresa antes de enviar", antes de qualquer envio nosso.
- O pipeline do Atende Ai está completo. O bloqueio está na conta da Meta.

**Não há correção possível pelo código.** Ações do proprietário na Meta:
1. **WhatsApp Manager** (WABA 1299741078262298) e **Account Quality** (`business.facebook.com/accountquality`): ver o motivo da restrição e, se houver a opção, clicar em **Request review**.
2. **Verificação do negócio** "Pizzaria Bella Massa". Exige documentos reais de pessoa jurídica. Como a Bella é fictícia, isso pode não ser possível de forma legítima.
3. **Alternativa recomendada:** fazer o piloto com um WABA de negócio **verificado** (por exemplo, o negócio do CNPJ dono do app). Isso muda número, WABA e coexistência, então só deve ser feito com autorização explícita, numa etapa própria.
4. **Não** redefinir PIN nem registrar o número de novo (coexistência).

**Estado mantido:** allowlist e provider local continuam ativos. Cada mensagem do testador gera inferência e uma tentativa que a Meta bloqueia, com a reserva liberada (sem custo). Kill switch, se preferir pausar: `auto_reply_mode=off`.

## Investigação Meta (22/10, 02:33–02:55 UTC) — causa raiz real do #10 e do #131031

**Correção de diagnóstico anterior:**
- O app **já tem Advanced Access**. O envio de App Review de 12/08/2026 foi **aprovado**: `whatsapp_business_messaging`, `whatsapp_business_management` e `public_profile`. O de 28/07 havia sido reprovado.
- A hipótese "#10 por falta de Advanced Access" estava **errada**.
- O token do parceiro usado às 02:17 **causou** o #131031. Ele já foi removido.

**0. Automação:** `auto_reply_mode=off` no tenant 5 às 02:33 UTC (auditoria 21). Allowlist (1 número), provider local, histórico e demais tenants preservados.

**1. Onde naveguei** (navegador do Cursor, sessão aberta pelo proprietário; sem senha nem cookies):
- WhatsApp Manager do WABA 1299741078262298: visão geral, alertas, números, registro de atividades e configurações de pagamento.
- Business Support Home e "Minhas contas"; Account Quality (redireciona para o Support Home).
- Configurações dos portfólios Bella, Atende Ai e AAA as: usuários do sistema, parceiros, contas do WhatsApp, contas de mensagens e Central de Segurança.
- App Dashboard 873826165763092: ações necessárias, Análise do app e configurações do Login para Empresas.

**2–4. Portfólios, WABA e status real:**

| Entidade | ID | Status |
| --- | --- | --- |
| Portfólio "Pizzaria Bella Massa" (dono do WABA) | 1348385330573371 | sem problemas, não verificado |
| Portfólio "Atende Ai" (dono do app e do System User "AtendaAi_WhatsApp") | 506485032393364 | **verificado** (CNPJ 34.144.027 ARTHUR GABRIEL MARTINS LARANJO, desde 02/06/2026) |
| Portfólio "AAA as" (conta antiga de teste US) | 2330602324386620 | "Conta com restrição"; **não** relacionado à Bella |
| Messaging account "Atende Ai" | 1299741078262298 | "Aprovada", pagamento MASTERCARD *6565 |
| WhatsApp account | 2404587199968825 | número +55 34 3195-3594 "Conectado", 250 clientes/24h |

Business Support Home e Account Quality: "Nenhum problema com a conta ou ativo". Sem violação, sem pedido de documentos, sem "Request review" disponível e sem caso de suporte ativo.

**5. Motivo exato:**
- A única configuração de Embedded Signup do app era **"Parceiro de mensuração do WhatsApp"** (2257921298375333). É o modelo da Meta que "concede aos parceiros **acesso somente leitura** à conta do WhatsApp Business".
- O registro de atividades confirma o efeito: as tarefas concedidas foram `View_Templates` e `View_Phone_Asset`, sem `MESSAGING`.
- Consequências:
  - **#10:** o token do Embedded Signup não pode enviar.
  - **#131031:** o envio feito pela identidade do parceiro foi aceito e depois bloqueado. O portfólio Atende Ai é parceiro da Bella, mas com **0 ativos atribuídos**.
- Não havia restrição de política no WABA.

**6–8. Ações executadas:**

| Ação | Detalhe |
| --- | --- |
| Nova configuração no App Dashboard | **"Atende Ai ES WhatsApp envio" (1778153380113357)**. Variação Cadastro incorporado do WhatsApp; produto **só WhatsApp Cloud API**; token de System User (expiração "Nunca", porque o backend ainda não renova tokens); ativo **só Contas do WhatsApp** com tarefas **MESSAGING, VIEW_PHONE_ASSETS, VIEW_TEMPLATES** (sem MANAGE/DEVELOP); permissões `whatsapp_business_management` e `whatsapp_business_messaging`. A configuração antiga não foi alterada. |
| `META_EMBEDDED_CONFIG_ID=1778153380113357` | `.env.production` (backup `.env.production.before-config-1778153380113357`); recriado só o backend-api e feito reload do Nginx. Webhook 403 esperado e API 401. |
| Token da conta Bella | Restaurado o token original (auditoria 22). O token do parceiro foi removido da conta. O token original hoje só tem `manage_events`/`public_profile` e precisa de um novo onboarding. |
| Atribuição de parceiro | **Não feita.** A Meta só oferece "Tudo" (configurações, usuários, pagamento) para envio, o que viola o menor privilégio e não é necessário com a configuração correta. |

**9–11.** Revisão: não solicitada (não há restrição nem botão de revisão). Protocolo: nenhum. Documentos: nenhum exigido; a verificação do portfólio Bella (fictícia) não é pré-requisito para enviar no limite de 250.

**12. Reconexão necessária:** sim. É preciso um novo Embedded Signup pela configuração correta para obter um token com a tarefa `MESSAGING`.
- O vínculo local é atualizado no mesmo registro (`whatsapp_accounts` id 1, upsert por tenant + WABA), sem duplicidade.
- Backup do vínculo: `whatsapp-accounts-before-reonboarding.sql.gz`.

**13–14.** MySQL: só `tenant_settings.auto_reply_mode` (via API) e o token cifrado da conta 1 (via serviço, auditado). Backups em `/var/backups/atende-ai-ia02/pre-ia03-bella-20261022T012139Z/`.

**15–16.** WhatsApp: recebimento normal; envio pendente de reconexão. Automação: `off`.

**17.** Da Meta não depende nada além do proprietário concluir o Embedded Signup (QR da coexistência, se a Meta pedir).

**18. Próximo teste:** somente depois de:
1. o onboarding novo;
2. a validação do token, que deve ter `MESSAGING` (o probe "mark as read" deve retornar 200 com o token da conta);
3. a volta para `allowlist`.

## Reconexão pela nova configuração (22/10, 02:57–03:08 UTC)

**Fluxo executado** (navegador do Cursor, painel logado como Bella; pop-up com `config_id=1778153380113357`, coexistência):
- Número existente "+55 34 3195-3594 · Registrado" (sem SMS nem novo registro).
- Portfólio "Pizzaria Bella Massa".
- QR da coexistência lido pelo proprietário no app WhatsApp Business.
- Tela final da Meta: "Sua conta está conectada a Atende Ai".

**Retorno ao painel não aconteceu:**
- Cliquei em "Concluir", mas a janela do Cursor fechou antes de o pop-up devolver o código.
- Não houve `exchange` no backend, e o registro `whatsapp_accounts` id 1 ficou inalterado.

**Estado na Meta após a reconexão** (sem enviar mensagem):
- Mesmo WABA 1299741078262298 e mesmo número 1155710810954749, ambos CONNECTED/LIVE, `ownership_type=CLIENT_OWNED`, dono "Pizzaria Bella Massa". Nenhum WABA nem número novo.
- `health_status`:
  - WABA `AVAILABLE`, app `AVAILABLE`.
  - Número `LIMITED`, só pelo limite de 250/24h, porque o nome de exibição e o portfólio não estão verificados (141010).
  - Nenhum bloqueio de conta.
- O token já gravado na conta (mesmo usuário de integração do app + portfólio, expiração "nunca") passou a ter `whatsapp_business_messaging` e `whatsapp_business_management` granulares para o WABA 1299741078262298. Antes tinha só `manage_events`.
- Probe "mark as read" na última mensagem recebida (02:19, anterior à reconexão): `#100 Invalid parameter` com os dois tokens.
  - Não houve mais `#10` (sem permissão) nem `#131031` (conta bloqueada), ou seja, a camada de permissão aceitou o token.
  - O `#100` se refere ao parâmetro: essa mensagem antiga não pode mais ser marcada como lida.
  - O 200 definitivo só virá com uma mensagem real.

**Passo do exchange que faltava:**
- `subscribed_apps` do WABA estava **vazio**: o app não recebia mais webhooks dessa WABA.
- Executei apenas o passo de assinatura do fluxo oficial (`MetaGraphService.subscribe_waba_webhooks`), com o token da conta. Script `backend-api/scripts/ia03_bella_resubscribe_waba.py`, auditoria 23 `whatsapp_account.webhook.resubscribe`.
- Resultado: app 873826165763092 assinado novamente.
- URL de callback e configuração de webhook do app não foram alteradas.
- A troca de código por token não foi necessária, porque o token gravado já tem a permissão.

**Automação:**
- `auto_reply_mode=allowlist` com 1 número (5534992665547), via API Superadmin. Script `backend-api/scripts/ia03_bella_auto_reply.py`, auditoria 24 `tenant.auto_reply.update`.
- Tenants 1–4 inalterados (`on`, `gemini`).

**Verificações finais:**
- `whatsapp_accounts`: um único registro, id 1, tenant 5.
- Webhook: verificação com token errado retorna 403.
- AWS acessa a API local pelo WireGuard (200).
- Contêineres de produção healthy.
- Nenhuma mensagem enviada por mim.

**Status:**
- A WABA **não está restrita** (`can_send_message=AVAILABLE`).
- O envio só fica comprovado depois da mensagem manual do proprietário. Se a Meta recusar, `ia03_bella_monitor.sh` mostrará o código exato.

## Teste de 03:10 UTC — sem resposta porque a conversa estava com humano (corrigido)

**O que funcionou:**
- Meta → Nginx (`POST /webhook` 200) → Gateway (tenant `pizzaria_bella_massa`, WABA 1299741078262298) → backend (mensagem 16 persistida).
- O "mark as read" do Gateway no inbound retornou **HTTP 200** com o token da conta. Antes da reconexão, a mesma chamada dava #10. Esta é a prova real de que a permissão de envio voltou.
- Sem #10 e sem #131031.

**Por que não houve resposta:**
- A sessão do 5547 estava com `assignment_mode=human`, `assigned_user_id=3` (owner da Bella).
- Às 02:23:53 uma resposta manual foi enviada pelo painel (mensagem 15, `source=human`, `admin_panel`). Por regra, resposta humana assume a conversa.
- Com a conversa em modo humano, o backend guarda o inbound (`awaiting_human`) e não chama fluxo, IA nem billing. Comportamento correto.
- Nenhuma reserva de billing e nenhum envio para a mensagem 16.

**Correção:**
- Conversa devolvida para a IA pela rota oficial `POST /api/v1/conversations/{id}/return-to-ai`. Script `backend-api/scripts/ia03_bella_return_to_ai.py`, auditoria 25 `conversation.return_to_ai`.
- Resultado: `assignment_mode=ai`.
- Só essa conversa foi alterada.
- A mensagem 16 não é respondida retroativamente; o próximo teste exige um novo envio manual pelo proprietário.

## Teste de 03:15 UTC — pipeline completo; Meta falhou a entrega com #131031 (bloqueio externo)

| Etapa | Resultado |
| --- | --- |
| Nginx | `POST /webhook` 200 às 03:15:25 |
| Gateway | tenant `pizzaria_bella_massa`, WABA 1299741078262298; inbound `wamid…QUNBM0I0…` |
| Backend | allowlist aprovou; Flow Engine `requires_ai_fallback` |
| Qwen3 local | `local_ai_ok`, nível RAG, 3 trechos, 1305/22 tokens, servidor 8,1 s, ponta a ponta 8,5 s |
| Envio | Cloud API aceitou às 03:15:36, mensagem `wamid…ERgUQ0U3MDU2RkZDQzQyQTEyMjhCN0MA` |
| Status Meta | **`failed` #131031 "Business Account locked"** às 03:15:39; não houve sent, delivered nem read |
| Billing V2 | reserve → accepted → **release** (`provider_status=failed`); ledger RESERVE 1 / RELEASE 1; sem cobrança |
| Duplicidade | 1 inbound (17) e 1 outbound (18) |

Latência: 11 s do webhook até o aceite da Meta, dos quais 8,5 s são do Qwen3.

**Ação imediata:**
- `auto_reply_mode=off` (via API Superadmin, auditada), para não insistir contra uma conta bloqueada.
- Allowlist mantida (1 número).

**Diagnóstico** (GET somente leitura): tudo sob nosso controle está correto.
- WABA `status=ACTIVE`, `on_behalf_of_business_info.status=APPROVED`.
- Número CONNECTED/LIVE, `is_on_biz_app=true` (coexistência ativa), webhook apontando para `https://api.meuatendeai.com.br/webhook`.
- App assinado e token com `MESSAGING`. O "mark as read" retornou 200, então a permissão de envio funciona.
- Pendência única: **`account_review_status=PENDING`**. É a revisão da WABA iniciada pela Meta no onboarding ("Analisaremos sua empresa… notificaremos você em até 24 horas").
- Enquanto essa revisão não termina, a Meta rejeita os envios por API com #131031, mesmo com `health_status=AVAILABLE`. É um padrão conhecido: a camada de entrega não aparece nos campos públicos.

**Status:**
- **NÃO RESOLVIDO.** O bloqueio é externo, na revisão da Meta.
- Não há documento a enviar nem botão de revisão disponível.
- A Bella é fictícia: não serão apresentados dados nem documentos inventados.

## Causa real do #131031 (22/10, 09:30–09:45 UTC): a Meta exige verificação do portfólio Bella

**Reconexão do proprietário às 09:28 UTC** (pelo painel): o exchange oficial foi concluído.
- `oauth/access_token` → `subscribed_apps` 200 → registro `whatsapp_accounts` id 1 atualizado, sem duplicidade.
- Auditoria 27 `whatsapp_onboarding.embedded_signup`.
- Eventos `PARTNER_APP_INSTALLED` e `WEBHOOK_CONFIG_UPDATED` recebidos.
- Token novo: System User, sem expiração, `messaging` + `management` para o WABA 1299741078262298.

**Mensagens de 03:39 e 09:29 UTC:** apenas armazenadas (`auto_reply_disabled`). Sem envio, sem billing.

**WhatsApp Manager** (navegador do Cursor), WABA 1299741078262298:
- Alerta **"Esta conta ainda não pode enviar mensagens no WhatsApp — Antes de começar a enviar mensagens, é necessário verificar sua empresa."**
- Conta de mensagens "Atende Ai": **"Conta restrita — Antes de começar a enviar mensagens, você precisará verificar sua empresa."**
- Os outros 2 alertas são informativos (agenda de contatos; termos de marketing).

**Central de Segurança do portfólio 1348385330573371:** "Verificação para Pizzaria Bella Massa — Qualificada para verificação — Iniciar verificação". **Não iniciada**: a Bella é fictícia e não há documentos legítimos.

**Business Support Home:** "Nenhum problema com a conta ou ativo". Não há caso aberto nem botão de revisão.

**Suporte direto:** "Você não é membro de nenhum negócio qualificado". O link "Entre em contato com o suporte" do WhatsApp Manager leva só a `developers.facebook.com/support/`.

**Conclusão:**
- O #131031 é o efeito da revisão da WABA (`account_review_status=PENDING`). A Meta passou a exigir que o portfólio dono da WABA seja verificado antes de qualquer envio.
- `health_status` não reflete isso, um padrão relatado por outros desenvolvedores no fórum da Meta e em documentação de BSPs.
- Não é uma penalidade revisável: é um pré-requisito que só a verificação legítima do portfólio satisfaz.
- Não foi aberto chamado: não há canal elegível, e pedir isenção da verificação para uma empresa fictícia não seria legítimo.

**Correção de segurança no backend:**
- O logger `httpx` (INFO) gravava a URL completa das chamadas Graph, incluindo `client_secret` no exchange e `access_token` nas demais.
- `backend-api/main.py` agora fixa `httpx`/`httpcore` em WARNING. Deploy só do backend-api (backup `backend-main.py.before-httpx-log-fix`), container healthy, Nginx recarregado.
- O container antigo, com o log, foi recriado.
- **Recomendado:** rotacionar o App Secret no App Dashboard e atualizar `META_APP_SECRET`, porque o valor apareceu em log.

## Viabilidade de levar o 3594 para o portfólio real do Atende Ai (22/10, análise sem alterações)

**Fontes oficiais** (developers.facebook.com, 2026):
- *Updates to WhatsApp Business accounts*:
  - Desde 23/09/2026, a WABA virou dois ativos: WhatsApp account (WAAC, dono do número) e Messaging account (templates e billing).
  - "Both hierarchies must belong to the same business portfolio. **A number can't be moved to another business portfolio.**"
  - Verificação "Under Business Portfolio".
- *Changelog*: "phone number migration isn't supported for accounts on the new WhatsApp account model… disconnecting the number from its current account doesn't make it available."
- *WhatsApp accounts and Messaging accounts*: "You cannot migrate a Messaging account from one business to another."
- *Onboard WhatsApp Business app users*:
  - A coexistência converte a conta do app e "both accounts remain associated with the client's Meta business portfolio".
  - Desconexão pelo app gera `PARTNER_REMOVED`.
  - Dispositivos vinculados são desvinculados ao onboardar.
  - Histórico (180 dias, sem grupos) sincroniza uma vez por onboarding.
- Fórum da Meta e o aviso do próprio painel: no Embedded Signup de coexistência, o portfólio que é dono do app aparece desabilitado ("This Meta Business Account owns the app").

**Business Manager (leitura):**
- Atende Ai (506485032393364): **verificado** desde 02/06/2026 (34.144.027 ARTHUR GABRIEL MARTINS LARANJO). Messaging accounts: "Test WhatsApp Business Account" (27281965408107469, própria) e "Atende Ai" (1299741078262298, "Isto pertence a Pizzaria Bella Massa").
- Portfólio dono do 3594 (1348385330573371): razão social "Pizzaria Bella Massa", endereço "Brasil", sem telefone, site um túnel `trycloudflare.com`, **não verificado**, "Qualificada para verificação".

**Conclusão:**
- Mover o 3594 para o portfólio 506485032393364 mantendo a coexistência **não é suportado**. O número não muda de portfólio, e desconectar não o libera.
- O cadastro tradicional pelo WhatsApp Manager exige apagar a conta do WhatsApp Business no celular, o que perde a coexistência.
- O Embedded Signup de coexistência não aceita o portfólio dono do app.
- O caminho oficial que preserva tudo é **tornar legítimo o próprio portfólio 1348385330573371**: corrigir os dados para os da empresa real (mesma pessoa jurídica do CNPJ 34.144.027) e verificá-lo com os documentos reais.
- A verificação é por portfólio, e os mesmos documentos podem ser usados se os dados coincidirem.
- Número, WAAC, Messaging account, Phone Number ID, coexistência, token e tenant 5 não mudam.
- Nada foi desconectado nem alterado. Nenhuma WABA foi criada. `auto_reply_mode=off`.

## Coexistência com o portfólio verificado do Atende Ai (22/10, investigação sem alterações)

**Restrições oficiais encontradas:**
- *Embedded Signup — Overview*: "Existing WhatsApp accounts that were originally created via the developer app cannot be selected or onboarded directly through the Embedded Signup flow."
  - Fórum da Meta e integradores (vários relatos de 2026): o portfólio dono do app aparece desabilitado ("This Meta Business Account owns the app"), por desenho, também em modo Live e com App Review aprovado.
- *Onboard WhatsApp Business app users*: coexistência só existe via Embedded Signup e exige ser Tech Provider ou Solution Partner. Não há caminho de coexistência para desenvolvedor direto no WhatsApp Manager ou no API Setup.
- *Business phone numbers*: "Numbers already in use with WhatsApp cannot be registered unless they are deleted first". O cadastro tradicional elimina o app no celular.
- *WhatsApp Business app login* (beta): também é um fluxo de parceiro. Exige que o número não esteja em nenhum Business Manager nem já em coexistência, o que exclui o 3594.
- *Updates to WhatsApp Business accounts*: "A number can't be moved to another business portfolio". O 3594 não pode ir para o Atende Ai.

**Conclusão:**
- Com o app atual (dono = portfólio Atende Ai), **não há procedimento oficial de coexistência para um número do próprio portfólio Atende Ai**.
- O 3594 não pode ser usado com o Atende Ai preservando a coexistência.

**Alternativa oficial com menos mudanças, sem nova verificação:** o número de teste do próprio Atende Ai (Graph, somente leitura, token do System User).
- Messaging account "Test WhatsApp Business Account" 27281965408107469: `ownership_type=SELF`, `account_review_status=APPROVED`, `business_verification_status=verified`.
- `health_status`: WABA, BUSINESS 506485032393364 e APP todos `AVAILABLE`, sem o 141010.
- Número +1 555-656-7513, PNID 1201264079728608, CONNECTED, LIVE, CLOUD_API, `is_on_biz_app=false`.
- App Atende Ai já assinado. Token do System User: sem expiração, `whatsapp_business_messaging` + `management`.
- Limitações: sem coexistência (não há WhatsApp Business no celular) e envio só para até 5 destinatários verificados no API Setup.

**Coexistência no portfólio Atende Ai, possível só com terceiro:**
- Um Tech Provider/BSP externo (app de outro portfólio) faria o Embedded Signup de coexistência escolhendo o portfólio Atende Ai, que não é dono desse app.
- O novo modelo prevê o mesmo WAAC compartilhado entre integração direta e parceiro ("Direct developer working with a partner").
- Exige contratar o serviço e usar outro número que não esteja em nenhum Business Manager.
- Não validado de ponta a ponta. Depende de autorização.

**Nada foi alterado:** nem número, WABA, app ou portfólio, nem MySQL. `auto_reply_mode=off`.

**Execução autorizada (opção "ambos"):**
- Vínculo aditivo do número de teste do Atende Ai ao tenant 5, pela API oficial (`backend-api/scripts/ia03_link_atendeai_test_number.py`).
  - Registro `whatsapp_accounts` id 4: account_key 27281965408107469, PNID 1201264079728608, `is_default=0`, token do System User Atende Ai cifrado. Auditoria 28 `whatsapp_account.create`.
  - Registro id 1 (3594) intacto.
  - O resolvedor interno do Gateway mapeia 1201264079728608 → `pizzaria_bella_massa`, com token.
- Pendente do proprietário: incluir o 5547 na lista de destinatários do número de teste (App Dashboard → Conectar no WhatsApp → Etapa 1. Experimente → campo "Para" → gerenciar lista). A Meta envia o código por WhatsApp para o 5547.
  - Sem isso, as respostas falham com #131030.
  - O painel não renderizou no navegador automatizado.
- Depois da inclusão: `auto_reply_mode=allowlist` (5547) e teste manual do 5547 para +1 555-656-7513.
- Coexistência via terceiro: a documentação do novo modelo descreve o caso "Direct developer working with a partner" (duas Messaging accounts no mesmo número). Não há texto oficial explícito para coexistência feita por parceiro e depois usada pela integração direta; precisa ser confirmado com o provedor antes de qualquer contratação.

## Testes pelo número de teste do Atende Ai (22/10)

**10:35 UTC:**
- Validações OK: roteamento 1201264079728608 → tenant 5, webhook, Qwen3 `ready` (modelo recarregado).
- `auto_reply_mode=allowlist` (5547), auditoria 29.

**10:36:32 UTC — mensagem recebida:**
- Nginx → Gateway (tenant `pizzaria_bella_massa`, conta 27281965408107469) → "mark as read" 200 → backend → Flow Engine `requires_ai_fallback`.
- AI Engine: `local_ai_unreachable` (`RemoteProtocolError`, depois `ConnectTimeout`).
- **Causa:** o servidor local foi desligado pelo botão físico ("Power key pressed short" às 07:37:03 BRT; o mesmo às 00:20:56). O Ubuntu executou `poweroff` limpo no meio da inferência. Ficou desligado até 19:40 BRT.
- Efeito correto (fail closed): sem resposta, sem reserva de billing, conversa marcada para humano.

**22:49 UTC — mensagem informada pelo proprietário:**
- **Nenhum webhook da Meta chegou** desde 22:00. Nginx registra outras requisições, então o endpoint está acessível (403 em 0,7 s).
- A assinatura do app está ativa (`messages`, `account_update`, `history`, `smb_*`) com callback `https://api.meuatendeai.com.br/webhook`.
- O número de teste está CONNECTED e o app assinado.
- A mensagem não saiu da Meta para nós. Possível pendência no envio pelo celular ou atraso da Meta.

**Recomendação:** no servidor local, `HandlePowerKey=ignore` em `/etc/systemd/logind.conf.d/`. Requer sudo do proprietário; não executado.

**Auditoria do número de teste (22:55 UTC, somente leitura):**
- Assinatura do app ativa: `whatsapp_business_account` com `messages`, callback `https://api.meuatendeai.com.br/webhook`.
- WABA 27281965408107469: app Atende Ai assinado, sem `override_callback_uri`. O outro app assinado, "WA DevX Webhook Events 1P App", é da própria Meta.
- Número 1201264079728608: `webhook_configuration.application` = mesmo callback, sem override de número.
- Roteamento: `whatsapp_accounts` id 4 → tenant 5.

**Recebimento comprovado por POST real:**
- 10:36:32 e **22:56:21 UTC**, `facebookexternalua`, Gateway `resolved_tenant=pizzaria_bella_massa` com PNID 1201264079728608.
- A mensagem das 22:49 chegou com cerca de 7 min de atraso da Meta.
- Não é preciso `hello_world` prévio: a mensagem iniciada pelo usuário abre a janela de 24 h e chega pelo webhook.

**Resultado das 22:56–22:57 UTC:**
- Número de teste: Qwen3 `deadline_exceeded` (504, 44,5 s). Foi a primeira inferência depois do boot das 19:40, com o modelo fora da memória. Sem resposta e sem billing.
- 3594 (mensagem enviada também para ele às 22:57:14): Qwen3 OK em 13 s, envio aceito, depois **#131031**; billing reserve → release.

**Correção (servidor local):**
- `ai-api` passou a aquecer o modelo em segundo plano no startup (`_warm_model`, reaproveita a sonda de readiness com o mesmo `num_ctx`/`keep_alive`, até 10 tentativas).
- 79 testes passando. Imagem anterior: `atende-ai-local/ai-api:pre-warmup-20261022`; backup `main.py.before-warmup`.
- Validado a frio: com o modelo descarregado, `warmup ok attempt=1` 5 s após o start, modelo residente por 24 h.

**Botão de energia:**
- Duas ocorrências "Power key pressed short" (00:20:56 e 07:37:03 BRT), cada uma seguida de `poweroff` limpo pelo logind. O dispositivo é o ACPI Power Button (LNXPWRBN), sem eventos espúrios repetidos.
- Script `atende-ai-local/scripts/disable_power_key.sh`, copiado para `~/disable_power_key.sh` no servidor. Grava um drop-in `HandlePowerKey=ignore`, recarrega o logind por SIGHUP sem encerrar sessões e valida pelo D-Bus.
- Requer sudo do proprietário. O sshd não é alterado.

## Primeira resposta do Qwen3 entregue no WhatsApp (22/10, 23:04 UTC)

**Número de teste do Atende Ai (+1 555-656-7513):**
- Webhook às 23:04:17 → tenant `pizzaria_bella_massa` (conta 27281965408107469).
- Allowlist aprovada; conversa com a IA (`assignment_mode=ai`).
- Flow `requires_ai_fallback` → Qwen3 local: RAG com 3 trechos, 1312/22 tokens. Fila de 35,7 s (atrás da mensagem do 3594) e geração de 3,4 s.
- Cloud API 200 às 23:04:57, `wamid.HBgMNTUzNDkyNjY1NTQ3FQIAERgSNDJDMEY3MTIxRjc4MTE3OEVCAA==`.
- **`sent` e `delivered` às 23:05:00**, cerca de 43 s após o webhook.
- Billing V2: reserva `fef665fa` **committed** (`delivered`, `legacy_unmetered`, custo 0).

**3594 (mesma mensagem, 23:04:11):**
- Qwen3 OK (40,5 s, primeira inferência com prompt completo após o restart), envio aceito e **#131031**.
- Reserva `98e6cccd` released.

**Consistência:**
- Ledger RESERVE 2 / COMMIT 1 / RELEASE 1.
- 1 inbound + 1 outbound por número, sem duplicidade.

**Pré-carregamento:**
- O carregamento do modelo saiu do caminho do cliente: nenhuma requisição pagou o carregamento.
- Restava o processamento a frio do prompt (cerca de 1300 tokens em CPU, cerca de 40 s), que se aproxima do prazo de 44,5 s.
- O warm-up agora também pré-computa o prefixo estável do prompt de cada tenant autorizado nas chaves de serviço (política + empresa + perfil).
- Validado a frio: `prefix prompt_tokens=576 total_ms=15717` logo após o start. 79 testes passando.

## 25. Pronto para mensagem real?
**Sim.** Todos os pré-requisitos essenciais foram validados:
- vínculo correto;
- allowlist ativa com um único número, aplicada no servidor;
- provider local só para a Bella;
- HMAC operacional e WireGuard ativo;
- Qwen3 respondendo com o conhecimento do fluxo;
- billing de homologação legítimo;
- fallback humano e kill switch;
- outras empresas inalteradas;
- nenhuma porta exposta.

Monitoramento: `scripts/ia03_bella_monitor.sh "<instante UTC>"` reúne os logs sanitizados do Gateway, do backend, do AI Engine e da API local, mais o estado do WireGuard, as mensagens, as reservas, o ledger e os status do tenant 5.
