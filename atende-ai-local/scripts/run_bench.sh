#!/usr/bin/env bash
# Run one local-AI benchmark safely on the AI server:
#   - one at a time (flock): concurrent benchmarks change Ollama runner options and evict each other's KV cache;
#   - bounded by timeouts outside and inside the container (no orphan python processes);
#   - always restarts ai-api at the end: benchmarks use Ollama directly, so the API's record of what is cached would
#     be stale and the next customer message could pay a cold prompt. The restart re-runs the staged warm-up.
# Usage (on the server, from /opt/atende-ai-local):
#   scripts/run_bench.sh ai-api/bench/context_bench.py full:concise full   > /tmp/bench.out
set -uo pipefail
script=${1:?bench script}; shift
cd "$(dirname "$0")/.."
exec 9>/tmp/atende-bench.lock
flock -n 9 || { echo "outro benchmark em andamento" >&2; exit 2; }
timeout 1500 docker compose exec -T -w /srv ai-api timeout 1450 python - "$@" < "$script"
rc=$?
timeout 120 docker compose restart ai-api >/dev/null 2>&1 || echo "AVISO: falha ao reiniciar ai-api" >&2
echo "bench rc=$rc; ai-api reiniciado (warm-up em andamento)" >&2
exit $rc
