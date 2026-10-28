# P0 — Saudação com pedido inventado (Bella Massa, 27/10/2026 23:46 BRT)

## Causa exata

- **Origem:** **Qwen3**, mensagem 51 (02:46:39 UTC), `source=ai_fallback`, estado `boas_vindas`. Não houve template fixo nem transição de pedido.
- **Pedidos:** **desativado** naquele momento (desligado 02:45:49, religado 02:49:25; auditorias #34 e #36).
- **O que o backend enviou ao Qwen3 junto com "Boa noite":**
  1. **`collected_data` do fluxo legado** de 22:41–22:43, que nunca expirava: `payment_method=cartao`, `address=vou retirar no local`, `delivery_type=vou retirar`… O Flow Engine reiniciava o estado legado, mas devolvia esses dados, e o AI Engine os colocava no prompt como "dados coletados".
  2. **Histórico sem noção de novo atendimento:** os 10 últimos turnos, incluindo o "🎉 Pedido recebido com sucesso!" falso do fluxo legado, uma hora antes.
- O modelo juntou essas peças ("cartão", "entrega") com o "até 5km" do documento de promoções.
- **Nenhum pedido existia.** O servidor da IA local não guarda conteúdo de conversa: tudo veio do backend.
- Agravante encontrado durante a correção: `_ensure_operational_defaults` regrava a sessão a cada mensagem, atualizando `last_interaction`. Por isso, a data dos turnos é usada como referência do último contato real.

## Correção (na origem)

- **Flow Engine:** só sobrevivem dados coletados por etapas habilitadas. Dados do fluxo legado ou de módulos desligados são descartados e **sobrescritos** no estado salvo. `iniciar_pedido` não coleta mais o nome (o assistente pede).
- **Backend:**
  - **Novo atendimento:** após 30 min sem turnos, a etapa do fluxo, os dados coletados e o rascunho de pedido recomeçam. O histórico continua salvo, e "Boa noite" recebe a saudação oficial do fluxo, sem passar pela IA.
  - **A IA só vê o atendimento atual**, e nunca os turnos do módulo Pedidos. Turnos são marcados por origem; a resposta manual do painel preserva a marcação.
  - Fatos de pedido vêm só do backend: a consulta de status lê o pedido real do tenant e do cliente.
  - O detector de afirmações sobre pedido ("já temos seu pedido", "será entregue", "pagamento confirmado") foi ampliado e fica como **última barreira**, não como a correção.
- **Reset seguro:** novo `POST /api/v1/conversations/{id}/reset-state`, só para admin da empresa ou superadmin, com auditoria. Limpa só o estado transitório e preserva mensagens e histórico.
- **Fluxo:** "Camaão" corrigido para "Camarão" (cardápio e especiais), com os preços mantidos. A IA local foi sincronizada: só `bella-flow-pizzas-especiais` mudou (v2); os outros 7 documentos ficaram inalterados.

## Testes

- Backend: 173 aprovados (8 novos deste caso). Flow Engine: 85 aprovados (dados legados nunca retornam; "Camarão").
- Dry-run ponta a ponta, **local antes do deploy** (42 verificações) e **em produção depois** (43 verificações). Rodou com Flow Engine e catálogo reais, IA simulada nos cenários, sem envio e sem gravar pedido. Tudo aprovado, com Pedidos ativado e desativado:
  - saudação após conversa antiga com pedido legado: saudação oficial, IA sem histórico ou dados antigos, histórico preservado;
  - mensagens consecutivas sem contaminação;
  - novo atendimento após pedido concluído e após pedido cancelado;
  - cardápio e categorias;
  - todos os cenários A–H anteriores.
- **Qwen3 real, em dry-run antes e depois do deploy:**
  - com o payload corrigido, a resposta foi "Boa noite! Como posso ajudar você hoje?";
  - com o payload de 23:46, foi "Obrigado por escolher a Pizzaria Bella Massa": não inventou pedido desta vez (a saída varia), mas ecoou o texto legado de confirmação.
- Evidências: `ai-phase2-evidencias/p0b-qwen3-dry-run.txt` e `p0b-greeting-dry-run-production.txt`.

## Deploy e estado

- Backup em `/var/backups/atende-ai-ia02/pre-p0b-greeting-20261028T232353Z/`; imagens `:pre-p0-20261028T232353Z`.
- Imports validados antes de subir. Serviços saudáveis, sem erros nos logs e sem indisponibilidade.
- **Reset feito só na sua conversa de teste** (sessão 12, auditoria #43): 7 dados legados removidos, histórico preservado.
- Allowlist da Bella mantida (apenas 5547). Pedidos continua ativado. Pedido #1 (seu teste) está como Entregue.
- Nenhum outro tenant alterado. WABA 3594 intocada. Nenhuma mensagem enviada. Sem push.
