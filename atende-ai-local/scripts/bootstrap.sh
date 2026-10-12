#!/usr/bin/env bash
# Idempotent bootstrap: secrets (local only), models, embedding cache, stack up.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077

MODELS=("qwen3:1.7b-q4_K_M" "qwen3:4b-instruct-2507-q4_K_M")
EMBEDDINGS=("google/embeddinggemma-2" "intfloat/multilingual-e5-small")

if [[ ! -f .env ]]; then
  cp .env.example .env
  sed -i "s/^QDRANT_API_KEY=.*/QDRANT_API_KEY=$(openssl rand -hex 32)/" .env
  echo "[bootstrap] .env criado"
fi
chmod 600 .env

mkdir -p secrets config
if [[ ! -f config/credentials.json ]]; then
  declare -A SPEC=(
    [TOKEN_BELLA]='bella-svc|pizzaria_bella_massa|respond,knowledge:read,knowledge:write'
    [TOKEN_ZE]='ze-svc|pastelaria_do_ze|respond,knowledge:read,knowledge:write'
    [TOKEN_BELLA_RO]='bella-readonly|pizzaria_bella_massa|respond,knowledge:read'
    [TOKEN_MULTI]='multi-test|pizzaria_bella_massa,pastelaria_do_ze|respond,knowledge:read'
  )
  : > secrets/tokens.env
  entries=()
  for name in "${!SPEC[@]}"; do
    IFS='|' read -r key tenants scopes <<< "${SPEC[$name]}"
    tok=$(openssl rand -hex 32)
    echo "${name}=${tok}" >> secrets/tokens.env
    sha=$(printf '%s' "$tok" | sha256sum | cut -d' ' -f1)
    entries+=("{\"key_id\":\"$key\",\"token_sha256\":\"$sha\",\"tenants\":$(jq -cn --arg t "$tenants" '$t|split(",")'),\"scopes\":$(jq -cn --arg s "$scopes" '$s|split(",")')}")
  done
  printf '{"credentials":[%s]}\n' "$(IFS=,; echo "${entries[*]}")" | jq . > config/credentials.json
  chmod 600 secrets/tokens.env
  chmod 644 config/credentials.json
  echo "[bootstrap] credenciais de teste geradas (tokens em secrets/tokens.env, somente hashes em config/)"
fi

docker compose up -d ollama qdrant
for m in "${MODELS[@]}"; do
  docker compose exec -T ollama ollama pull "$m"
done

docker compose build ai-api
for e in "${EMBEDDINGS[@]}"; do
  docker compose run --rm --no-deps -e HF_HUB_OFFLINE=0 ai-api \
    python -c "from huggingface_hub import snapshot_download as d; print(d('$e', ignore_patterns=['onnx/*', 'openvino/*', '*.bin', '*.onnx']))"
done

docker compose up -d ai-api
echo "[bootstrap] ok"
