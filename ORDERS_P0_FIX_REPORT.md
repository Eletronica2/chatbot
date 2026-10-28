# P0 — Confirmação indevida de pedido (Bella Massa, 27/10/2026)

## 1. Causa exata (MySQL, logs e transições; horários em UTC = BRT + 3)

| Hora | Cliente | Transição / origem | Causa |
| --- | --- | --- | --- |
| 01:40:20 | "Tradicionais" | nenhuma transição → fallback de IA → **IA local com timeout (504) após 46 s** → sem resposta, conversa enviada para atendente | `contains:tradicional` não casava com "tradicionais": desde uma fase anterior, o Flow Engine compara **palavras inteiras**, sem plural. O mesmo valia para "especiais" e "doces". |
| 01:41:16 | "Quero ver as tradicionais" | `cardapio_principal` → `contains:quero` → `iniciar_pedido` | Pelo mesmo motivo, a única palavra que casou foi o gatilho genérico "quero". |
| 01:41:45 → 01:43:13 | Arthur, Grande, Calabresa, Só a pizza, Vou retirar, Vou retirar no local | `pedido_*` (coleta legada) | O fluxo legado de pedidos rodava sem consultar o módulo Pedidos. O Flow Engine não sabia se o módulo estava ativo. |
| 01:43:22 | "Cartão" | `pedido_pagamento` → `contains:cartao` → `pedido_confirmacao` | "Pedido recebido com sucesso" é um **texto fixo do fluxo legado**, sem gravação nem confirmação. |

- **Mensagem "atrasada":** não houve atraso. A confirmação foi a resposta imediata (mesmo segundo) à mensagem "Cartão". Entre 22:41 e 22:43 o celular enviou 7 respostas, todas registradas com wamid. Não existem timers nem filas: o Gateway só envia a resposta síncrona do backend, com limite de 30 s.
- **Pedidos durante o teste:** estava **desativado**. Foi ativado às 01:43:55 (auditoria #30), 33 s depois da mensagem de "sucesso".

## 2. Pedido gravado indevidamente?

**Não.** A tabela `orders` está vazia; nenhum pedido foi criado. Históricos preservados: nada foi apagado.

## 3. Correções

- **Flow Engine:**
  - etapas exigem módulo (`requires_module`), e o backend informa os módulos ativos (`enabled_modules`);
  - sem Pedidos, as etapas de pedido não são alcançáveis por transição, intenção, transição global ou fallback, e a opção "Fazer pedido" e o convite "fazer pedido" saem dos menus;
  - as etapas legadas `pedido_*` e `consultar_*` **nunca** executam, com Pedidos ativo ou não (ficam no arquivo só como fonte de conhecimento da IA);
  - sessões presas numa etapa legada reiniciam pela etapa inicial;
  - comparação de palavras tolera plural ("tradicional" ~ "tradicionais");
  - categorias acessíveis de qualquer etapa;
  - removidos os 8 gatilhos genéricos `contains:quero` → pedido.
- **Backend (defesa em profundidade):**
  - `OrderService.create` recusa a criação se `orders_enabled=false`;
  - o gatilho `start_order` só vai para o assistente com Pedidos ativo; caso contrário, ou se o assistente falhar, segue uma resposta segura e **nunca** a etapa legada;
  - ações legadas (`confirmar_pedido`, etc.) e qualquer texto de fluxo ou da IA que afirme "pedido recebido/confirmado" são bloqueados;
  - "Quanto custa X?" é respondido com o preço do catálogo cadastrado, sem depender da IA.
- **Assistente de pedidos:**
  - "SIM" só confirma o **resumo atual**: valida assinatura dos itens e valores, idade do resumo (até 15 min) e se a mensagem é posterior ao resumo; caso contrário, reapresenta o resumo;
  - respostas ambíguas ("pode", "isso", "sim, mas…") não confirmam;
  - webhook repetido e evento antigo são ignorados;
  - turnos da mesma conversa são processados em sequência, com leitura do rascunho atualizada (número normalizado);
  - falha ao gravar nunca gera mensagem de sucesso;
  - navegar ("quero ver…") ou perguntar preço não inicia pedido.
- **Painel:** o editor visual de fluxos agora preserva `requires_module`, `lines_without_module` e `knowledge` ao salvar.

## 4. Testes aprovados

- Flow Engine: 76 testes, incluindo cenários A e B, Pedidos ligado/desligado, e varredura de todos os estados × mensagens do fluxo legado (nenhuma etapa legada alcançável).
- Backend: 165 testes; com MySQL descartável, 206. Inclui C, D, E, F (1 pedido no MySQL), G (repetição, simultaneidade), H (falha), confirmação ambígua e evento antigo.
- Ponta a ponta antes do deploy (stack local) e em produção, com o Flow Engine implantado e o catálogo real, sem gravar pedidos nem enviar mensagens: **A–H aprovados com Pedidos ativado e desativado**, incluindo a reprodução da conversa de 27/10 (`ai-phase2-evidencias/p0-orders-dry-run-production.txt`).

## 5. Deploy

- Contenção: Bella com `auto_reply_mode=off` via API auditada durante toda a correção.
- Backup: `/var/backups/atende-ai-ia02/pre-p0-orders-20261028T023944Z/` (banco com 43 tabelas, código) e imagens `:pre-p0-20261028T023944Z`.
- Imports validados antes de subir. Flow Engine e backend saudáveis, **sem indisponibilidade** e sem erros nos logs. Painel atualizado.
- Conhecimento da IA inalterado (8/8). Nenhum outro tenant alterado. WABA 3594 não tocada. Nenhuma mensagem real enviada. Sem push.
- Após os testes: allowlist da Bella restaurada só com o celular 5547 (auditada). **Pedidos continua ATIVADO para a Bella** (ativação feita às 22:43:55 BRT); pode ser desligado no painel.

## 6. Como repetir o teste manual (celular 5547)

1. **Navegação:** "Boa noite" → "Cardápio" → "Tradicionais" → "Quero ver as especiais" → "Bebidas" → "Quanto custa a calabresa?". Esperado: listas e preços, nenhum pedido iniciado.
2. **Pedido (Pedidos ativado):** "Quero duas pizzas grandes de calabresa" → "não" → "retirada" → seu nome. Esperado: resumo com total R$ 125,80 e o pedido de **SIM**. Fique 3 minutos sem responder: nada acontece. Responda "sim": "Pedido #1 registrado!" aparece na aba Pedidos do painel.
3. **Pedidos desativado:** desligue no painel e repita os passos 1 e 2. Esperado: menus sem "Fazer pedido", e nenhuma coleta nem confirmação.
4. Esse pedido de teste fica gravado. Pode cancelá-lo na aba Pedidos (o cancelamento avisa o cliente se a janela de 24h estiver aberta).
