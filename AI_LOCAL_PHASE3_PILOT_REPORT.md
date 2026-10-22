# IA-03 — piloto WhatsApp brasileiro com Qwen3 local

Atualizado em 2026-10-14.

## Status

**Preparação; piloto não ativado.** O proprietário autorizou usar no primeiro piloto controlado o WhatsApp Business brasileiro terminado em 3594 e proibiu o número Meta Test americano. Login manual confirmou WABA e número. Em 14/10, com autorização explícita, foi atribuído ao usuário de sistema existente `AtendaAi_WhatsApp` acesso parcial ao WABA brasileiro: `Mensagens` e `Números de telefone (apenas visualização)`. Acesso total, gerenciamento de números e modelos não foram concedidos. Ainda não há token Cloud API, vínculo de tenant/conta no runtime, provider local ativado nem mensagem enviada. A Meta continua exibindo `Restricted` e negócio não verificado; o proprietário relata que coexistência já foi testada e funcionou, portanto esse aviso fica registrado como limitação da plataforma, não como autorização para iniciar verificação.

O proprietário informou que já testou a coexistência com esse número e confirmou que deseja usá-lo apesar do status restrito exibido pela Meta. Também autorizou como remetente de teste um celular terminado em 5547; o número completo não é registrado neste relatório nem nos arquivos versionados.

## Auditoria de runtime

- **AWS:** MySQL, Backend API, AI Engine, Flow Engine e WhatsApp Gateway estavam `running/healthy` na última verificação disponível. `LOCAL_AI_ENABLED=false`; AI Engine não tem chave HMAC operacional após a revogação das chaves IA-02.
- **Ubuntu local:** API, Qdrant e Ollama estavam `running/healthy`; `/ready` retornou pronto com Qwen3 4B. A checagem privada AWS → `http://10.77.0.2:8100/health` retornou `{"status":"ok"}`. Handshake recente do WireGuard não foi confirmado nesta execução: consulta `wg show` sem privilégios foi negada. Nenhum comando privilegiado foi executado.
- **WhatsApp Gateway:** `DEFAULT_TENANT_ID=default`; `META_PHONE_NUMBER_ID` ausente/placeholder; `META_ACCESS_TOKEN` ausente; app secret configurado. O endpoint esperado é `/webhook`, com validação de `X-Hub-Signature-256`; o código procura a conta pelo `metadata.phone_number_id`. O Gateway não tem ligação atual confirmada com o número autorizado.
- **Contas no MySQL:** `whatsapp_accounts` não contém registros. Não há associação atual de tenant, WABA, Phone Number ID, display number ou status de conexão nessa tabela.
- **Tenants/settings atuais:** `default`, `smoke-bv2-20261002032044`, `smoke-bv2-20261002033025` e `teste_empresa`; todos permanecem com provider Gemini e IA local desligada. `pizzaria_bella_massa` não existe no catálogo atual do MySQL. Não há fluxo de homologação registrado na tabela `flows` (vazia). O YAML `tenants/pizzaria_bella_massa/atendimento_pizzaria_delivery.yaml` existe no container Flow Engine, mas não comprova vínculo do tenant no runtime nem que seja um fluxo de homologação.
- **Mensagens persistidas:** há um inbound `source=gateway` com ID externo, em `2026-09-25`, tenant `default`, Phone Number ID `1155710810954749`. Isso é evidência de um evento externo recebido, mas não confirma conta/status Meta atual nem vínculo correto. Não há outbound com ID Meta correspondente; a mensagem de saída registrada não prova envio ou entrega. As mensagens dos tenants `smoke-bv2-*` são fixtures e não foram contadas como tráfego real.
- **Histórico documental:** [checklist Meta](docs/novo-app-meta-checklist.md) registra o número brasileiro `+55 34 3195-3594`, WABA `1299741078262298`, Phone Number ID `1155710810954749` e tenant histórico `pizzaria_bella_massa`. São dados históricos, não confirmação na Meta/runtime atual. O número americano de teste não será usado.
- **Meta — app:** no portfólio empresarial **Atende Ai** (Business ID `506485032393364`), o app **Atende Ai** (App ID `873826165763092`) está ativo, publicado e contém o caso de uso “Conectar no WhatsApp”. A página de configuração de produção do caso de uso ficou carregando sem exibir os detalhes; o URL público do webhook, permissões e assinatura da WABA ao app não puderam ser confirmados nessa tela.
- **Meta — ativos WhatsApp:** o Business Manager mostra duas contas. O ativo `Test WhatsApp Business Account`, WABA `27281965408107469`, pertence ao portfólio Atende Ai e é a conta Meta Test americana, explicitamente excluída pelo proprietário. A outra conta, chamada **Atenda Ai**, WABA `1299741078262298`, é propriedade de **Pizzaria Bella Massa** e está identificada como “Aplicativo WhatsApp Business”. Na aba de números, há um número `+55 34 3195-3594`, display name **Atenda Ai**, Phone Number ID `1155710810954749`, status **Conectado**. Isso confirma a associação atual na Meta e confirma os IDs históricos. O rótulo “Aplicativo WhatsApp Business” indica a associação com o app Business, mas o estado explícito de coexistência não foi exibido/confirmado.
- **Meta — usuário de sistema:** existe `AtendaAi_WhatsApp` (System User ID `61590550748033`, papel Admin), com o app Atende Ai e o ativo Meta Test americano previamente atribuídos. Após confirmação explícita do proprietário, o WABA brasileiro `1299741078262298` foi atribuído com acesso parcial, permissões `Números de telefone (apenas visualização)` e `Mensagens`. A tela confirmou que o usuário foi adicionado; a lista de ativos confirma exatamente essas permissões. Acesso total, gerenciamento de números de telefone e gerenciamento de modelos continuam desmarcados. Nenhum token foi gerado ou exibido.
- **Restrição Meta:** o painel do WABA Bella Massa informa `Restricted` e “Antes de começar a enviar mensagens, você precisará verificar sua empresa”; a seção mostra a empresa como **Não verificado**. Portanto, apesar do número aparecer Conectado, a conta não está liberada para iniciar o teste de envio. Não iniciei a verificação, pois isso exige ação do proprietário na Meta.
- **Atividade Meta:** Insights do número no período de 16/09/2026 a 13/10/2026 mostram **1 mensagem recebida, 0 enviadas, 0 entregues e $0,00** de cobrança aproximada. A Meta não expõe nessa visão o remetente nem a ligação com tenant; isso é consistente com o único inbound persistido no banco, mas não prova que aquele evento veio desse número. Status de qualidade não apresentou valor.

