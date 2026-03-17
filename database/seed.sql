INSERT INTO tenants (tenant_id, name, slug, whatsapp_phone)
VALUES (
    uuid_generate_v4(),
    'Tenant Demo',
    'tenant-demo',
    '+5511999999999'
)
ON CONFLICT (slug) DO NOTHING;

WITH t AS (
    SELECT tenant_id FROM tenants WHERE slug = 'tenant-demo'
)
INSERT INTO sessions (tenant_id, phone_number, last_flow, last_state, session_state, context, status)
SELECT tenant_id, '+5511888888888', 'start', 'greeting', '{"last_flow":"start","last_state":"greeting"}', '{}', 'open' FROM t
ON CONFLICT (tenant_id, phone_number) DO NOTHING;

WITH t AS (
    SELECT tenant_id, session_id FROM sessions WHERE phone_number = '+5511888888888'
)
INSERT INTO flow_states (tenant_id, session_id, flow_name, current_state, state_data)
SELECT tenant_id, session_id, 'start', 'greeting', '{"step":"welcome"}' FROM t
ON CONFLICT (tenant_id, session_id, flow_name) DO NOTHING;
