-- ============================================================
-- Migration 004 — Demo tenant: Pizzaria Bella Massa
-- ============================================================
SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- ----------------------------------------------------------
-- 1. Tenant
-- ----------------------------------------------------------
INSERT INTO tenants (external_key, name, email, whatsapp_phone_number, whatsapp_token, status, plan)
SELECT
    'pizzaria_bella_massa',
    'Pizzaria Bella Massa',
    'contato@bellamassa.com.br',
    '+5511988887777',
    'demo_token_pizzaria',
    'active',
    'professional'
WHERE NOT EXISTS (
    SELECT 1 FROM tenants WHERE external_key = 'pizzaria_bella_massa'
);

-- ----------------------------------------------------------
-- 2. Subscription
-- ----------------------------------------------------------
INSERT INTO subscriptions (tenant_id, plan, status, renewal_date, monthly_message_limit)
SELECT
    t.id,
    'professional',
    'active',
    DATE_ADD(UTC_TIMESTAMP(), INTERVAL 30 DAY),
    10000
FROM tenants t
WHERE t.external_key = 'pizzaria_bella_massa'
  AND NOT EXISTS (
      SELECT 1 FROM subscriptions s WHERE s.tenant_id = t.id
  );

-- ----------------------------------------------------------
-- 3. Tenant settings
-- ----------------------------------------------------------
INSERT INTO tenant_settings (
    tenant_id, ai_enabled, flow_editing_enabled, debug_mode,
    gemini_model, fallback_models, available_models
)
SELECT
    t.id,
    1,
    1,
    0,
    'gemini-1.5-flash-latest',
    JSON_ARRAY(
        'gemini-2.5-flash','gemini-2.0-flash','gemini-1.5-flash',
        'gemini-1.0-pro','gemini-pro','gemini-1.5-pro',
        'gemini-2.0-pro','gemini-2.0-flash-lite',
        'gemini-1.5-flash-latest','gemini-1.5-pro-latest'
    ),
    JSON_ARRAY(
        'gemini-2.5-flash','gemini-2.0-flash','gemini-1.5-flash',
        'gemini-1.0-pro','gemini-pro','gemini-1.5-pro',
        'gemini-2.0-pro','gemini-2.0-flash-lite',
        'gemini-1.5-flash-latest','gemini-1.5-pro-latest'
    )
FROM tenants t
WHERE t.external_key = 'pizzaria_bella_massa'
  AND NOT EXISTS (
      SELECT 1 FROM tenant_settings ts WHERE ts.tenant_id = t.id
  );

-- ----------------------------------------------------------
-- 4. Admin user
-- Hash corresponds to password: Bella@2026!
-- Algorithm: pbkdf2_sha256 / 120000 iterations (jwt_tools.py)
-- ----------------------------------------------------------
INSERT INTO users (tenant_id, email, display_name, password_hash, role, status)
SELECT
    t.id,
    'admin@bellamassa.com.br',
    'Admin Bella Massa',
    'pbkdf2_sha256$120000$obLD1OX2obLD1OX2obLD1A==$qD34iOxAZxTQtq3xmtX4WUQ6ezRS1GpJ9X3NkL50nn4=',
    'owner',
    'active'
FROM tenants t
WHERE t.external_key = 'pizzaria_bella_massa'
  AND NOT EXISTS (
      SELECT 1 FROM users u WHERE u.email = 'admin@bellamassa.com.br'
  );

-- ----------------------------------------------------------
-- 5. Flow metadata
-- ----------------------------------------------------------
INSERT INTO flows (tenant_id, flow_key, name, description, start_state_key, is_active)
SELECT
    t.id,
    'atendimento_pizzaria_delivery',
    'atendimento_pizzaria_delivery',
    'Fluxo completo de atendimento para pizzaria com cardapio, pedidos, sabores, entrega, retirada, promocoes e atendimento humano',
    'boas_vindas',
    1
FROM tenants t
WHERE t.external_key = 'pizzaria_bella_massa'
  AND NOT EXISTS (
      SELECT 1 FROM flows f
      WHERE f.tenant_id = t.id AND f.flow_key = 'atendimento_pizzaria_delivery'
  );

