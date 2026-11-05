#!/usr/bin/env bash
# Guarda as credenciais Stripe LIVE em /opt/atende-ai/.env.stripe-live (600), com entrada oculta.
# NÃO altera .env.production nem reinicia nada. Na primeira execução também guarda o backup TEST
# (.env.stripe-test, 600) a partir da configuração ativa. Nenhum valor é exibido.
set -euo pipefail
DIR=/opt/atende-ai
ENV_FILE="$DIR/.env.production"
LIVE_FILE="$DIR/.env.stripe-live"
TEST_FILE="$DIR/.env.stripe-test"
umask 077

if [[ ! -f "$TEST_FILE" ]]; then
  grep -E '^(STRIPE_SECRET_KEY|STRIPE_WEBHOOK_SECRET)=' "$ENV_FILE" > "$TEST_FILE.tmp"
  if ! grep -qE '^STRIPE_SECRET_KEY=(sk|rk)_test_' "$TEST_FILE.tmp"; then
    rm -f "$TEST_FILE.tmp"; echo "Recusado: a configuração ativa não é TEST; backup TEST não criado."; exit 1
  fi
  chmod 600 "$TEST_FILE.tmp"; mv "$TEST_FILE.tmp" "$TEST_FILE"
  echo "Backup da configuração TEST: $TEST_FILE"
fi
TEST_WH="$(sed -n 's/^STRIPE_WEBHOOK_SECRET=//p' "$TEST_FILE")"

read -rsp "Cole a chave LIVE (sk_live_... ou rk_live_...) e tecle Enter: " LIVE_SK; echo
read -rsp "Cole o segredo do webhook LIVE (whsec_...) e tecle Enter: " LIVE_WH; echo
case "$LIVE_SK" in sk_live_*|rk_live_*) ;; *) echo "Recusado: a chave precisa ser LIVE. Nada foi gravado."; exit 1 ;; esac
case "$LIVE_WH" in whsec_*) ;; *) echo "Recusado: o segredo precisa começar com whsec_. Nada foi gravado."; exit 1 ;; esac
if [[ "$LIVE_WH" == "$TEST_WH" ]]; then echo "Recusado: este whsec é o do webhook TEST. Use o do webhook LIVE."; exit 1; fi

printf 'STRIPE_SECRET_KEY=%s\nSTRIPE_WEBHOOK_SECRET=%s\n' "$LIVE_SK" "$LIVE_WH" > "$LIVE_FILE.tmp"
chmod 600 "$LIVE_FILE.tmp"; mv "$LIVE_FILE.tmp" "$LIVE_FILE"
unset LIVE_SK LIVE_WH TEST_WH
echo "OK: credenciais LIVE guardadas em $LIVE_FILE (valores não exibidos). Nada foi ativado."
