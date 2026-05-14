# Estrutura de Automações — Referência para Geração por IA

> **Propósito deste documento:** Descrever com precisão técnica e funcional cada campo, regra e conceito da estrutura de automações do sistema de chatbot WhatsApp. Uma IA generativa deve usar este documento para produzir a descrição completa de uma automação pronta para ser implementada no painel administrativo.

---

## 1. Visão geral

Uma **automação** é um fluxo de conversa via WhatsApp composto por uma sequência de **etapas**. Cada etapa representa um momento da conversa: o bot envia uma mensagem e aguarda a resposta do cliente. A resposta determina qual etapa o fluxo segue em seguida.

O sistema converte a automação para YAML internamente e a executa por meio de um flow-engine. A IA não precisa gerar YAML — ela deve gerar a **descrição estruturada** no formato especificado na Seção 7 para que o desenvolvedor importe no painel.

---

## 2. Campos da Automação (nível raiz)

| Campo | Obrigatório | Tipo | Regras |
|---|---|---|---|
| `nome` | ✅ | string | Identificador único da automação. Use snake_case sem acentos (ex: `atendimento_loja`). Não pode haver duas automações com o mesmo nome no mesmo tenant. |
| `descricao` | ❌ | string | Texto livre para documentar o propósito do fluxo. Não afeta o comportamento. |
| `etapa_inicial` | ✅ | string | Nome exato de uma das etapas listadas. É a etapa que o cliente encontra ao iniciar a conversa. Geralmente se chama `"Mensagem inicial"`. |

---

## 3. Etapas (`states`)

Uma automação contém **de 1 a N etapas**. Cada etapa tem os seguintes campos:

### 3.1 Campos da Etapa

| Campo | Obrigatório | Tipo | Descrição |
|---|---|---|---|
| `nome` | ✅ | string | Nome interno da etapa. Deve ser único dentro da automação. Usado para referenciar a etapa como destino de botões e regras. Use linguagem natural (ex: `"Horário de funcionamento"`). |
| `mensagem` | ✅ | string | Texto que o bot envia ao cliente quando entra nesta etapa. Pode conter emojis, quebras de linha e formatação WhatsApp (`*negrito*`, `_itálico_`). Limite recomendado: 1024 caracteres. |
| `botoes` | ❌ | lista de opções | Lista de botões de resposta rápida exibidos após a mensagem. Veja Seção 4. |
| `regras_texto` | ❌ | lista de transições | Regras para desviar o fluxo quando o cliente digita palavras-chave. Veja Seção 5. |
| `requer_handoff` | ❌ | boolean | Se `true`, esta etapa encerra o bot e transfere a conversa para um atendente humano. Padrão: `false`. |
| `acao_sistema` | ❌ | string | Identificador de uma ação externa (webhook/integração) a ser chamada quando o cliente entra nesta etapa. Ex: `"consultar_pedido"`, `"verificar_disponibilidade"`. Deixar vazio se não houver integração. |

### 3.2 Regras importantes sobre Etapas

- **Toda automação precisa de pelo menos uma etapa.**
- **Nomes de etapas devem ser únicos** dentro da mesma automação (case-insensitive).
- Uma etapa sem `botoes` e sem `regras_texto` é um **nó terminal** — o bot responde a mensagem e aguarda input livre, mas não direciona o fluxo automaticamente (a menos que exista IA habilitada).
- A etapa com `requer_handoff: true` deve ter uma mensagem de despedida ou de transição clara para o cliente.
- Se uma etapa tem `botoes`, ela não precisa necessariamente ter `regras_texto` (e vice-versa) — mas ter ambos é válido e recomendado para cobrir tanto cliques quanto digitação.

---

## 4. Botões e Escolhas Rápidas (`options`)

Cada **botão** aparece como resposta rápida (quick-reply) para o cliente no WhatsApp.

| Sub-campo | Obrigatório | Tipo | Descrição |
|---|---|---|---|
| `texto_botao` | ✅ | string | Rótulo visível ao cliente. Máximo 20 caracteres recomendado (limite WhatsApp). Ex: `"Ver cardápio"`. |
| `etapa_destino` | ✅ | string | Nome exato de uma etapa da mesma automação para onde o fluxo vai quando o cliente clica neste botão. |

**Regras:**
- Uma etapa pode ter **0 a 10 botões** (limitado pelo WhatsApp).
- Cada botão deve apontar para uma etapa existente.
- O texto do botão não precisa ser igual ao nome da etapa destino.
- Ao clicar em um botão, o sistema cria automaticamente uma regra de transição usando o valor do botão como condição.

