AUTOMAÇÃO: atendimento_pizzaria_delivery
DESCRIÇÃO: Fluxo completo de atendimento para pizzaria com cardápio, pedidos, sabores, entrega, retirada, promoções e atendimento humano
ETAPA INICIAL: Boas-vindas

ETAPA: Boas-vindas
MENSAGEM:
Olá! 🍕 Seja muito bem-vindo à Pizzaria Bella Massa!
É um prazer atender você 😊

Como podemos te ajudar hoje?

Escolha uma das opções abaixo 👇
BOTÕES:

"Ver cardápio" → "Cardápio principal"
"Fazer pedido" → "Iniciar pedido"
"Promoções" → "Promoções do dia"
"Horários" → "Horário funcionamento"
"Atendente" → "Atendente humano"
REGRAS DE TEXTO:
"cardápio" → "Cardápio principal"
"menu" → "Cardápio principal"
"pizza" → "Cardápio principal"
"pedido" → "Iniciar pedido"
"promoção" → "Promoções do dia"
"cupom" → "Promoções do dia"
"horário" → "Horário funcionamento"
"abre" → "Horário funcionamento"
"funciona" → "Horário funcionamento"
"humano" → "Atendente humano"
"atendente" → "Atendente humano"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

ETAPA: Cardápio principal
MENSAGEM:
📋 Nosso Cardápio

🍕 Pizzas Tradicionais
🍕 Pizzas Especiais
🍫 Pizzas Doces
🥤 Bebidas
🧄 Bordas recheadas

Escolha uma categoria para visualizar 👇
BOTÕES:

"Tradicionais" → "Pizzas tradicionais"
"Especiais" → "Pizzas especiais"
"Pizzas doces" → "Pizzas doces"
"Bebidas" → "Bebidas"
"Voltar menu" → "Boas-vindas"
REGRAS DE TEXTO:
"tradicional" → "Pizzas tradicionais"
"especial" → "Pizzas especiais"
"doce" → "Pizzas doces"
"bebida" → "Bebidas"
"menu" → "Boas-vindas"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

ETAPA: Pizzas tradicionais
MENSAGEM:
🍕 Pizzas Tradicionais

• Mussarela — R$ 39,90
• Calabresa — R$ 42,90
• Portuguesa — R$ 45,90
• Frango com Catupiry — R$ 46,90

Todos os sabores disponíveis nos tamanhos:
Broto, Média e Grande 😊
BOTÕES:

"Fazer pedido" → "Iniciar pedido"
"Ver especiais" → "Pizzas especiais"
"Voltar menu" → "Cardápio principal"
REGRAS DE TEXTO:
"pedido" → "Iniciar pedido"
"especial" → "Pizzas especiais"
"voltar" → "Cardápio principal"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

ETAPA: Pizzas especiais
MENSAGEM:
👑 Pizzas Especiais

• Camarão Especial — R$ 69,90
• Parma com Rúcula — R$ 64,90
• Quatro Queijos Premium — R$ 59,90
• Costela BBQ — R$ 72,90

Deseja fazer um pedido? 😋
BOTÕES:

"Fazer pedido" → "Iniciar pedido"
"Pizzas doces" → "Pizzas doces"
"Voltar menu" → "Cardápio principal"
REGRAS DE TEXTO:
"pedido" → "Iniciar pedido"
"doce" → "Pizzas doces"
"menu" → "Cardápio principal"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

ETAPA: Pizzas doces
MENSAGEM:
🍫 Pizzas Doces

• Chocolate com Morango — R$ 49,90
• Banana com Canela — R$ 42,90
• Prestígio — R$ 47,90
• Nutella com Leite Ninho — R$ 59,90

Uma delícia para finalizar sua noite 😍
BOTÕES:

"Fazer pedido" → "Iniciar pedido"
"Bebidas" → "Bebidas"
"Voltar menu" → "Cardápio principal"
REGRAS DE TEXTO:
"pedido" → "Iniciar pedido"
"bebida" → "Bebidas"
"menu" → "Cardápio principal"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

ETAPA: Bebidas
MENSAGEM:
🥤 Bebidas disponíveis

• Refrigerante Lata — R$ 7,00
• Refrigerante 2L — R$ 14,00
• Suco Natural — R$ 10,00
• Água Mineral — R$ 4,00

Deseja adicionar bebidas ao seu pedido?
BOTÕES:

"Fazer pedido" → "Iniciar pedido"
"Voltar menu" → "Cardápio principal"
REGRAS DE TEXTO:
"pedido" → "Iniciar pedido"
"menu" → "Cardápio principal"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

