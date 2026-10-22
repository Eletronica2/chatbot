#!/usr/bin/env bash
# IA-03 — sanitized end-to-end trace of the Bella Massa pilot since a UTC instant.
# Usage: scripts/ia03_bella_monitor.sh "2026-10-22 02:00:00"
# Prints events from Gateway, Backend, AI Engine, local API, WireGuard and the DB (messages + billing) for tenant 5.
# Phone numbers are masked; tokens, secrets and message bodies are never printed.
set -uo pipefail
SINCE=${1:?informe o instante UTC inicial, ex.: "2026-10-22 02:00:00"}
AWS=(ssh -i "$HOME/Downloads/atendeai.pem" -o IdentitiesOnly=yes -o BatchMode=yes -o LogLevel=ERROR ec2-user@3.218.194.130)
LOCAL=(ssh -i "$HOME/.ssh/id_ed25519_atendeai" -o IdentitiesOnly=yes -o BatchMode=yes -o LogLevel=ERROR atendeai@192.168.0.50)
MASK='s/(55[0-9]{2})[0-9]{5}([0-9]{4})/\1*****\2/g; s/(access_token|secret_b64|signature|verify_token)[=:][^ ,]*/\1=***/Ig'
SINCE_ISO=$(date -u -d "$SINCE" +%Y-%m-%dT%H:%M:%SZ)

echo "===== AWS: Nginx (entrada do webhook) / Gateway / Backend / AI Engine (desde $SINCE_ISO)"
"${AWS[@]}" "cd /opt/atende-ai; DC='docker compose -p atende-prod --env-file .env.production -f docker-compose.production.yml';
  \$DC logs --since $SINCE_ISO nginx 2>&1 | grep -E 'POST /webhook|connect\\(\\) failed|upstream' | sed -E 's/\"[0-9.]+\"$//' ;
  \$DC logs --since $SINCE_ISO --timestamps whatsapp-gateway 2>&1 | grep -E 'Webhook message metadata|Processing message|forwarded|Reply sent|Failed to send|delivery status|Backend returned|rejected|signature|No WhatsApp account' ;
  \$DC logs --since $SINCE_ISO --timestamps backend-api 2>&1 | grep -E 'Handling message|auto_reply_blocked|billing\\.|Flow engine resolved|Flow unresolved|requires_ai_fallback|AI engine|ERROR|Traceback' ;
  \$DC logs --since $SINCE_ISO --timestamps ai-engine 2>&1 | grep -E 'local_ai_ok|local_ai_failed|local_ai requested|ERROR'" | sed -E "$MASK"

echo "===== Local: API privada (respond) + rede"
"${LOCAL[@]}" "cd /opt/atende-ai-local; docker compose logs --since $SINCE_ISO ai-api 2>&1 | grep '\"event\": \"respond\"' | sed -E 's/.*(\\{.*\\})/\\1/' | python3 -c '
import json, sys
for line in sys.stdin:
    try: d = json.loads(line)
    except ValueError: continue
    print({k: d.get(k) for k in (\"ts\", \"request_id\", \"tenant_id\", \"status\", \"level\", \"model\", \"latency_ms\", \"queue_ms\", \"retrieval_ms\", \"generation_ms\", \"prompt_tokens\", \"completion_tokens\", \"retrieval_count\", \"guard\", \"error_code\")})
'; cat /var/lib/atende-ai/netwatch/netwatch.json 2>/dev/null | tr -d '\\n'; echo"

echo "===== MySQL: mensagens e billing do tenant 5"
"${AWS[@]}" "cd /opt/atende-ai; C=\$(docker compose -p atende-prod --env-file .env.production -f docker-compose.production.yml ps -q mysql); docker exec -i \$C sh -c 'exec mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -t \"\$MYSQL_DATABASE\" 2>/dev/null'" <<SQL
SELECT m.id, m.direction, m.source, LEFT(m.external_message_id, 14) ext, CHAR_LENGTH(m.content) chars,
       JSON_UNQUOTE(JSON_EXTRACT(m.metadata,'$.ai_usage.provider')) provider, JSON_UNQUOTE(JSON_EXTRACT(m.metadata,'$.ai_usage.model')) model,
       JSON_EXTRACT(m.metadata,'$.ai_usage.latency_ms') ai_ms, JSON_UNQUOTE(JSON_EXTRACT(m.metadata,'$.auto_reply_blocked')) blocked, m.created_at
FROM messages m WHERE m.tenant_id=5 AND m.created_at >= '$SINCE' ORDER BY m.id;
SELECT LEFT(id, 8) res, status, entitlement, billing_mode, source_path, LEFT(provider_message_id, 14) wamid, last_provider_status, created_at, accepted_at, finalized_at
FROM billing_reservations WHERE tenant_id=5 AND created_at >= '$SINCE' ORDER BY created_at;
SELECT entry_type, COUNT(*) n FROM billing_ledger WHERE tenant_id=5 AND created_at >= '$SINCE' GROUP BY entry_type;
SELECT status, LEFT(provider_message_id, 14) wamid, error_code, applied, received_at FROM billing_message_status WHERE tenant_id=5 AND received_at >= '$SINCE' ORDER BY id;
SELECT provider, model, input_tokens, output_tokens, created_at FROM ai_usage_events WHERE tenant_id=5 AND created_at >= '$SINCE';
SELECT id, JSON_EXTRACT(context,'$.human_handoff_pending') handoff, JSON_UNQUOTE(JSON_EXTRACT(context,'$.human_handoff_reason')) reason, current_state, assignment_mode, updated_at
FROM sessions WHERE tenant_id=5 AND updated_at >= '$SINCE';
SQL
