#!/usr/bin/env bash
# Sobe a stack local, o painel Flutter e os túneis Cloudflare, depois imprime as URLs.
# Ctrl+C encerra túneis e o painel. O Docker permanece no ar (o volume MySQL não é apagado).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$ROOT/.run"
LOG_DIR="$RUN_DIR/logs"
mkdir -p "$LOG_DIR"

GATEWAY_PORT=40000
ADMIN_PORT=4173
BACKEND_PORT=8000

SKIP_BUILD="${SKIP_BUILD:-0}"
SKIP_FLUTTER="${SKIP_FLUTTER:-0}"

PIDS=()

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "comando não encontrado: $1"
}

ensure_flutter() {
  if command -v flutter >/dev/null 2>&1; then
    return 0
  fi
  local candidate
  for candidate in \
    "${FLUTTER_ROOT:-}/bin/flutter" \
    "$HOME/flutter/bin/flutter" \
    /home/arthur/flutter/bin/flutter \
    /opt/flutter/bin/flutter \
    /usr/local/flutter/bin/flutter
  do
    if [[ -x "$candidate" ]]; then
      export PATH="$(dirname "$candidate"):$PATH"
      log "Flutter encontrado em $(dirname "$candidate")"
      return 0
    fi
  done
  die "flutter não está no PATH. Instale o SDK ou rode: export PATH=\"\$HOME/flutter/bin:\$PATH\""
}

cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}

# INT/TERM must exit — otherwise Ctrl+C during flutter build leaves an incomplete
# build/web and the script continues serving a blank admin panel.
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

wait_http() {
  local url="$1"
  local name="$2"
  local tries="${3:-60}"
  local i
  for ((i = 1; i <= tries; i++)); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      printf '    %s ok (%s)\n' "$name" "$url"
      return 0
    fi
    sleep 2
  done
  die "$name não respondeu em $url"
}

wait_tunnel_url() {
  local logfile="$1"
  local tries=45
  local i url
  for ((i = 1; i <= tries; i++)); do
    url="$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$logfile" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$url" ]]; then
      printf '%s' "$url"
      return 0
    fi
    sleep 1
  done
  return 1
}

need docker
need curl
need cloudflared

if ! docker compose version >/dev/null 2>&1; then
  die "Docker Compose v2 não está disponível (docker compose)"
fi

log "Subindo Docker (infra)"
cd "$ROOT/infra"
if [[ "$SKIP_BUILD" == "1" ]]; then
  docker compose up -d
else
  docker compose up --build -d
fi

log "Aguardando healthchecks"
wait_http "http://127.0.0.1:${BACKEND_PORT}/health" "backend-api"
wait_http "http://127.0.0.1:8002/health" "flow-engine"
wait_http "http://127.0.0.1:8003/health" "ai-engine"
wait_http "http://127.0.0.1:${GATEWAY_PORT}/health" "whatsapp-gateway"

log "Abrindo túnel Cloudflare do WhatsApp Gateway (:${GATEWAY_PORT})"
cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${GATEWAY_PORT}" \
  >"$LOG_DIR/tunnel-gateway.log" 2>&1 &
PIDS+=("$!")

log "Abrindo túnel Cloudflare da API (:${BACKEND_PORT})"
cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${BACKEND_PORT}" \
  >"$LOG_DIR/tunnel-api.log" 2>&1 &
PIDS+=("$!")

GATEWAY_PUBLIC=""
if ! GATEWAY_PUBLIC="$(wait_tunnel_url "$LOG_DIR/tunnel-gateway.log")"; then
  die "não foi possível ler a URL do túnel do gateway. Veja $LOG_DIR/tunnel-gateway.log"
fi

API_PUBLIC=""
if ! API_PUBLIC="$(wait_tunnel_url "$LOG_DIR/tunnel-api.log")"; then
  die "não foi possível ler a URL do túnel da API. Veja $LOG_DIR/tunnel-api.log"
fi

ADMIN_LOCAL="http://127.0.0.1:${ADMIN_PORT}"
ADMIN_PUBLIC=""
if [[ "$SKIP_FLUTTER" != "1" ]]; then
  ensure_flutter
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${ADMIN_PORT}/tcp" >/dev/null 2>&1 || true
    sleep 1
  fi

  log "Gerando Admin Panel (release) apontando a API para o túnel HTTPS"
  if ! (
    cd "$ROOT/admin-panel"
    flutter build web --release --no-tree-shake-icons --no-wasm-dry-run \
      --dart-define="API_BASE_URL=${API_PUBLIC}"
  ) >"$LOG_DIR/flutter.log" 2>&1; then
    die "flutter build web falhou. Veja $LOG_DIR/flutter.log"
  fi
  if [[ ! -f "$ROOT/admin-panel/build/web/main.dart.js" ]]; then
    die "build incompleto: falta main.dart.js em admin-panel/build/web (veja $LOG_DIR/flutter.log)"
  fi
  if [[ ! -f "$ROOT/admin-panel/build/web/flutter_bootstrap.js" ]]; then
    die "build incompleto: falta flutter_bootstrap.js"
  fi

  log "Servindo build estático em :${ADMIN_PORT}"
  (
    cd "$ROOT/admin-panel/build/web"
    exec python3 -m http.server "$ADMIN_PORT" --bind 127.0.0.1
  ) >"$LOG_DIR/admin-static.log" 2>&1 &
  PIDS+=("$!")
  wait_http "$ADMIN_LOCAL" "admin-panel" 30
  if ! curl -fsS "$ADMIN_LOCAL/main.dart.js" >/dev/null 2>&1; then
    die "admin-panel respondeu, mas main.dart.js não está acessível em :${ADMIN_PORT}"
  fi

  log "Abrindo túnel Cloudflare do Admin Panel (:${ADMIN_PORT})"
  cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${ADMIN_PORT}" \
    >"$LOG_DIR/tunnel-admin.log" 2>&1 &
  PIDS+=("$!")
  if ! ADMIN_PUBLIC="$(wait_tunnel_url "$LOG_DIR/tunnel-admin.log")"; then
    printf 'aviso: túnel do painel não ficou pronto. Veja %s\n' "$LOG_DIR/tunnel-admin.log" >&2
  fi
fi

cat <<EOF

============================================================
  Atende Ai — ambiente online
============================================================

  Local
    Backend API:       http://127.0.0.1:${BACKEND_PORT}
    Flow Engine:       http://127.0.0.1:8002
    AI Engine:         http://127.0.0.1:8003
    WhatsApp Gateway:  http://127.0.0.1:${GATEWAY_PORT}
    Admin Panel:       ${ADMIN_LOCAL}

  Público (Cloudflare trycloudflare)
    Gateway:           ${GATEWAY_PUBLIC}
    Webhook (Meta):    ${GATEWAY_PUBLIC}/webhook
    Data deletion:     ${GATEWAY_PUBLIC}/api/v1/meta/data-deletion
    Backend API:       ${API_PUBLIC}
    Admin Panel:       ${ADMIN_PUBLIC:-não iniciado}

  Logs
    $LOG_DIR/flutter.log
    $LOG_DIR/admin-static.log
    $LOG_DIR/tunnel-gateway.log
    $LOG_DIR/tunnel-api.log
    $LOG_DIR/tunnel-admin.log

  Ctrl+C encerra túneis e o servidor do painel. Docker continua rodando.
  SKIP_BUILD=1  — não reconstrói imagens Docker
  SKIP_FLUTTER=1 — só Docker + túnel do gateway

============================================================

EOF

log "Túneis ativos. Aguardando (Ctrl+C para sair)..."
wait