-- ----------------------------------------------------------
-- 6. Flow YAML document (used by admin panel)
-- ----------------------------------------------------------
INSERT INTO flow_documents (tenant_id, flow_key, yaml_content, version)
SELECT
    t.id,
    'atendimento_pizzaria_delivery',
    'name: atendimento_pizzaria_delivery\ndescription: "Fluxo completo de atendimento para pizzaria com cardapio, pedidos, sabores, entrega, retirada, promocoes e atendimento humano"\nstart_state: boas_vindas\nstates:\n  boas_vindas:\n    display_name: "Boas-vindas"\n    message: "Ola! Seja muito bem-vindo a Pizzaria Bella Massa!\\nE um prazer atender voce\\n\\nComo podemos te ajudar hoje?\\n\\nEscolha uma das opcoes abaixo"\n    options:\n      - label: "Ver cardapio"\n        value: "ver_cardapio"\n      - label: "Fazer pedido"\n        value: "fazer_pedido"\n      - label: "Promocoes"\n        value: "promocoes"\n      - label: "Horarios"\n        value: "horarios"\n      - label: "Atendente"\n        value: "atendente"\n    transitions:\n      - condition: "contains:ver_cardapio"\n        target_state: cardapio_principal\n      - condition: "contains:fazer_pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:promocoes"\n        target_state: promocoes_do_dia\n      - condition: "contains:horarios"\n        target_state: horario_funcionamento\n      - condition: "contains:atendente"\n        target_state: atendente_humano\n      - condition: "contains:cardapio"\n        target_state: cardapio_principal\n      - condition: "contains:menu"\n        target_state: cardapio_principal\n      - condition: "contains:pizza"\n        target_state: cardapio_principal\n      - condition: "contains:pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:promocao"\n        target_state: promocoes_do_dia\n      - condition: "contains:cupom"\n        target_state: promocoes_do_dia\n      - condition: "contains:horario"\n        target_state: horario_funcionamento\n      - condition: "contains:abre"\n        target_state: horario_funcionamento\n      - condition: "contains:funciona"\n        target_state: horario_funcionamento\n      - condition: "contains:humano"\n        target_state: atendente_humano\n  cardapio_principal:\n    display_name: "Cardapio principal"\n    message: "Nosso Cardapio\\n\\nPizzas Tradicionais\\nPizzas Especiais\\nPizzas Doces\\nBebidas\\nBordas recheadas\\n\\nEscolha uma categoria para visualizar"\n    options:\n      - label: "Tradicionais"\n        value: "tradicionais"\n      - label: "Especiais"\n        value: "especiais"\n      - label: "Pizzas doces"\n        value: "pizzas_doces"\n      - label: "Bebidas"\n        value: "bebidas"\n      - label: "Voltar menu"\n        value: "voltar_menu"\n    transitions:\n      - condition: "contains:tradicionais"\n        target_state: pizzas_tradicionais\n      - condition: "contains:especiais"\n        target_state: pizzas_especiais\n      - condition: "contains:pizzas_doces"\n        target_state: pizzas_doces\n      - condition: "contains:bebidas"\n        target_state: bebidas\n      - condition: "contains:voltar_menu"\n        target_state: boas_vindas\n      - condition: "contains:tradicional"\n        target_state: pizzas_tradicionais\n      - condition: "contains:especial"\n        target_state: pizzas_especiais\n      - condition: "contains:doce"\n        target_state: pizzas_doces\n      - condition: "contains:bebida"\n        target_state: bebidas\n      - condition: "contains:menu"\n        target_state: boas_vindas\n  pizzas_tradicionais:\n    display_name: "Pizzas tradicionais"\n    message: "Pizzas Tradicionais\\n\\nMussarela - R$ 39,90\\nCalabresa - R$ 42,90\\nPortuguesa - R$ 45,90\\nFrango com Catupiry - R$ 46,90\\n\\nTodos os sabores disponiveis nos tamanhos:\\nBroto, Media e Grande"\n    options:\n      - label: "Fazer pedido"\n        value: "fazer_pedido"\n      - label: "Ver especiais"\n        value: "ver_especiais"\n      - label: "Voltar menu"\n        value: "voltar_menu"\n    transitions:\n      - condition: "contains:fazer_pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:ver_especiais"\n        target_state: pizzas_especiais\n      - condition: "contains:voltar_menu"\n        target_state: cardapio_principal\n      - condition: "contains:pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:especial"\n        target_state: pizzas_especiais\n      - condition: "contains:voltar"\n        target_state: cardapio_principal\n  pizzas_especiais:\n    display_name: "Pizzas especiais"\n    message: "Pizzas Especiais\\n\\nCamarao Especial - R$ 69,90\\nParma com Rucula - R$ 64,90\\nQuatro Queijos Premium - R$ 59,90\\nCostela BBQ - R$ 72,90\\n\\nDeseja fazer um pedido?"\n    options:\n      - label: "Fazer pedido"\n        value: "fazer_pedido"\n      - label: "Pizzas doces"\n        value: "pizzas_doces"\n      - label: "Voltar menu"\n        value: "voltar_menu"\n    transitions:\n      - condition: "contains:fazer_pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:pizzas_doces"\n        target_state: pizzas_doces\n      - condition: "contains:voltar_menu"\n        target_state: cardapio_principal\n      - condition: "contains:pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:doce"\n        target_state: pizzas_doces\n      - condition: "contains:menu"\n        target_state: cardapio_principal\n  pizzas_doces:\n    display_name: "Pizzas doces"\n    message: "Pizzas Doces\\n\\nChocolate com Morango - R$ 49,90\\nBanana com Canela - R$ 42,90\\nPrestigio - R$ 47,90\\nNutella com Leite Ninho - R$ 59,90\\n\\nUma delicia para finalizar sua noite!"\n    options:\n      - label: "Fazer pedido"\n        value: "fazer_pedido"\n      - label: "Bebidas"\n        value: "bebidas"\n      - label: "Voltar menu"\n        value: "voltar_menu"\n    transitions:\n      - condition: "contains:fazer_pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:bebidas"\n        target_state: bebidas\n      - condition: "contains:voltar_menu"\n        target_state: cardapio_principal\n      - condition: "contains:pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:bebida"\n        target_state: bebidas\n      - condition: "contains:menu"\n        target_state: cardapio_principal\n  bebidas:\n    display_name: "Bebidas"\n    message: "Bebidas disponiveis\\n\\nRefrigerante Lata - R$ 7,00\\nRefrigerante 2L - R$ 14,00\\nSuco Natural - R$ 10,00\\nAgua Mineral - R$ 4,00\\n\\nDeseja adicionar bebidas ao seu pedido?"\n    options:\n      - label: "Fazer pedido"\n        value: "fazer_pedido"\n      - label: "Voltar menu"\n        value: "voltar_menu"\n    transitions:\n      - condition: "contains:fazer_pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:voltar_menu"\n        target_state: cardapio_principal\n      - condition: "contains:pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:menu"\n        target_state: cardapio_principal\n  promocoes_do_dia:\n    display_name: "Promocoes do dia"\n    message: "Promocoes de Hoje\\n\\n2 Pizzas Grandes Tradicionais + Refrigerante 2L\\nApenas R$ 89,90\\n\\nPizza doce com 20% OFF apos 22h\\n\\nDelivery gratis para pedidos acima de R$ 80,00 em ate 5km\\n\\nAproveite!"\n    options:\n      - label: "Fazer pedido"\n        value: "fazer_pedido"\n      - label: "Ver cardapio"\n        value: "ver_cardapio"\n      - label: "Voltar menu"\n        value: "voltar_menu"\n    transitions:\n      - condition: "contains:fazer_pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:ver_cardapio"\n        target_state: cardapio_principal\n      - condition: "contains:voltar_menu"\n        target_state: boas_vindas\n      - condition: "contains:pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:cardapio"\n        target_state: cardapio_principal\n      - condition: "contains:menu"\n        target_state: boas_vindas\n  horario_funcionamento:\n    display_name: "Horario funcionamento"\n    message: "Horario de funcionamento\\n\\nSegunda a Quinta: 18h as 23h\\nSexta e Sabado: 18h a 00h\\nDomingo: 18h as 22h\\n\\nDelivery disponivel todos os dias!\\n\\nPosso ajudar com mais alguma coisa?"\n    options:\n      - label: "Fazer pedido"\n        value: "fazer_pedido"\n      - label: "Voltar menu"\n        value: "voltar_menu"\n    transitions:\n      - condition: "contains:fazer_pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:voltar_menu"\n        target_state: boas_vindas\n      - condition: "contains:pedido"\n        target_state: iniciar_pedido\n      - condition: "contains:menu"\n        target_state: boas_vindas\n  iniciar_pedido:\n    display_name: "Iniciar pedido"\n    message: "Perfeito! Vamos iniciar seu pedido\\n\\nPor favor, envie:\\n\\nSeu nome\\nSeu endereco completo\\nSabores desejados\\nTamanho da pizza\\nForma de pagamento\\n\\nCaso prefira retirada, informe: RETIRADA"\n    options:\n      - label: "Entrega"\n        value: "entrega"\n      - label: "Retirada"\n        value: "retirada"\n      - label: "Atendente"\n        value: "atendente"\n    transitions:\n      - condition: "contains:entrega"\n        target_state: pedido_entrega\n      - condition: "contains:retirada"\n        target_state: pedido_retirada\n      - condition: "contains:atendente"\n        target_state: atendente_humano\n      - condition: "contains:humano"\n        target_state: atendente_humano\n  pedido_entrega:\n    display_name: "Pedido entrega"\n    message: "Perfeito! Seu pedido sera enviado por delivery.\\n\\nAgora envie:\\n\\nEndereco completo\\nSabores desejados\\nForma de pagamento\\n\\nNosso time ira confirmar tudo rapidinho"\n    options:\n      - label: "Atendente"\n        value: "atendente"\n      - label: "Voltar menu"\n        value: "voltar_menu"\n    transitions:\n      - condition: "contains:atendente"\n        target_state: atendente_humano\n      - condition: "contains:voltar_menu"\n        target_state: boas_vindas\n      - condition: "contains:menu"\n        target_state: boas_vindas\n      - condition: "contains:humano"\n        target_state: atendente_humano\n    hook:\n      action: "registrar_pedido_delivery"\n  pedido_retirada:\n    display_name: "Pedido retirada"\n    message: "Perfeito! Seu pedido ficara disponivel para retirada em nossa loja.\\n\\nAgora envie:\\n\\nSabores desejados\\nNome para retirada\\nForma de pagamento\\n\\nAssim que estiver pronto avisaremos"\n    options:\n      - label: "Atendente"\n        value: "atendente"\n      - label: "Voltar menu"\n        value: "voltar_menu"\n    transitions:\n      - condition: "contains:atendente"\n        target_state: atendente_humano\n      - condition: "contains:voltar_menu"\n        target_state: boas_vindas\n      - condition: "contains:menu"\n        target_state: boas_vindas\n      - condition: "contains:humano"\n        target_state: atendente_humano\n    hook:\n      action: "registrar_pedido_retirada"\n  consultar_pedido:\n    display_name: "Consultar pedido"\n    message: "Para consultar seu pedido, envie:\\n\\nNumero do pedido\\nou\\nCPF utilizado na compra\\n\\nVamos localizar para voce"\n    options:\n      - label: "Voltar menu"\n        value: "voltar_menu"\n      - label: "Atendente"\n        value: "atendente"\n    transitions:\n      - condition: "contains:voltar_menu"\n        target_state: boas_vindas\n      - condition: "contains:atendente"\n        target_state: atendente_humano\n      - condition: "contains:pedido"\n        target_state: consultar_pedido_status\n      - condition: "contains:humano"\n        target_state: atendente_humano\n    hook:\n      action: "consultar_status_pedido"\n  consultar_pedido_status:\n    display_name: "Consultar pedido status"\n    message: "Estamos verificando o status do seu pedido.\\n\\nEm instantes voce recebera as informacoes atualizadas"\n    options:\n      - label: "Voltar menu"\n        value: "voltar_menu"\n    transitions:\n      - condition: "contains:voltar_menu"\n        target_state: boas_vindas\n      - condition: "contains:menu"\n        target_state: boas_vindas\n    hook:\n      action: "verificar_status_pedido"\n  atendente_humano:\n    display_name: "Atendente humano"\n    message: "Perfeito! Vou encaminhar sua conversa para um de nossos atendentes agora.\\n\\nNosso tempo medio de resposta e de ate 5 minutos\\n\\nObrigado pela paciencia!"\n    requires_handoff: true\n',
    1
FROM tenants t
WHERE t.external_key = 'pizzaria_bella_massa'
  AND NOT EXISTS (
      SELECT 1 FROM flow_documents fd
      WHERE fd.tenant_id = t.id AND fd.flow_key = 'atendimento_pizzaria_delivery'
  );