| Evidência | Tenant | WABA ID | Phone Number ID | Business phone | Estado verificado |
|---|---|---:|---:|---|---|
| Meta Business Manager (lido após login) | `pizzaria_bella_massa` (ausente no MySQL atual) | `1299741078262298` | `1155710810954749` | `+55 34 ****-3594` | Proprietário do WABA: Pizzaria Bella Massa; display name `Atenda Ai`; telefone `Conectado`; WABA `Restricted`, negócio não verificado; proprietário confirma coexistência testada |
| Meta WhatsApp Manager — insights 16/09 a 13/10/2026 | Mesmo WABA/phone acima | `1299741078262298` | `1155710810954749` | `+55 34 ****-3594` | 1 recebida; 0 enviada/entregue; custo aproximado $0.00 |
| Conta no MySQL atual | — | — | — | — | Nenhuma conta cadastrada |
| Evento inbound persistido | `default` | não mapeado | `1155710810954749` | `+55 34 ****-3594` (correspondência histórica) | 1 evento com ID externo; não confirma entrega/estado atual |
| Meta Test americana | — | `27281965408107469` | — | — | WABA aparece no mesmo portfólio como `Test WhatsApp Business Account`; Phone Number ID/número americano são apenas dados históricos do checklist e não foram reabertos na Meta; explicitamente excluída pelo proprietário; não usar |

## Segurança e isolamento do piloto

