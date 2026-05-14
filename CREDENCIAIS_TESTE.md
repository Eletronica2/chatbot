# Credenciais de teste

Atualizado em 2026-05-13, apos limpeza completa do banco e reprovisionamento da stack.

Este arquivo lista os tenants, empresas e usuarios atualmente disponiveis para login e smoke test.

## Empresas provisionadas

| Tipo | Tenant ID | Empresa | Email | Status | Plano |
| --- | --- | --- | --- | --- | --- |
| Operacao interna | default | Operacao SaaS | operacao@chatbot.local | active | starter |
| Empresa modelo | loja_centro_demo | Loja Centro Demo | contato@lojacentro.local | active | starter |
| Empresa demo (pizzaria) | pizzaria_bella_massa | Pizzaria Bella Massa | contato@bellamassa.com.br | active | professional |

## Usuarios para login

| Escopo | Perfil no painel | Role tecnico | Email | Senha | Permissoes principais |
| --- | --- | --- | --- | --- | --- |
| default | Superadmin | superadmin | arthurlaranjo@hotmail.com | adminpanel | Gerencia o sistema inteiro, empresas, usuarios admins, cobranca e ativacoes |
| loja_centro_demo | Admin da empresa | owner | admin@lojacentro.local | empresa123 | Gerencia automacoes e configuracoes da propria empresa |
| pizzaria_bella_massa | Admin da empresa | owner | admin@bellamassa.com.br | Bella@2026! | Gerencia automacoes e configuracoes da Pizzaria Bella Massa |

## Automacoes disponíveis por tenant

| Tenant | Fluxo | Etapa inicial | Etapas | Handoff |
| --- | --- | --- | --- | --- |
| pizzaria_bella_massa | atendimento_pizzaria_delivery | boas_vindas | 14 (cardapio, pedido, entrega, retirada, promocoes, horario) | Atendente humano |

## Como testar

- Login da API: POST `http://localhost:8000/api/v1/auth/login`
- No painel, o role tecnico `owner` aparece com o rotulo visual `Admin da empresa`.
- O tenant `default` e um contexto interno do SaaS. Para validar o fluxo de cliente, use `loja_centro_demo`.
