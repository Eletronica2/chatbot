#!/usr/bin/env bash
# Troca as credenciais Stripe de /opt/atende-ai/.env.production e recria SOMENTE o backend-api.
#   stripe-mode.sh live               chaves LIVE com STRIPE_ALLOW_LIVE=false (nada é cobrado; checkout recusado)
#   stripe-mode.sh live --allow-live  chaves LIVE com STRIPE_ALLOW_LIVE=true (cobrança real; só com autorização)
#   stripe-mode.sh test               rollback para as chaves TEST (STRIPE_ALLOW_LIVE=false)
# Faz backup (600) antes; se o backend não ficar saudável, restaura sozinho. Nenhum valor é exibido.
set -euo pipefail
DIR=/opt/atende-ai
ENV_FILE="$DIR/.env.production"
umask 077
ALLOW=false
case "${1:-}" in
  live) SRC="$DIR/.env.stripe-live"; [[ "${2:-}" == "--allow-live" ]] && ALLOW=true ;;
  test) SRC="$DIR/.env.stripe-test" ;;
  *) echo "uso: $0 live [--allow-live] | test"; exit 2 ;;
esac
[[ -f "$SRC" ]] || { echo "Arquivo ausente: $SRC"; exit 1; }

BACKUP="$ENV_FILE.bak-mode-$(date -u +%Y%m%dT%H%M%SZ)"
cp -p "$ENV_FILE" "$BACKUP"; chmod 600 "$BACKUP"
python3 - "$ENV_FILE" "$SRC" "$ALLOW" <<'PY'
import sys

env_path, src_path, allow = sys.argv[1:4]
src = dict(line.split("=", 1) for line in open(src_path, encoding="utf-8").read().splitlines() if "=" in line)
values = {key: src[key] for key in ("STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET")}
values["STRIPE_ALLOW_LIVE"] = allow
out, seen = [], set()
for line in open(env_path, encoding="utf-8").read().splitlines():
    key = line.split("=", 1)[0].strip()
    if key in values:
        if key not in seen:
            out.append(f"{key}={values[key]}")
            seen.add(key)
        continue
    out.append(line)
out.extend(f"{key}={value}" for key, value in values.items() if key not in seen)
open(env_path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
chmod 600 "$ENV_FILE"

cd "$DIR"
DC="docker compose -p atende-prod --env-file .env.production -f docker-compose.production.yml"
$DC up -d --no-deps backend-api >/dev/null 2>&1
st=none
for _ in $(seq 1 30); do
  st=$(docker inspect -f '{{.State.Health.Status}}' "$($DC ps -q backend-api)")
  [[ "$st" == healthy ]] && break
  sleep 5
done
if [[ "$st" != healthy ]]; then
  cp -p "$BACKUP" "$ENV_FILE"; $DC up -d --no-deps backend-api >/dev/null 2>&1
  echo "FALHA: backend não ficou saudável; configuração anterior restaurada ($BACKUP)."; exit 1
fi
$DC exec -T backend-api python -c "from app.config.settings import settings as s; k=s.STRIPE_SECRET_KEY; print('ativo:', 'LIVE' if k.startswith(('sk_live_','rk_live_')) else 'TEST', '| STRIPE_ALLOW_LIVE:', s.STRIPE_ALLOW_LIVE)"
echo "Backup anterior: $BACKUP"