**Exemplo:**
```
Botão: "Falar com atendente"  →  Etapa destino: "Atendente humano"
Botão: "Ver produtos"         →  Etapa destino: "Catálogo de produtos"
Botão: "Rastrear pedido"      →  Etapa destino: "Rastreamento"
```

---

## 5. Regras para Texto Digitado (`transitions`)

As **regras de transição por texto** desviam o fluxo quando o cliente digita uma mensagem contendo uma palavra ou frase específica.

| Sub-campo | Obrigatório | Tipo | Descrição |
|---|---|---|---|
| `palavra_chave` | ✅ | string | Palavra ou frase que o sistema busca na mensagem do cliente (busca por `contains`, sem diferença de maiúsculas). Ex: `"horário"`, `"cancelar"`, `"sim"`. |
| `etapa_destino` | ✅ | string | Nome exato de uma etapa da mesma automação. |

**Regras:**
- Uma etapa pode ter **0 a N regras** de texto.
- A condição é **`contains`** — a mensagem do cliente apenas precisa *conter* a palavra-chave (não precisa ser exata).
- A verificação é **case-insensitive**.
- As regras são avaliadas **em ordem** — a primeira que casar é aplicada.
- Se nenhuma regra casar e não houver IA habilitada, o bot permanece na etapa atual e pode reenviar a mensagem ou aguardar nova entrada.
- Regras de texto **complementam** botões — cubra variações do mesmo tema (ex: botão "Horário" + regra `"horário"` + regra `"funciona"` + regra `"abre"`).

**Exemplo:**
```
Palavra-chave: "horário"      →  Etapa: "Horário de funcionamento"
Palavra-chave: "cancelar"     →  Etapa: "Cancelamento de pedido"
Palavra-chave: "humano"       →  Etapa: "Atendente humano"
Palavra-chave: "ajuda"        →  Etapa: "Menu principal"
```

---

## 6. Handoff (Transferência para Humano)

Quando uma etapa tem `requer_handoff: true`:

- O sistema encerra a execução do bot para aquela conversa.
- A conversa aparece na fila de atendimento humano.
- A mensagem da etapa é enviada ao cliente antes da transferência (deve ser uma mensagem de aviso/transição).
- **Uma automação pode ter múltiplas etapas com handoff** para diferentes contextos (ex: suporte técnico, reclamação, venda complexa).

---

## 7. Formato de Saída Esperado da IA

A IA generativa deve retornar a descrição da automação **estritamente** no formato abaixo. Este formato é legível por humanos e permite a implementação direta no painel.

### Template de saída:

```
AUTOMAÇÃO: <nome_snake_case>
DESCRIÇÃO: <frase descrevendo o propósito do fluxo>
ETAPA INICIAL: <nome exato da etapa inicial>

---

ETAPA: <Nome da Etapa 1>
MENSAGEM:
  <Texto completo que o bot envia. Pode ter múltiplas linhas.>
BOTÕES:
  - "<Texto do botão 1>" → "<Nome da Etapa destino>"
  - "<Texto do botão 2>" → "<Nome da Etapa destino>"
REGRAS DE TEXTO:
  - "<palavra-chave>" → "<Nome da Etapa destino>"
  - "<palavra-chave>" → "<Nome da Etapa destino>"
HANDOFF: não
AÇÃO SISTEMA: (vazio ou nome da ação)

---

ETAPA: <Nome da Etapa 2>
MENSAGEM:
  <Texto completo>
BOTÕES:
  (nenhum)
REGRAS DE TEXTO:
  (nenhuma)
HANDOFF: sim
AÇÃO SISTEMA: (vazio)

---
```

### Regras de formatação para a IA:

1. `AUTOMAÇÃO` — snake_case, sem acentos, sem espaços. Ex: `atendimento_pizzaria`
2. `ETAPA` — linguagem natural, pode ter acentos e espaços. Ex: `"Horário de funcionamento"`
3. `ETAPA INICIAL` — deve ser exatamente igual ao campo `ETAPA` de uma das etapas listadas.
4. Toda etapa referenciada em `BOTÕES` ou `REGRAS DE TEXTO` como destino **deve existir** na lista de etapas da mesma automação.
5. Toda etapa com `HANDOFF: sim` deve ter uma mensagem de aviso ao cliente.
6. A propriedade `AÇÃO SISTEMA` só deve ser preenchida quando o fluxo necessitar de uma integração externa real (ex: consulta de CEP, verificação de pedido).
7. **Não deixar etapas inalcançáveis** — toda etapa (exceto a inicial) deve ser destino de pelo menos um botão ou regra de texto.
8. **Não criar ciclos infinitos diretos** — evite `Etapa A → Etapa A`. Crie um "Menu principal" como ponto de retorno se necessário.

