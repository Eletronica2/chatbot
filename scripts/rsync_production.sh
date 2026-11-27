#!/usr/bin/env bash
# Rsync código para EC2 sem copiar segredos locais (.env, credenciais).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="${REMOTE:-ec2-user@3.218.194.130}"
REMOTE_DIR="${REMOTE_DIR:-/opt/atende-ai}"
SSH_KEY="${SSH_KEY:-$HOME/Downloads/atendeai.pem}"
RSYNC_SSH="ssh -i $SSH_KEY"

RSYNC_EXCLUDES=(
  --exclude '.git/'
  --exclude '**/__pycache__/'
  --exclude '**/.pytest_cache/'
  --exclude '**/.venv/'
  --exclude '**/node_modules/'
  --exclude '.env'
  --exclude '.env.local'
  --exclude '.env.production'
  --exclude '.env.development'
  --exclude '.env.*.local'
  --exclude '**/.env'
  --exclude '**/.env.local'
  --exclude '**/.env.production'
  --exclude '**/.env.development'
  --exclude '**/credentials.json'
  --exclude '**/*-credentials*.json'
  --exclude '**/*.pem'
  --exclude '**/*.key'
  --exclude 'admin-panel/build/'
)

usage() {
  echo "Usage: $0 backend-api|whatsapp-gateway|admin-web" >&2
  exit 1
}

echo "rsync_production: publishing $target from HEAD (clean worktree)"

WORK="$(mktemp -d)"
cleanup() {
  git -C "$ROOT" worktree remove --force "$WORK" >/dev/null 2>&1 || rm -rf "$WORK"
}
trap cleanup EXIT
git -C "$ROOT" worktree add --detach "$WORK" HEAD >/dev/null

target="${1:-}"
case "$target" in
  backend-api)
    rsync -avz "${RSYNC_EXCLUDES[@]}" -e "$RSYNC_SSH" \
      "$WORK/backend-api/" "$REMOTE:$REMOTE_DIR/backend-api/"
    ;;
  whatsapp-gateway)
    rsync -avz "${RSYNC_EXCLUDES[@]}" -e "$RSYNC_SSH" \
      "$WORK/whatsapp-gateway/" "$REMOTE:$REMOTE_DIR/whatsapp-gateway/"
    ;;
  admin-web)
    API_BASE_URL="${API_BASE_URL:-https://api.meuatendeai.com.br}" \
      "$WORK/scripts/build_admin_web.sh"
    rsync -avz --delete -e "$RSYNC_SSH" \
      "$WORK/admin-panel/build/web/" "$REMOTE:$REMOTE_DIR/admin-panel/build/web/"
    ;;
  *)
    usage
    ;;
esac

echo "rsync_production: $target OK (secrets excluded)"