ETAPA: Promoções do dia
MENSAGEM:
🎉 Promoções de Hoje

🍕 2 Pizzas Grandes Tradicionais + Refrigerante 2L
💰 Apenas R$ 89,90

🍫 Pizza doce com 20% OFF após 22h

🚚 Delivery grátis para pedidos acima de R$ 80,00 em até 5km

Aproveite! 😍
BOTÕES:

"Fazer pedido" → "Iniciar pedido"
"Ver cardápio" → "Cardápio principal"
"Voltar menu" → "Boas-vindas"
REGRAS DE TEXTO:
"pedido" → "Iniciar pedido"
"cardápio" → "Cardápio principal"
"menu" → "Boas-vindas"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

ETAPA: Horário funcionamento
MENSAGEM:
🕐 Horário de funcionamento

Segunda a Quinta: 18h às 23h
Sexta e Sábado: 18h à 00h
Domingo: 18h às 22h

🛵 Delivery disponível todos os dias!

Posso ajudar com mais alguma coisa? 😊
BOTÕES:

"Fazer pedido" → "Iniciar pedido"
"Voltar menu" → "Boas-vindas"
REGRAS DE TEXTO:
"pedido" → "Iniciar pedido"
"menu" → "Boas-vindas"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

ETAPA: Iniciar pedido
MENSAGEM:
🛒 Perfeito! Vamos iniciar seu pedido 😊

Por favor, envie:

• Seu nome
• Seu endereço completo
• Sabores desejados
• Tamanho da pizza
• Forma de pagamento

Caso prefira retirada, informe: RETIRADA
BOTÕES:

"Entrega" → "Pedido entrega"
"Retirada" → "Pedido retirada"
"Atendente" → "Atendente humano"
REGRAS DE TEXTO:
"entrega" → "Pedido entrega"
"retirada" → "Pedido retirada"
"humano" → "Atendente humano"
HANDOFF: não
AÇÃO SISTEMA: (vazio)

ETAPA: Pedido entrega
MENSAGEM:
🚚 Perfeito! Seu pedido será enviado por delivery.

Agora envie:

📍 Endereço completo
🍕 Sabores desejados
💳 Forma de pagamento

Nosso time irá confirmar tudo rapidinho 😊
BOTÕES:

"Atendente" → "Atendente humano"
"Voltar menu" → "Boas-vindas"
REGRAS DE TEXTO:
"menu" → "Boas-vindas"
"humano" → "Atendente humano"
HANDOFF: não
AÇÃO SISTEMA: registrar_pedido_delivery

ETAPA: Pedido retirada
MENSAGEM:
🏪 Perfeito! Seu pedido ficará disponível para retirada em nossa loja.

Agora envie:

🍕 Sabores desejados
📞 Nome para retirada
💳 Forma de pagamento

Assim que estiver pronto avisaremos 😊
BOTÕES:

"Atendente" → "Atendente humano"
"Voltar menu" → "Boas-vindas"
REGRAS DE TEXTO:
"menu" → "Boas-vindas"
"humano" → "Atendente humano"
HANDOFF: não
AÇÃO SISTEMA: registrar_pedido_retirada

ETAPA: Consultar pedido
MENSAGEM:
📦 Para consultar seu pedido, envie:

• Número do pedido
ou
• CPF utilizado na compra

Vamos localizar para você 😊
BOTÕES:

"Voltar menu" → "Boas-vindas"
"Atendente" → "Atendente humano"
REGRAS DE TEXTO:
"pedido" → "Consultar pedido status"
"humano" → "Atendente humano"
HANDOFF: não
AÇÃO SISTEMA: consultar_status_pedido

ETAPA: Consultar pedido status
MENSAGEM:
🔎 Estamos verificando o status do seu pedido.

Em instantes você receberá as informações atualizadas 🍕
BOTÕES:

"Voltar menu" → "Boas-vindas"
REGRAS DE TEXTO:
"menu" → "Boas-vindas"
HANDOFF: não
AÇÃO SISTEMA: verificar_status_pedido

ETAPA: Atendente humano
MENSAGEM:
👨‍🍳 Perfeito! Vou encaminhar sua conversa para um de nossos atendentes agora.

Nosso tempo médio de resposta é de até 5 minutos 😊

Obrigado pela paciência! 🍕
BOTÕES:
(nenhum)
REGRAS DE TEXTO:
(nenhuma)
HANDOFF: sim
AÇÃO SISTEMA: (vazio)