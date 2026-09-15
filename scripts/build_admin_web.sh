#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_BASE_URL="${API_BASE_URL:-http://localhost:8000}"
FLUTTER_BIN="${FLUTTER_BIN:-}"

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

cd "$ROOT/admin-panel"
"$FLUTTER_BIN" build web --release --dart-define=API_BASE_URL="$API_BASE_URL"
echo "Built admin-panel/build/web with API_BASE_URL=$API_BASE_URL"
