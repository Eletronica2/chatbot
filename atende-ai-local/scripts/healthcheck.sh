#!/usr/bin/env bash
# Liveness + readiness + container health + published ports. Exit 1 if not ready.
set -uo pipefail
cd "$(dirname "$0")/.."

echo "== containers"
docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
echo "== /health"
curl -s -m 5 http://127.0.0.1:8100/health; echo
echo "== /ready"
ready=$(curl -s -m 60 http://127.0.0.1:8100/ready)
echo "$ready" | jq .
echo "== portas em escuta (host)"
ss -tln | awk 'NR==1 || /:8100|:11434|:6333|:6334/'
echo "$ready" | jq -e '.ready == true' >/dev/null
