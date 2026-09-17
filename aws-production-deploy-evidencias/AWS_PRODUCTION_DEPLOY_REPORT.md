# AWS Production Deploy Report — Atende Ai

**Status final:** ATENDE AI PRODUÇÃO ONLINE — PRONTO PARA CONFIGURAR META

Checked at: 2026-09-17 (America/Sao_Paulo / UTC)

---

## 1. Status geral

Produção real no ar em `3.218.194.130` com HTTPS válido nos três hosts, stack Docker healthy pós-reboot, MySQL persistente, backup diário local, webhook público respondendo de forma controlada. Meta/Facebook e Stripe LIVE **não** foram configurados (conforme escopo).

## 2. Snapshot/commit implantado

- Repo local HEAD de referência: `e65b9e9` (`prod`)
- Código em `/opt/atende-ai` (cópia sanitizada implantada; sem `.git`/`.pem` no servidor)
- Compose project: `atende-prod` / `docker-compose.production.yml`

## 3. EC2

| Campo | Valor |
| --- | --- |
| Nome | Atende Ai |
| Instance ID | `i-0f8a52f8c7982590c` |
| Tipo | `t3.small` (2 vCPU, ~1.9 GiB RAM) |
| Região/AZ | `us-east-1` / `us-east-1f` |
| Usuário SSH | `ec2-user` |
| Key Pair | `atendeai` |

## 4. Elastic IP

PASS — `3.218.194.130` associado à instância.

## 5. Amazon Linux

PASS — Amazon Linux 2023.12.20260914, kernel `6.18.48-107.148.amzn2023.x86_64`.

## 6. EBS 20 GiB

PASS — `vol-0d86385575366db14` gp3 20 GiB. Sem nova ampliação / sem mudança de IOPS/throughput.

## 7. Filesystem

PASS — partição XFS `/dev/nvme0n1p1` expandida (`growpart` + `xfs_growfs`). `df -h /` ≈ **20G** (6.2G usados, 14G livres, 31%).

## 8. Swap

PASS — `/swapfile` 2 GiB; pós-reboot **0B** usado.

## 9. Docker

PASS — Docker 25.0.14, Compose v5.5.1, buildx 0.19.3. Projeto `atende-prod` no ar.

## 10. `.env.production` validation

PASS — existe, owner `ec2-user`, mode **600**. Variáveis obrigatórias do projeto presentes (SET). Conteúdo **não** exibido.

P1: `GEMINI_API_KEY` está SET mas o valor **parece texto de erro** (espaços / formato atípico). AI Engine permanece `healthy` com `AI_PROVIDER=gemini` e `MOCK_AI=false`; validar/corrigir a chave antes de confiar em IA generativa em produção.

## 11. Branding Atende Ai

PASS — títulos públicos Landing/Painel: **Atende Ai**. Identifiers internos históricos preservados.

## 12. DNS

PASS — `@`, `painel`, `api` → `3.218.194.130`. Nameservers Registro.br preservados.

## 13. Landing

PASS — `https://meuatendeai.com.br` 200, título Atende Ai, favicon/manifest OK. Host sem prefixo `painel.` exibe landing (roteamento Flutter).

## 14. Painel

PASS — `https://painel.meuatendeai.com.br` 200, SPA Flutter, `main.dart.js` 200 (~3.8 MB). Login host-based.

## 15. API

PASS — `https://api.meuatendeai.com.br/health` → 200 mínimo (`status=healthy`, sem secrets).

## 16. Flutter

PASS — release com `API_BASE_URL=https://api.meuatendeai.com.br`. Sem URL de runtime para localhost/127.0.0.1/:8000/:8080.

## 17. CORS

PASS — preflight `OPTIONS` login: `access-control-allow-origin: https://painel.meuatendeai.com.br` + `credentials=true` (sem `*`).

## 18. MySQL

PASS — container `mysql:8.4` healthy; volume `atende-prod_mysql_data`; **3306 não público**.

## 19. Migrations

PASS — ledger `schema_migrations`:

| Migration | Status |
| --- | --- |
| 001_init_saas_mysql.sql | APPLIED |
| 002_seed_demo_mysql.sql | SKIPPED (demo) |
| 003_billing_email_dashboard.sql | APPLIED |
| 004_pizzaria_demo.sql | SKIPPED (demo) |
| 005–009 | APPLIED |

## 20. Bootstrap

PASS — Super Admin (1), tenant (1), subscription (1), grupo (1), `meta_rate_cards` (4). `BOOTSTRAP_DEMO_DATA=false`. Sem conversas/mensagens/leads demo.

## 21. Backend

PASS — healthy; `DEBUG=false`; `TRUST_PROXY=true`.

## 22. Flow Engine

PASS — healthy.

## 23. AI Engine

