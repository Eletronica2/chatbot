#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env.production"
CERTBOT_EMAIL_FILE="$ROOT/.certbot-email"

umask 077

if [[ -e "$ENV_FILE" ]]; then
  echo "Refusing to overwrite existing $ENV_FILE" >&2
  exit 1
fi

read -r -p "Administrative email (superadmin): " admin_email
read -r -p "Superadmin display name [Superadmin]: " admin_name
admin_name="${admin_name:-Superadmin}"
read -r -p "Let's Encrypt administrative email: " certbot_email
read -r -s -p "New strong superadmin password: " admin_password
printf '\n'
read -r -s -p "Repeat superadmin password: " admin_password_confirm
printf '\n'
read -r -s -p "Production Gemini API key: " gemini_api_key
printf '\n'

if [[ -z "$admin_email" || -z "$certbot_email" || -z "$admin_password" || -z "$gemini_api_key" ]]; then
  echo "Email, password and Gemini key are required." >&2
  exit 1
fi

if [[ "$admin_password" != "$admin_password_confirm" ]]; then
  echo "Passwords do not match." >&2
  exit 1
fi

if (( ${#admin_password} < 16 )); then
  echo "Superadmin password must contain at least 16 characters." >&2
  exit 1
fi

for value in "$admin_email" "$admin_name" "$certbot_email" "$admin_password" "$gemini_api_key"; do
  if [[ "$value" == *"'"* || "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "Values cannot contain single quotes or line breaks." >&2
    exit 1
  fi
done

mysql_root_password="$(openssl rand -hex 32)"
mysql_password="$(openssl rand -hex 32)"
app_secret_key="$(openssl rand -hex 48)"
internal_api_key="$(openssl rand -hex 32)"
meta_verify_token="$(openssl rand -hex 32)"
env_tmp="$(mktemp "$ROOT/.env.production.tmp.XXXXXX")"
trap 'rm -f -- "$env_tmp"' EXIT

{
  printf "APP_DOMAIN='meuatendeai.com.br'\n"
  printf "ADMIN_PANEL_URL='https://painel.meuatendeai.com.br'\n"
  printf "CORS_ORIGINS='https://painel.meuatendeai.com.br,https://meuatendeai.com.br'\n"
  printf "MYSQL_ROOT_PASSWORD='%s'\n" "$mysql_root_password"
  printf "MYSQL_DATABASE='atenda'\n"
  printf "MYSQL_USER='atenda'\n"
  printf "MYSQL_PASSWORD='%s'\n" "$mysql_password"
  printf "APP_SECRET_KEY='%s'\n" "$app_secret_key"
  printf "INTERNAL_API_KEY='%s'\n" "$internal_api_key"
  printf "META_VERIFY_TOKEN='%s'\n" "$meta_verify_token"
  printf "DEFAULT_ADMIN_EMAIL='%s'\n" "$admin_email"
  printf "DEFAULT_ADMIN_PASSWORD='%s'\n" "$admin_password"
  printf "DEFAULT_ADMIN_NAME='%s'\n" "$admin_name"
  printf "BOOTSTRAP_DEMO_DATA='false'\n"
  printf "AI_PROVIDER='gemini'\n"
  printf "GEMINI_API_KEY='%s'\n" "$gemini_api_key"
  printf "MOCK_AI='false'\n"
  printf "META_APP_ID=''\nMETA_APP_SECRET=''\nMETA_SYSTEM_USER_TOKEN=''\nMETA_EMBEDDED_CONFIG_ID=''\n"
  printf "META_API_VERSION='v22.0'\n"
  printf "META_DATA_DELETION_BASE_URL='https://api.meuatendeai.com.br/api/v1/meta/data-deletion/status'\n"
  printf "STRIPE_SECRET_KEY=''\nSTRIPE_WEBHOOK_SECRET=''\n"
  printf "STRIPE_PRICE_STARTER=''\nSTRIPE_PRICE_GROWTH=''\nSTRIPE_PRICE_PRO=''\nSTRIPE_PRICE_ENTERPRISE=''\n"
  printf "BILLING_SUCCESS_URL='https://painel.meuatendeai.com.br/#/billing/success?session_id={CHECKOUT_SESSION_ID}'\n"
  printf "BILLING_CANCEL_URL='https://painel.meuatendeai.com.br/#/billing/cancel'\n"
  printf "BILLING_PORTAL_RETURN_URL='https://painel.meuatendeai.com.br/#/billing'\n"
  printf "SMTP_HOST=''\nSMTP_PORT='587'\nSMTP_USERNAME=''\nSMTP_PASSWORD=''\n"
  printf "SMTP_FROM_EMAIL='no-reply@meuatendeai.com.br'\n"
} >"$env_tmp"

chmod 600 "$env_tmp"
mv -- "$env_tmp" "$ENV_FILE"
printf '%s\n' "$certbot_email" >"$CERTBOT_EMAIL_FILE"
chmod 600 "$CERTBOT_EMAIL_FILE"
trap - EXIT

unset admin_password admin_password_confirm gemini_api_key mysql_root_password \
  mysql_password app_secret_key internal_api_key meta_verify_token

echo "Production environment created with mode 600. No secret was displayed."