---

## 8. Diagrama de Fluxo — Como pensar a estrutura

```
[Cliente envia mensagem]
        ↓
[Etapa Inicial]
  → mensagem de boas-vindas
  → botões com as principais intenções
        ↓ (cliente clica ou digita)
[Etapa de conteúdo]
  → responde a dúvida específica
  → botão "Voltar ao menu" ou "Falar com atendente"
        ↓
[Etapa terminal ou handoff]
  → encerra fluxo ou transfere para humano
```

### Padrões recomendados de estrutura:

**Fluxo linear simples** (ideal para FAQ):
```
Início → Opção A → [fim]
       → Opção B → [fim]
       → Atendente → [handoff]
```

**Fluxo com retorno ao menu** (ideal para lojas com múltiplos temas):
```
Início → Tema 1 → Sub-resposta → "Voltar" → Início
       → Tema 2 → Sub-resposta → "Voltar" → Início
       → Atendente → [handoff]
```

**Fluxo com coleta de informação** (ideal para agendamento ou pedido):
```
Início → Confirmar interesse → Coleta dado 1 → Coleta dado 2 → Confirmação → [handoff ou fim]
```

---

## 9. Exemplos de Automações Completas

### Exemplo 1 — FAQ Loja de Roupas

```
AUTOMAÇÃO: atendimento_loja_roupas
DESCRIÇÃO: Atendimento inicial para loja de roupas com dúvidas frequentes sobre trocas, tamanhos e entrega
ETAPA INICIAL: Mensagem inicial

---

ETAPA: Mensagem inicial
MENSAGEM:
  Olá! 👗 Bem-vindo à *Loja da Moda*! Como posso te ajudar hoje?
BOTÕES:
  - "Tamanhos disponíveis" → "Tamanhos"
  - "Prazo de entrega" → "Entrega"
  - "Política de troca" → "Trocas"
  - "Falar com atendente" → "Atendente humano"
REGRAS DE TEXTO:
  - "troca" → "Trocas"
  - "entrega" → "Entrega"
  - "tamanho" → "Tamanhos"
  - "humano" → "Atendente humano"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

---

ETAPA: Tamanhos
MENSAGEM:
  📏 Trabalhamos com os tamanhos P, M, G e GG.
  Para peças específicas, consulte a tabela de medidas no nosso site.
  Posso te ajudar com mais alguma coisa?
BOTÕES:
  - "Voltar ao menu" → "Mensagem inicial"
  - "Falar com atendente" → "Atendente humano"
REGRAS DE TEXTO:
  - "menu" → "Mensagem inicial"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

---

ETAPA: Entrega
MENSAGEM:
  🚚 Nosso prazo de entrega é de *3 a 7 dias úteis* após a confirmação do pagamento.
  Frete grátis para compras acima de R$ 150!
BOTÕES:
  - "Voltar ao menu" → "Mensagem inicial"
  - "Falar com atendente" → "Atendente humano"
REGRAS DE TEXTO:
  - "menu" → "Mensagem inicial"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

---

ETAPA: Trocas
MENSAGEM:
  🔄 Você tem *7 dias* após o recebimento para solicitar troca.
  O produto deve estar sem uso, com etiqueta original.
  Para iniciar o processo, fale com nosso atendente!
BOTÕES:
  - "Falar com atendente" → "Atendente humano"
  - "Voltar ao menu" → "Mensagem inicial"
REGRAS DE TEXTO:
  (nenhuma)
HANDOFF: não
AÇÃO SISTEMA: (vazio)

---

ETAPA: Atendente humano
MENSAGEM:
  👤 Perfeito! Vou te conectar com um de nossos atendentes agora.
  O tempo de espera é de até 5 minutos. Obrigado pela paciência! 🙏
BOTÕES:
  (nenhum)
REGRAS DE TEXTO:
  (nenhuma)
HANDOFF: sim
AÇÃO SISTEMA: (vazio)
```

---

### Exemplo 2 — Restaurante com Pedido

