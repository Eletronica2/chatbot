SET NAMES utf8mb4;

INSERT INTO tenants (
    external_key,
    name,
    email,
    whatsapp_phone_number,
    whatsapp_token,
    status,
    plan
)
SELECT
    'default',
    'Operacao SaaS',
    'operacao@chatbot.local',
    '+5511999999999',
    'demo_token_placeholder',
    'active',
    'starter'
WHERE NOT EXISTS (
    SELECT 1
    FROM tenants
    WHERE external_key = 'default'
);

INSERT INTO subscriptions (
    tenant_id,
    plan,
    status,
    renewal_date,
    monthly_message_limit
)
SELECT
    t.id,
    'starter',
    'active',
    DATE_ADD(UTC_TIMESTAMP(), INTERVAL 30 DAY),
    1000
FROM tenants t
WHERE t.external_key = 'default'
  AND NOT EXISTS (
      SELECT 1
      FROM subscriptions s
      WHERE s.tenant_id = t.id
  );

INSERT INTO tenant_settings (
    tenant_id,
    ai_enabled,
    flow_editing_enabled,
    debug_mode,
    gemini_model,
    fallback_models,
    available_models
)
SELECT
    t.id,
    1,
    1,
    0,
    'gemini-1.5-flash-latest',
    JSON_ARRAY(
      'gemini-2.5-flash',
      'gemini-2.0-flash',
      'gemini-1.5-flash',
      'gemini-1.0-pro',
      'gemini-pro',
      'gemini-1.5-pro',
      'gemini-2.0-pro',
      'gemini-2.0-flash-lite',
      'gemini-1.5-flash-latest',
      'gemini-1.5-pro-latest'
    ),
    JSON_ARRAY(
      'gemini-2.5-flash',
      'gemini-2.0-flash',
      'gemini-1.5-flash',
      'gemini-1.0-pro',
      'gemini-pro',
      'gemini-1.5-pro',
      'gemini-2.0-pro',
      'gemini-2.0-flash-lite',
      'gemini-1.5-flash-latest',
      'gemini-1.5-pro-latest'
    )
FROM tenants t
WHERE t.external_key = 'default'
  AND NOT EXISTS (
      SELECT 1
      FROM tenant_settings ts
      WHERE ts.tenant_id = t.id
  );
