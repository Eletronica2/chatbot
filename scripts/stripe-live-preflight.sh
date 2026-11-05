#!/usr/bin/env bash
# Verificação SOMENTE LEITURA das credenciais LIVE guardadas, num contêiner temporário.
# Não altera .env.production, não reinicia o backend, não cria cliente/checkout/assinatura.
set -euo pipefail
DIR=/opt/atende-ai
cd "$DIR"
[[ -f .env.stripe-live ]] || { echo "Rode antes: bash $DIR/scripts/stage-stripe-live-keys.sh"; exit 1; }
DC="docker compose -p atende-prod --env-file .env.production -f docker-compose.production.yml"
(
  set -a; . ./.env.stripe-live; set +a
  $DC run --rm --no-deps -T -e STRIPE_SECRET_KEY -e STRIPE_WEBHOOK_SECRET -e STRIPE_ALLOW_LIVE=false \
    --entrypoint python backend-api - --live-preflight < backend-api/scripts/stripe_test_check.py 2>&1 | grep -v "HTTP Request"
)