```
AUTOMAÇÃO: atendimento_restaurante
DESCRIÇÃO: Fluxo de atendimento para restaurante com cardápio, horário e pedido via WhatsApp
ETAPA INICIAL: Boas-vindas

---

ETAPA: Boas-vindas
MENSAGEM:
  Olá! 🍕 Seja bem-vindo ao *Restaurante Sabor & Arte*!
  O que deseja hoje?
BOTÕES:
  - "Ver cardápio" → "Cardápio"
  - "Fazer pedido" → "Fazer pedido"
  - "Horário de funcionamento" → "Horário"
  - "Falar com atendente" → "Atendente"
REGRAS DE TEXTO:
  - "cardápio" → "Cardápio"
  - "pedido" → "Fazer pedido"
  - "horário" → "Horário"
  - "funciona" → "Horário"
  - "abre" → "Horário"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

---

ETAPA: Cardápio
MENSAGEM:
  📋 *Nosso Cardápio:*

  🍕 Pizzas a partir de R$ 39,90
  🍝 Massas a partir de R$ 29,90
  🥗 Saladas a partir de R$ 19,90
  🥤 Bebidas a partir de R$ 7,00

  Para fazer seu pedido, basta clicar abaixo!
BOTÕES:
  - "Fazer pedido" → "Fazer pedido"
  - "Voltar" → "Boas-vindas"
REGRAS DE TEXTO:
  - "pedido" → "Fazer pedido"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

---

ETAPA: Horário
MENSAGEM:
  🕐 *Horários de funcionamento:*

  Segunda a Sexta: 11h às 23h
  Sábados: 11h às 00h
  Domingos e Feriados: 12h às 22h

  Delivery disponível todos os dias! 🛵
BOTÕES:
  - "Fazer pedido" → "Fazer pedido"
  - "Voltar" → "Boas-vindas"
REGRAS DE TEXTO:
  (nenhuma)
HANDOFF: não
AÇÃO SISTEMA: (vazio)

---

ETAPA: Fazer pedido
MENSAGEM:
  🛒 Ótimo! Para realizar seu pedido, por favor nos informe:

  1️⃣ Seu nome
  2️⃣ Seu endereço completo (ou informe "retirada" se for buscar)
  3️⃣ O que deseja pedir

  Nosso atendente vai confirmar tudo e informar o tempo estimado! 😊
BOTÕES:
  - "Falar com atendente" → "Atendente"
REGRAS DE TEXTO:
  (nenhuma)
HANDOFF: não
AÇÃO SISTEMA: (vazio)

---

ETAPA: Atendente
MENSAGEM:
  👨‍🍳 Perfeito! Estou passando você para nosso atendente finalizar o pedido.
  Aguarde um instante! ⏳
BOTÕES:
  (nenhum)
REGRAS DE TEXTO:
  (nenhuma)
HANDOFF: sim
AÇÃO SISTEMA: (vazio)
```

---

## 10. Checklist de Validação

Antes de entregar a descrição, a IA deve verificar:

- [ ] O campo `AUTOMAÇÃO` está em snake_case sem acentos?
- [ ] A `ETAPA INICIAL` existe como etapa listada?
- [ ] Todos os destinos de `BOTÕES` e `REGRAS DE TEXTO` apontam para etapas que existem na lista?
- [ ] Toda etapa (exceto a inicial) é destino de pelo menos um botão ou regra?
- [ ] Toda etapa com `HANDOFF: sim` tem mensagem de aviso?
- [ ] Nenhuma etapa está em ciclo direto com ela mesma?
- [ ] O texto das mensagens usa linguagem natural, adequada ao tipo de negócio?
- [ ] Os botões têm no máximo 20 caracteres?
- [ ] Etapas de coleta de informação (nome, endereço, data) têm handoff ou ação de sistema para processar os dados?

---

## 11. Instruções para a IA Geradora de Fluxo

Ao receber uma solicitação como _"crie uma automação para uma clínica odontológica que atende agendamentos"_, a IA deve:

1. **Identificar as intenções principais** do cliente final (o que as pessoas mais perguntam naquele tipo de negócio).
2. **Criar uma etapa inicial** com saudação contextual ao nicho (clínica, loja, restaurante, etc.) e botões para as intenções identificadas.
3. **Criar uma etapa para cada intenção** com a informação relevante e opções de continuidade.
4. **Sempre criar uma etapa de handoff** chamada "Atendente humano" ou similar.
5. **Adicionar regras de texto** nas etapas mais prováveis de receber input livre (etapa inicial, menu, coleta de dados).
6. **Usar linguagem do nicho** — um pet shop usa 🐾, uma clínica usa linguagem formal, uma lanchonete usa linguagem jovial.
7. **Não omitir nenhum campo** — mesmo que vazio, declarar `(nenhum)` ou `(vazio)` explicitamente para facilitar a implementação.
8. **Gerar fluxos completos**, não esboços — todas as mensagens devem ter conteúdo real, não placeholders como `"mensagem aqui"`.

---

*Documento gerado em: 14/05/2026 — Sistema de chatbot WhatsApp com painel administrativo Flutter.*