- O código da seleção local exige metadados do tenant (`ai_provider=local`), `LOCAL_AI_ENABLED` e cliente local configurado; não há fallback silencioso para Gemini quando o provider local falha. As configurações atuais continuam Gemini/desligadas.
- O endpoint administrativo para selecionar provider é protegido por Superadmin e registra auditoria. Nenhuma chave HMAC operacional foi gerada. As antigas chaves IA-02 foram revogadas; não serão reutilizadas.
- **Antes desta continuação, não havia allowlist inbound por remetente/tenant.** `META_TEST_RECIPIENT` é usado pela rota de envio de template de teste; não é controle de remetentes de webhook e não deve ser tratado como allowlist.
- **Alteração local nesta continuação:** foi implementada no Gateway uma allowlist JSON por tenant, vazia por padrão, e o AI Engine suprime o provider `local` em mensagens WhatsApp sem autorização explícita do remetente. Para remetentes não autorizados, o provider global anterior permanece. O Gateway também pode rejeitar eventos do Phone Number ID piloto se ele não resolver exatamente para o tenant configurado, evitando cair em `default`. A mudança ainda não foi implantada na AWS.
- O webhook agenda processamento por `BackgroundTasks` após receber evento; a resolução de conta pode cair no tenant global/default quando não há correspondência. Não encontrei agrupamento/debounce para mensagens próximas. Esses comportamentos exigem uma proteção explícita de tenant/remetente antes de permitir automação Qwen3 no número Business.
- Código de Flow Engine determinístico, detecção de atendimento humano, fallback/handoff e Billing V2 existe, mas não foi validado em tráfego real nesta fase. Não afirmar `DELIVERED` sem status correspondente da Meta.

## Pendências antes do primeiro WhatsApp real

1. Configurar/deploy da allowlist tenant-scoped usando somente o remetente autorizado (terminado em 5547) e mapear o Phone Number ID para o tenant piloto; validar que nenhum outro tenant recebe roteamento local.
2. Confirmar como restaurar/vincular o WABA conectado ao tenant do runtime. Meta confirma `pizzaria_bella_massa`, mas esse tenant e qualquer conta WhatsApp não existem no banco de produção atual; o usuário autorizou o número `piloto_3594` se o tenant histórico estiver ausente. Ainda é preciso validar duplicidade e executar a criação/vinculação no caminho administrativo correto.
3. O WABA brasileiro já foi atribuído a `AtendaAi_WhatsApp` com permissões parciais mínimas. Ainda falta emitir token Meta de produção com os escopos estritamente necessários e armazená-lo no ambiente AWS sem imprimir ou registrar em Git; token ainda não existe no runtime.
4. O proprietário relata coexistência funcional; preservar a configuração atual do Business App e usar essa confirmação para o teste quando o runtime estiver pronto. O painel Meta ainda indica restrição e negócio não verificado; não iniciar verificação empresarial. Se uma chamada Cloud API retornar bloqueio, registrar a resposta e interromper o teste de envio.
5. Ler webhook, assinatura da WABA ao app e permissões em tela apropriada; a página de configuração do app não carregou os detalhes.
6. Gerar nova chave HMAC operacional restrita ao tenant, ativar o gate global apenas se necessário e comprovar que todos os demais tenants continuam em Gemini. Validar kill switch e chamada privada autenticada AWS → WireGuard → Qwen3.
7. Validar fluxo determinístico, fallback humano, Billing V2 (`RESERVE/COMMIT/RELEASE`), idempotência, duplicidade e status Meta antes do envio voluntário. Não executar campanhas.

## Testes e resultados

- Saúde local e endpoint privado VPN: **passaram** na última verificação informada.
- Handshake WireGuard recente: **pendente de verificação com privilégio**.
- Meta Business Manager/WhatsApp Manager: **WABA, número, proprietário e status Conectado verificados**; WABA restrito/não verificado. Proprietário confirma teste anterior de coexistência. Atribuição do WABA brasileiro ao usuário de sistema confirmada com `Mensagens` e leitura de números apenas; webhook, assinatura e permissões do app ainda não verificados. Graph/Cloud API não testada; token ausente.
- Inferência privada autenticada pós-revogação: **não executada**, sem chave operacional.
- Allowlist local: **passou validação unitária local** para número autorizado normalizado, negação de outro tenant, remetente diferente e JSON malformado. Mudança não implantada; fallback/BillingGate e kill switch operacional não validados.
- WhatsApp inbound/outbound, entrega e teste de respostas “Boa noite”, preço e Wi-Fi: **não executados**.
- Benchmark 4B versus 1.7B: **não executado**.

## Próxima ação

Concluir a configuração da Cloud API (permissões do app, assinatura do webhook e armazenamento seguro do token), resolver/vincular `piloto_3594` conforme autorizado, implantar e validar a proteção de remetente/tenant e provisionar HMAC operacional isolado. O usuário de sistema recebeu acesso parcial ao WABA brasileiro com escopo de mensagens e leitura de números. O proprietário confirmou coexistência pelo Business App e autorizou o remetente de teste; a mensagem voluntária só deve ocorrer depois de validar o mapeamento e o provider local. O status de restrição permanece documentado; não iniciar verificação empresarial sem pedido.
