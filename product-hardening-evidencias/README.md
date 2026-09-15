# Product Hardening — Evidências

## Baseline (início)

- cwd: `/home/arthur/Área de trabalho/chatbot`
- branch: `main`
- HEAD: `0788c57 Refactor billing hub and team screens for improved functionality and UI`
- Working tree já continha mudanças de production readiness (compose, nginx, docs, env examples).

## Validação

| Check | Resultado |
|-------|-----------|
| `pytest tests/test_product_hardening.py` | **6 passed** (via container + docker cp tests; `.dockerignore` exclui `tests/`) |
| `dart analyze lib` | 6 *info* (deprecated DropdownButtonFormField.value) — sem errors |
| `flutter build web --release` | **PASS** |
| `docker compose -f docker-compose.production.yml config` | **PASS** |
| Backend health `:8000/health` | healthy após rebuild `infra-backend-api` |
| Rotas assume/transfer/return-to-ai/group | presentes no container recriado |
| Botão Assistente (cliente WhatsApp) | **removido** |
| Favicon Flutter default | substituído (Atenda Ai em `web/` + build) |

## Meta rate card

Consulta docs oficiais Meta: **2026-09-03** — `https://developers.facebook.com/docs/whatsapp/pricing/`  
Seeds BR (estimativa UI): MARKETING 0.3217 BRL, UTILITY/AUTH 0.0350 BRL, SERVICE 0 até 2026-09-30.

## Screenshots

Capturas manuais recomendadas (UI live):

- `login-new.png`
- `sidebar-admin.png` / `sidebar-agent.png`
- `conversation-ai.png` / `conversation-human.png` / `conversation-transfer.png`
- `groups.png` / `quick-replies.png` / `billing.png` / `template-create.png`

Placeholders: rode o painel e grave em `product-hardening-evidencias/` conforme smoke.

## Stitch

Stitch MCP conectado (`user-stitch`). Identidade/login implementados no Design System V2 + CustomPainter/logo vetorial local; mocks Stitch usados como referência de direção, não como fonte de entidades fictícias.
