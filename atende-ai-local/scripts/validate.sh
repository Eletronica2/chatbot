#!/usr/bin/env bash
# Post-restart/post-reboot validation: services, readiness, Qdrant persistence, retrieval and a real LLM answer.
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; source secrets/tokens.env; set +a
fail=0
ok() { echo "PASS | $*"; }
ko() { echo "FAIL | $*"; fail=1; }

echo "== $(date -Is) uptime: $(uptime -p)"
systemctl is-active docker >/dev/null && ok "docker ativo ($(docker --version | cut -d, -f1))" || ko "docker inativo"
for i in $(seq 1 90); do curl -sf -m 3 http://127.0.0.1:8100/health >/dev/null && break; sleep 4; done
docker compose ps --format '{{.Service}} {{.Status}}' | sed 's/^/     /'
ready=$(curl -s -m 120 http://127.0.0.1:8100/ready)
echo "$ready" | jq -e '.ready == true' >/dev/null && ok "/ready = true ($(echo "$ready" | jq -c '[.checks | to_entries[] | "\(.key)=\(.value.ok)"]'))" || ko "/ready: $ready"

h=(-H "Authorization: Bearer $TOKEN_BELLA" -H 'Content-Type: application/json')
s=$(curl -s -m 60 "${h[@]}" http://127.0.0.1:8100/v1/knowledge/search -d '{"query":"meio a meio","top_k":3}')
n=$(echo "$s" | jq '.results | length'); sec=$(echo "$s" | jq -r '.results[0].section')
[[ "$n" -ge 1 ]] && ok "Qdrant persistente: busca Bella retornou $n chunks (top1: $sec)" || ko "busca vazia: $s"
z=$(curl -s -m 60 -H "Authorization: Bearer $TOKEN_ZE" -H 'Content-Type: application/json' http://127.0.0.1:8100/v1/knowledge/search -d '{"query":"pastel de carne","top_k":3}')
echo "$z" | jq -e '[.results[].tenant_id] | all(. == "pastelaria_do_ze") and length > 0' >/dev/null \
  && ok "isolamento: busca Zé retorna só pastelaria_do_ze" || ko "isolamento Zé: $z"

req='{"request_id":"validate-'$(date +%s)'","message":"vcs fazem pizza meio a meio?","options":{"allow_deterministic":false},
 "business_context":'"$(cat ai-api/fixtures/pizzaria_bella_massa/business_context.json)"'}'
r=$(curl -s -m 300 "${h[@]}" http://127.0.0.1:8100/v1/respond -d "$req")
echo "$r" | jq -c '{text, level, model, usage, latency_ms, load_ms: .timings.load_ms, tps: .timings.tokens_per_s}'
echo "$r" | jq -e '.model != null and .usage.completion_tokens > 0' >/dev/null && ok "modelo carregável e inferência real" || ko "inferência: $r"
df -h / | awk 'NR==2{print "     filesystem /: " $2 " total, " $4 " livres"}'
[[ $(df -BG --output=size / | tail -1 | tr -dc 0-9) -gt 250 ]] && ok "filesystem expandido" || ko "filesystem não expandido"
exit $fail
