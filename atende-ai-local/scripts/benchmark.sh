#!/usr/bin/env bash
# Runs benchmarks inside the ai-api container while sampling docker stats on the host.
# Usage: scripts/benchmark.sh <models|embeddings|ptbr|security|concurrency> [args...]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${OUT:-./bench-results}
mkdir -p "$OUT"
kind=$1; shift
ts=$(date +%Y%m%d-%H%M%S)
tag="${kind}-$(echo "$*" | tr ' :/,' '____')-$ts"

( while true; do
    docker stats --no-stream --format '{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}' | sed "s/^/$(date +%T) /"
    free -m | awk '/Mem:/{print strftime("%T"), "host_used_mb=" $3, "host_avail_mb=" $7} /Swap:/{print strftime("%T"), "swap_used_mb=" $3}'
    sleep 5
  done ) > "$OUT/$tag.stats.txt" 2>&1 &
sampler=$!
trap 'kill $sampler 2>/dev/null' EXIT

envs=()
while IFS= read -r line; do [[ -n "$line" ]] && envs+=(-e "$line"); done < secrets/tokens.env

if curl -sf -m 3 http://127.0.0.1:8100/health >/dev/null; then
  run=(docker compose exec -T)
else
  run=(docker compose run --rm --no-deps -T)
fi

case "$kind" in
  models)      "${run[@]}" ai-api python -m bench.model_bench "$@" ;;
  embeddings)  "${run[@]}" -e HF_HUB_OFFLINE=1 ai-api python -m bench.embeddings_bench "$@" ;;
  ptbr)        "${run[@]}" "${envs[@]}" ai-api python -m bench.ptbr_bench "$@" ;;
  security)    "${run[@]}" "${envs[@]}" ai-api python -m bench.security_tests "$@" ;;
  concurrency) "${run[@]}" "${envs[@]}" ai-api python -m bench.concurrency_bench "$@" ;;
  rag)         "${run[@]}" "${envs[@]}" ai-api python -m bench.rag_eval "$@" ;;
  unit)        "${run[@]}" ai-api python -m pytest -q tests ;;
  seed)        "${run[@]}" "${envs[@]}" ai-api python -c "import json;from bench.common import client,seed;print(json.dumps(seed(client()),ensure_ascii=False))" ;;
  *) echo "tipo desconhecido: $kind"; exit 2 ;;
esac > "$OUT/$tag.json" 2> "$OUT/$tag.err"
echo "$OUT/$tag.json"
