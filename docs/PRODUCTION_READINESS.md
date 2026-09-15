# Production Readiness

## Status

**PRODUCTION READINESS PARCIAL — AGUARDANDO ACESSO AWS E SECRETS NOVOS**

A stack de produção foi preparada (Compose, Nginx, backup, env de exemplo, guia EC2). Ainda não declarar pronto para EC2 até:

1. Secrets reais saírem do Git (histórico ainda contém `.env` e tokens).
2. `.env.production` ser preenchido fora do repositório.
3. Build Flutter de release com `API_BASE_URL` público.
4. Health da stack Compose ser validado com o `.env.production` local (sem dados reais).

Nenhuma publicação AWS/DNS/Meta/Stripe foi feita nesta passagem.

## Baseline

- Branch: `main`
- Working tree no início desta passagem: limpo
- Docker, Compose e Flutter disponíveis no host de desenvolvimento
- Portas reais no código (não as históricas 8000/8002/8003/40000):

| Serviço | Porta interna | Público em produção |
| --- | --- | --- |
| Admin Flutter | estático | 80/443 via Nginx |
| Backend API | 8000 | via `api.meuatendeai.com.br` |
| Flow Engine | 8002 | interno |
| AI Engine | 8003 | interno |
| WhatsApp Gateway | 40000 | só `/webhook` via Nginx |
| MySQL | 3306 no container / 3310 no compose de dev | não publicar |

## Architecture

```text
Internet
  └── Nginx (80/443)
        ├── meuatendeai.com.br         → Landing Flutter
        ├── painel.meuatendeai.com.br  → Painel Flutter (SPA hash)
        ├── api.meuatendeai.com.br     → backend-api:8000
        └── api.meuatendeai.com.br/webhook → whatsapp-gateway:40000
              └── backend-api → flow-engine:8002
                            └── ai-engine:8003
                            └── mysql:3306
```

## Services

- `admin-panel` — Flutter Web, rotas em hash (`/#/...`)
- `backend-api` — FastAPI, JWT, bootstrap de schema/tenants
- `flow-engine` — YAML flows
- `ai-engine` — Gemini/OpenAI
- `whatsapp-gateway` — webhook Meta Cloud API
- `mysql:8.4` — utf8mb4

## Dockerfiles

Todos os quatro serviços Python já tinham Dockerfile (python:3.11-slim, user `appuser`, HEALTHCHECK `/health`). Foi adicionado `.dockerignore` para não copiar `.env` para a imagem.

Admin não tem Dockerfile: Nginx serve `admin-panel/build/web`.

## Compose

- Dev existente: `infra/docker-compose.yml` (portas publicadas, seed, senhas de demo)
- Produção: `docker-compose.production.yml` (só `8080:80`, MySQL sem porta pública)

## Environment Variables

Ver `.env.production.example` e `backend-api/.env.example`.

Variáveis novas no backend: `CORS_ORIGINS`, `TRUST_PROXY`.

## Secrets

| Item | Estado |
| --- | --- |
| JWT / APP_SECRET_KEY | default fraco no código; obrigatório via env em produção |
| DB password | compose de dev usa `chatbot`; produção via env |
| META_APP_SECRET | estava no `.env.example` versionado — sanitizado |
| META_SYSTEM_USER_TOKEN | estava no `.env.example` — sanitizado |
| GEMINI_API_KEY | presente em `ai-engine/.env` versionado |
| META_ACCESS_TOKEN | presente em `whatsapp-gateway/.env` versionado |
| Stripe | via env; vazio em dev (`provider_ready` depende da key) |

**P0:** `ai-engine/.env` e `whatsapp-gateway/.env` estavam no Git. Passam a ser ignorados. O histórico Git ainda contém os valores — rotacionar após a conta AWS.

Não imprimir valores neste relatório.

## MySQL

- Versão: 8.4
- Charset: utf8mb4 / utf8mb4_unicode_ci
- Init: `database/schema.sql`
- Bootstrap extra: `backend-api` cria tabelas complementares e tenants demo no startup
- Produção: volume `mysql_data`

## Persistence

Precisa sobreviver a restart: volume MySQL. Tokens WhatsApp ficam no banco. Sem store de sessão em disco no gateway. Flutter JWT em `SharedPreferences` (localStorage web).

