# Atende Ai — Modelo comercial Billing V2

Documento em linguagem simples para vendas, suporte e financeiro. Sem dados sensíveis.

## O que é cobrado

A unidade de cobrança é a **mensagem enviada pela Atende Ai e entregue no WhatsApp do cliente final**.

- Mensagem **recebida** (o cliente final escreve para a empresa): **não consome** nada.
- Mensagem enviada que **falhou**: **não consome** (o crédito volta).
- Mensagem **lida** depois de entregue, ou status repetido da Meta: não cobra de novo.
- Cada mensagem entregue consome **1 unidade**, uma única vez.

Como funciona por dentro: antes de enviar, o sistema **reserva** 1 unidade. Quando a Meta confirma a entrega, a reserva vira **consumo**. Se a Meta informar falha, a reserva é **devolvida**.

## Planos (catálogo 2026-10)

| Plano | Mensalidade | Mensagens operacionais entregues por mês |
|---|---|---|
| Inicial | R$ 197 | 1.000 |
| Essencial | R$ 297 | 3.000 |
| Crescimento | R$ 497 | 6.000 |
| Profissional | R$ 897 | 12.000 |
| Empresarial | sob consulta | definida em proposta |

"Mensagens operacionais" são as de atendimento: respostas da IA, respostas manuais, notificações e templates utilitários e de autenticação.

Nunca use os termos "mensagens ilimitadas" nem "Meta inclusa".

## Franquia

- A franquia do plano vale para o **ciclo da assinatura** e **expira no fim do ciclo**. Não há acúmulo.
- Níveis de uso exibidos no painel: normal, atenção (80%), alerta (90%) e esgotado (100%).
- Ao chegar a 100%, os **envios** (respostas automáticas e respostas manuais) ficam pausados até a compra de uma recarga ou a renovação do ciclo. O **recebimento** de mensagens continua normalmente, e a conversa é sinalizada para atendimento humano.

## Recargas operacionais

| Pacote | Preço |
|---|---|
| +500 mensagens | R$ 49,90 |
| +1.000 mensagens | R$ 89,90 |

- As recargas **não expiram**.
- O sistema usa primeiro a franquia do plano, que expira antes, e depois as recargas.
- O saldo só é liberado após a confirmação do pagamento.

## Campanhas (marketing)

Mensagens de marketing (promoções, campanhas) são tratadas à parte da franquia operacional, e a regra depende do modo de cobrança da empresa.

## Modos de cobrança da Meta

A Meta cobra pelas conversas de WhatsApp Business. Existem dois modos de lidar com esse custo:

### 1. Cliente paga a Meta (customer_direct) — padrão

- A empresa cliente cadastra o próprio meio de pagamento na Meta, e a **Meta cobra diretamente o cliente**.
- A Atende Ai cobra apenas a mensalidade, a franquia e as recargas operacionais.
- Campanhas **não usam créditos da Atende Ai**: a Meta cobra o cliente. Mostramos uma **estimativa** do custo Meta apenas como referência.
- Texto padrão: "Tarifas da Meta são cobradas diretamente pela Meta."

### 2. Atende Ai paga a Meta (solution_partner_credit_line)

- A Atende Ai paga a Meta pela linha de crédito de Solution Partner e repassa esse custo no preço.
- Campanhas são **pré-pagas**: **R$ 0,55 por mensagem de marketing entregue**, comprada como créditos de campanha.
- Sem saldo de créditos de campanha, a campanha não é enviada.
- Os créditos de campanha não expiram.

O modo padrão é global ("Cliente paga a Meta"). O superadmin pode definir outro modo por empresa; a mudança é auditada e exige motivo. Mensagens já registradas mantêm o modo da época em que foram enviadas.

## Sugestão de plano na proposta

O plano sugerido segue a **quantidade de mensagens de atendimento** informada pelo cliente:

| Volume operacional informado | Sugestão |
|---|---|
| até 1.000 | Inicial (R$ 197) |
| até 3.000 | Essencial (R$ 297) |
| até 6.000 | Crescimento (R$ 497) |
| até 12.000 | Profissional (R$ 897) |
| acima de 12.000 | Empresarial (sob consulta) |

O volume de campanhas **não aumenta o plano base**. Ele gera uma estimativa separada. Exemplo no modo Atende Ai: 100 campanhas por mês × R$ 0,55 = R$ 55.

## Proteção de margem (Margin Guard)

Toda proposta, conversão de lead e atribuição de plano passa por uma checagem de margem de contribuição:

**margem = (preço − custos variáveis) ÷ preço**

| Resultado | Regra |
|---|---|
| Vermelho (margem negativa, prejuízo) | **bloqueado**, mesmo com justificativa |
| Amarelo (0% a 30%) | permitido somente com **justificativa do superadmin** (auditada) |
| Verde (30% ou mais) | apenas quando **todos os custos** estiverem configurados |
| Estimativa parcial | algum custo ainda é desconhecido (IA, taxa de pagamento, impostos); desconto exige justificativa |

O painel mostra o **preço mínimo seguro** para a franquia escolhida.

## Clientes e propostas existentes

- Clientes atuais continuam no plano legado. **Não há migração automática**: a troca para um plano V2 é manual, explícita e auditada.
- Propostas antigas são preservadas e identificadas como legado.
- Nenhuma mensagem antiga é cobrada retroativamente.