PASS health — healthy; provider `gemini`; `MOCK_AI=false`.  
P1 — qualidade/formato da `GEMINI_API_KEY` (ver §10).

## 24. WhatsApp Gateway

PASS — healthy. **Sem** registro Meta / sem mensagem real.

## 25. Nginx

PASS — host edge 1.30.4 → `127.0.0.1:8080`; container Nginx SPA + `/api` `/health` `/webhook`.

## 26. HTTPS

PASS — TLS Let’s Encrypt válido nos três hosts; HTTP→HTTPS 301.

## 27. Certbot

PASS — cert para os 3 FQDNs; `certbot renew --dry-run` sucesso; `certbot-renew.timer` enabled/active.

## 28. Webhook readiness

PASS — rota real `/webhook`; sem params Meta → **403** controlado (não 404/502).

## 29. META_WEBHOOK_URL

```text
META_WEBHOOK_URL=https://api.meuatendeai.com.br/webhook
```

**Não cadastrado na Meta.**

## 30. Backup

PASS — `/var/backups/atende-ai/atenda-20260917T020654Z.sql.gz` (5.5K, gzip OK). Cron diário `15 3 * * *` via `/usr/local/bin/atende-ai-backup`, retenção 7 dias, sem password no crontab.  
P1 futuro: backup off-instance/S3.

## 31. Reboot

PASS — `sudo reboot` executado; serviços e Nginx voltaram sozinhos.

## 32. Persistência

PASS — volume MySQL, migrations, Super Admin, HTTPS e backup local permaneceram após reboot.

## 33. RAM

PASS em idle — ~49% used (~937 MiB / 1.9 GiB), available ~828 MiB. MySQL ~467 MiB é o maior consumidor. Sem OOM.

## 34. Swap usage

PASS — 0B usado em idle pós-reboot (antes do reboot havia ~6 MiB pontuais).

## 35. CPU

PASS idle — load ~0.08–0.19; CPU majoritariamente idle. Instância burstable `t3.small` (créditos: monitorar na AWS).

## 36. Disk usage

PASS — 6.2G / 20G (31%); `/var/lib/docker` ~3.5G. Sem `docker system prune -a`.

## 37. Smoke Tenant Admin

PARCIAL — API/login Super Admin OK; não há segundo usuário tenant-admin dedicado criado (propositalmente sem demo). UI paths de tenant não exercitados com usuário separado.

## 38. Smoke Agent

N/A — nenhum usuário agent provisionado (sem dados demo).

## 39. Smoke Superadmin

PASS — `POST /api/v1/auth/login` → 200, `role=superadmin`, token presente (redacted).

## 40. Dry-run

NÃO executado via UI browser nesta passagem; DB sem mensagens outbound; Meta não conectada → sem risco de outbound real.

## 41. Security

PASS — públicos: 22/80/443; 8080 só em `127.0.0.1`; 3306/8000/8002/8003/40000 não públicos; sem `.pem` em `/opt/atende-ai`; env 600; log rotate 10m×3; SSH SG não aberto a `0.0.0.0/0`.

## 42. Findings

1. Produção HTTPS + stack healthy pós-reboot.
2. Webhook público pronto (`/webhook` → 403 sem verify Meta).
3. Backup local + cron OK; DR off-instance pendente.
4. Gemini key com formato suspeito (P1).
5. Smokes de tenant-admin/agent limitados pela ausência de usuários extras.

## 43. P0 / P1 / P2 / P3

| Severidade | Item | Estado |
| --- | --- | --- |
| P0 | — | **Nenhum aberto** |
| P1 | `GEMINI_API_KEY` com formato suspeito | OPEN — corrigir valor sem reexpor |
| P1 | Backup off-instance / S3 | OPEN — documentado como próximo hardening |
| P2 | Smokes UI tenant/agent sem usuários dedicados | OPEN menor |
| P2 | `buildx_buildkit` container residual | baixa prioridade |
| P3 | Nome de arquivo de backup ainda prefixo histórico `atenda-` | cosmético |

## 44. Blockers externos

Nenhum blocker para declarar produção online. Próximo trabalho externo: **Meta/Facebook Developers** (fora deste escopo).

## 45. Produção online?

**SIM.**

## 46. Pronto para configurar Meta?

**SIM** — endpoint público pronto: `https://api.meuatendeai.com.br/webhook`.

## 47. Próximo passo

1. (Recomendado antes de tráfego de IA) corrigir `GEMINI_API_KEY` no servidor sem logar o valor.  
2. **META/FACEBOOK PRODUCTION** + webhook live + Embedded Signup + teste real inbound/outbound.  
3. Manter Stripe em TEST / not configured.  
4. Planejar backup off-instance (S3).

---

Meta/Facebook, WABA, Embedded Signup e Stripe LIVE **não** foram alterados nesta etapa.