## Backups

- `scripts/backup_mysql.sh`
- `scripts/restore_mysql.sh`
- Política inicial: diário, retenção 7 dias (cron na EC2, não configurado agora)

Restore de teste deve usar database temporário (`atenda_restore_*`), nunca o volume ativo.

## Health Checks

| Serviço | Endpoint |
| --- | --- |
| backend-api | `GET /health` |
| flow-engine | `GET /health` |
| ai-engine | `GET /health` |
| whatsapp-gateway | `GET /health` |
| Meta verify | `GET /webhook` |

Compose de produção usa `depends_on` + healthcheck.

## Logging

stdout/stderr + `json-file` 10m × 3. Não há ELK.

Útil: `docker compose -f docker-compose.production.yml logs -f backend-api`

## CORS

Antes: `allow_origins=["*"]` + credentials (inválido no browser).

Agora: `CORS_ORIGINS` (default `*` sem credentials). Produção lista somente `https://painel.meuatendeai.com.br,https://meuatendeai.com.br`.

## Nginx

- Local/stack: `infra/nginx/atenda-ai.local.conf`
- Produção DNS: `infra/nginx/atenda-ai.conf`
- SPA: `try_files $uri $uri/ /index.html` (hash routing Flutter)
- `client_max_body_size 20m`
- Timeout 120s em API/webhook
- Sem WebSocket no produto

## HTTPS

Não emitir certificado agora. Guia em `docs/DEPLOY_AWS_EC2.md` (Certbot).

## Meta

- Webhook: `https://api.meuatendeai.com.br/webhook` → gateway
- Verify token: `META_VERIFY_TOKEN`
- Embedded Signup: painel precisa HTTPS público (não localhost)
- Data deletion: `POST /api/v1/meta/data-deletion`

## Stripe

- Checkout/portal URLs via `BILLING_*_URL`
- Webhook: `POST /api/v1/billing/webhooks/stripe`
- Sem keys = billing não fica ready

## AI / Flow / Gateway

Descoberta Docker: `http://flow-engine:8002`, `http://ai-engine:8003`, `http://backend-api:8000`. Dev local permanece em localhost via compose de `infra/`.

## Security

- Sem rate limit
- JWT ~12h em localStorage
- CORS wildcard ainda é default de dev
- Bootstrap cria tenants demo se env de bootstrap permanecer
- Security Group futuro: 22 (admin IP), 80, 443

## Resource Usage / AWS sizing

Medição `docker stats` desta passagem: ver evidências. Baseline conservadora para WhatsApp + MySQL + 3 APIs + Nginx:

- **t3.micro: não recomendado** (1 GB; MySQL + 4 Python estoura)
- **t3.small: capacidade mínima desta primeira produção** (2 GB, exige 2 GB de swap e medição pós-deploy)
- **t3.medium: upgrade recomendado** se RAM idle superar 80% ou houver swap constante/OOM
- Disco EBS inicial: 40 GB gp3
- Swap: documentar 1–2 GB se a instância for menor que medium

## Findings

| ID | Nível | Item |
| --- | --- | --- |
| F1 | P0 | Secrets em `.env` rastreados no Git (rotacionar) |
| F2 | P0 | Tokens Meta no antigo `.env.example` (sanitizado; histórico permanece) |
| F3 | P1 | Defaults de senha/bootstrap no `settings.py` |
| F4 | P1 | Admin build precisa `--dart-define=API_BASE_URL` senão aponta para localhost:8000 |
| F5 | P1 | Compose de dev publica 8000/8002/8003/40000/3310 |
| F6 | P2 | Sem rate limit / TrustedHost |
| F7 | P2 | JWT em localStorage |
| F8 | P3 | Dockerfiles sem multi-stage |
| F9 | P3 | CI/CD ausente (fora de escopo) |

## Blockers

1. Rotacionar Gemini/Meta tokens que estiveram no repositório.
2. Preencher `.env.production` com secrets novos.
3. Build web com URL pública.
4. Validar `compose up` de produção em homologação.

## Ready for EC2?

Não. Infra arquivos prontos; secrets e validação runtime ainda bloqueiam publicação.
