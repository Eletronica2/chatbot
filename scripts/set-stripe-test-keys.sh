#!/usr/bin/env bash
# Grava as credenciais Stripe TEST em /opt/atende-ai/.env.production sem exibi-las.
# - Lê os valores com entrada oculta (não ficam no histórico do shell nem na linha de comando).
# - Aceita somente chaves de TESTE (sk_test_/rk_test_ e whsec_) e fixa STRIPE_ALLOW_LIVE=false.
# - Faz backup protegido (600) do arquivo antes de alterar.
set -euo pipefail
ENV_FILE="${ENV_FILE:-/opt/atende-ai/.env.production}"
umask 077

[[ -f "$ENV_FILE" ]] || { echo "Arquivo não encontrado: $ENV_FILE"; exit 1; }

read -rsp "Cole a STRIPE_SECRET_KEY (sk_test_...) e tecle Enter: " STRIPE_SK; echo
read -rsp "Cole o STRIPE_WEBHOOK_SECRET (whsec_...) e tecle Enter: " STRIPE_WH; echo

case "$STRIPE_SK" in
  sk_test_*|rk_test_*) ;;
  *) echo "Recusado: a chave secreta precisa ser de TESTE (sk_test_...). Nada foi alterado."; exit 1 ;;
esac
case "$STRIPE_WH" in
  whsec_*) ;;
  *) echo "Recusado: o segredo do webhook precisa começar com whsec_. Nada foi alterado."; exit 1 ;;
esac

backup="$ENV_FILE.bak-stripe-$(date -u +%Y%m%dT%H%M%SZ)"
cp -p "$ENV_FILE" "$backup"
chmod 600 "$backup"

STRIPE_SK="$STRIPE_SK" STRIPE_WH="$STRIPE_WH" python3 - "$ENV_FILE" <<'PY'
import os
import sys

path = sys.argv[1]
values = {
    "STRIPE_SECRET_KEY": os.environ["STRIPE_SK"],
    "STRIPE_WEBHOOK_SECRET": os.environ["STRIPE_WH"],
    "STRIPE_ALLOW_LIVE": "false",
}
with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines()
out, seen = [], set()
for line in lines:
    key = line.split("=", 1)[0].strip()
    if key in values:
        if key not in seen:
            out.append(f"{key}={values[key]}")
            seen.add(key)
        continue
    out.append(line)
out.extend(f"{key}={value}" for key, value in values.items() if key not in seen)
with open(path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
PY
chmod 600 "$ENV_FILE"
unset STRIPE_SK STRIPE_WH
echo "OK: credenciais TEST gravadas em $ENV_FILE (valores não exibidos). STRIPE_ALLOW_LIVE=false."
echo "Backup protegido: $backup"
