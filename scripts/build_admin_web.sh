#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-}"
ALLOW_LOCALHOST_IN_RELEASE="${ALLOW_LOCALHOST_IN_RELEASE:-}"

# Release web: produção por padrão (dev local: API_BASE_URL=http://localhost:8000 ./scripts/build_admin_web.sh)
API_BASE_URL="${API_BASE_URL:-https://api.meuatendeai.com.br}"

if [[ -z "$FLUTTER_BIN" ]]; then
  for candidate in flutter "$HOME/flutter/bin/flutter" /home/arthur/flutter/bin/flutter; do
    if command -v "$candidate" >/dev/null 2>&1; then
      FLUTTER_BIN="$(command -v "$candidate" 2>/dev/null || true)"
    fi
    if [[ -x "$candidate" ]]; then
      FLUTTER_BIN="$candidate"
      break
    fi
  done
fi

if [[ -z "${FLUTTER_BIN:-}" || ! -x "$FLUTTER_BIN" ]]; then
  echo "flutter not found" >&2
  exit 1
fi

case "$API_BASE_URL" in
  *localhost*|*127.0.0.1*)
    if [[ -z "$ALLOW_LOCALHOST_IN_RELEASE" ]]; then
      echo "refuse release build with local API URL: $API_BASE_URL" >&2
      echo "use API_BASE_URL=https://api.meuatendeai.com.br or ALLOW_LOCALHOST_IN_RELEASE=1" >&2
      exit 1
    fi
    ;;
esac

cd "$ROOT/admin-panel"
"$FLUTTER_BIN" build web --release --dart-define=API_BASE_URL="$API_BASE_URL"
echo "Built admin-panel/build/web with API_BASE_URL=$API_BASE_URL"

OUT="$ROOT/admin-panel/build/web/main.dart.js"
if [[ ! -f "$OUT" ]]; then
  echo "missing $OUT" >&2
  exit 1
fi
if [[ -z "$ALLOW_LOCALHOST_IN_RELEASE" ]]; then
  if grep -qE 'localhost:8000|127\.0\.0\.1:8000' "$OUT"; then
    echo "release bundle still references local API — aborting deploy" >&2
    exit 1
  fi
  if ! grep -q 'api.meuatendeai.com.br' "$OUT"; then
    echo "release bundle missing api.meuatendeai.com.br — aborting" >&2
    exit 1
  fi
fi