# Atende Ai — Módulo Pedidos (MVP)

Data: 2026-10-28 (UTC). Deploy controlado em produção concluído; **Pedidos está desativado em todos os tenants** (padrão).
Nenhuma mensagem real foi enviada e nenhum pedido foi criado em produção.

## Funcionalidades concluídas

| Regra | Implementação |
| --- | --- |
| 1. Aba Pedidos no painel | `admin-panel/lib/screens/orders_screen.dart`: lista com filtros (em andamento, todos, por status), detalhe com itens, valores, cliente, entrega/retirada, endereço e histórico; atualização automática a cada 30 s. |
| 2. Ativar/desativar por tenant | `tenant_settings.orders_enabled` (padrão 0). Chave no painel para o admin da empresa e o superadmin, com auditoria `tenant.orders.update`. |
| 3. Catálogo | Categorias e produtos com preço fixo ou opções (tamanhos e sabores, cada uma com preço próprio) e disponibilidade (`/api/v1/catalog/*`), com auditoria. |
| 4. Flow Engine e AI Engine | Hook `start_order` no estado `iniciar_pedido` da Bella (sem mudança no Flow Engine). O catálogo vai para a IA local como documento `catalogo-pedidos` quando Pedidos está ativo. |
| 5. Intenção de compra e confirmação | `order_assistant.py`: detecta a intenção ("quero 2 calabresas grandes e uma coca lata"), extrai itens, quantidades e opções do catálogo, pergunta o que falta (opção, entrega ou retirada, endereço, nome), mostra o resumo com o total e só registra depois de um **SIM** explícito. |
| 6. Ações estruturadas | Criação via `OrderService.create`: preços recalculados pelo catálogo, numeração por tenant e idempotência `draft:{id}`. A IA nunca escreve no MySQL. |
| 7. Visão da loja | Detalhe completo e histórico de status com autor e resultado da notificação. |
| 8. Status em português | Novo → Confirmado → Em preparo → Saiu para entrega / Pronto para retirada → Entregue / Retirado; Cancelado em qualquer etapa aberta. As transições são validadas e respeitam entrega ou retirada. |
| 9. Notificação a cada mudança de status | Dentro da janela de 24h: texto pelo Gateway com reserva e confirmação no Billing V2. Fora dela: só o modelo aprovado `atende_pedido_status`; sem ele, o envio é pulado e registrado como `skipped_outside_window`. |
| 10. RBAC, isolamento, idempotência, auditoria | Atendente vê pedidos e muda status; só o admin mexe no catálogo e na chave. Todas as consultas filtram por tenant. A mudança de status usa compare-and-set (409 em conflito). Todas as mudanças são auditadas. |
| 11. Publicar fluxo atualiza a IA | **Não existia; implementado.** Salvar ou restaurar um fluxo com a seção `knowledge` sincroniza a IA local em segundo plano (só envia o que mudou) e audita `knowledge.sync`. |

## Testes

- Backend: 136 passaram (todo o conjunto), incluindo 25 novos do módulo e 1 de inicialização da aplicação. Com um MySQL descartável, 173 passaram, incluindo 5 novos de MySQL: idempotência, numeração, máquina de status, isolamento entre tenants e conflito concorrente.
- Flow Engine: 41 passaram, incluindo o hook da Bella e o carregamento da seção `knowledge`.
- Flutter: `analyze` sem problemas nos arquivos novos; build web de release com a URL de produção.
- Dry-run em produção (`ai-phase2-evidencias/orders-dry-run.txt`): 2 conversas completas com o catálogo real da Bella, totais corretos e 0 pedidos gravados. A sincronização do fluxo da Bella daria 8/8 documentos inalterados (sem reindexação).

## Deploy

- Backups em `/var/backups/atende-ai-ia02/pre-orders-20261028T010144Z/`: dump completo do banco (38 tabelas, validado), checkpoint do código e imagens marcadas `:pre-orders-20261028T010144Z`.
- Atualizados: backend-api, flow-engine e o build do painel. O schema foi criado pelo bootstrap; a migração 013 é o espelho dele.
- Catálogo da Bella: 21 produtos em 4 categorias, copiados dos preços do fluxo sem alterá-los. A única mudança foi corrigir o nome "Camaão" para "Camarão" no catálogo.
- **Incidente:** a primeira subida do backend falhou ao iniciar (dependência de rota baseada em classe). Ficou cerca de 3 min fora até o rollback para a imagem marcada. Corrigi e adicionei um teste de inicialização; o redeploy passou na verificação de import antes de subir.

## Pendências reais

1. **Ativar para a Bella**: ligar a chave Pedidos no painel. As respostas automáticas continuam limitadas à allowlist (número de teste).
2. **Modelo fora da janela de 24h**: criar e aprovar na Meta o modelo UTILITY `atende_pedido_status` (2 variáveis: número e status). Além disso, o envio de modelos hoje só é permitido para o número de teste.
3. **Clientes Gemini**: não recebem o catálogo como contexto; a sincronização só existe para a IA local.
4. **Fora do MVP**: pizza meio a meio, taxa de entrega, forma de pagamento. Perguntas no meio do pedido não vão para a IA; o assistente repete a pergunta e "CANCELAR" encerra o pedido.
5. **Painel**: falta conferência visual com login de loja (precisa de credenciais do usuário).
