# Deploy AWS EC2 — Atende Ai

Domínios oficiais: `meuatendeai.com.br`, `painel.meuatendeai.com.br` e `api.meuatendeai.com.br`.

## 1. Criar EC2

- Ubuntu Server 24.04 LTS
- Instance atual: **t3.small** (2 GiB; criar 2 GiB de swap e medir memória após subir)
- Storage: 40 GB gp3
- Key pair (ED25519)
- Associar Elastic IP antes de configurar o DNS oficial

## 2. Security Group

Inbound:

- 22/tcp — somente IP administrativo
- 80/tcp — 0.0.0.0/0
- 443/tcp — 0.0.0.0/0

Nada mais (sem 3306, 8000, 40000).

## 3. SSH

- Login por chave
- Desabilitar password login
- Desabilitar root login
- Usuário de deploy não-root (`ubuntu` ou `atenda`) com docker via grupo `docker`

## 4. Instalar Docker

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Relogue e confira `docker compose version`.

## 5. Copiar o projeto

Clone ou `scp` o repositório. Não copiar `.env` de desenvolvimento.

```bash
git clone <repo> atenda
cd atenda
git checkout <tag-ou-commit>
```

## 6. Criar `.env.production`

```bash
cp .env.production.example .env.production
chmod 600 .env.production
```

Preencher secrets **novos**. Não reutilizar tokens que estiveram no Git.

## 7. Build do admin

```bash
API_BASE_URL=https://api.meuatendeai.com.br ./scripts/build_admin_web.sh
```

## 8. Subir Compose

```bash
docker compose -f docker-compose.production.yml --env-file .env.production up -d --build
docker compose -f docker-compose.production.yml ps
```

## 9. Migrations / bootstrap

O backend aplica schema complementar e cria o superadmin definido em `DEFAULT_ADMIN_*` no startup. Confirmar logs:

```bash
docker compose -f docker-compose.production.yml logs backend-api | tail
```

Não usar senhas de `CREDENCIAIS_TESTE.md` em produção.

## 10. Nginx + DNS

1. Apontar raiz, `painel` e `api` para o Elastic IP
2. Instalar `infra/nginx/atende-ai-edge.conf` no Nginx do host
3. Recarregar Nginx

Em produção real, TLS na borda:

```bash
sudo apt-get install -y certbot python3-certbot-nginx
# ou Certbot com o Nginx do host, se Nginx for host-level
```

Esta stack usa Nginx em container. Opções:

- **A (recomendada na 1ª publicação):** Nginx no host (80/443) fazendo proxy para `127.0.0.1:8080` e Certbot no host
- **B:** Certificados montados no container Nginx

## 11. Certbot

Com Nginx no host na frente do container:

```bash
sudo certbot --nginx -d meuatendeai.com.br -d painel.meuatendeai.com.br -d api.meuatendeai.com.br
```

## 12. Meta

Configurar no App Dashboard:

- Callback webhook: `https://api.meuatendeai.com.br/webhook`
- Verify token = `META_VERIFY_TOKEN`
- Embedded Signup / OAuth redirect: origem `https://painel.meuatendeai.com.br`
- Data deletion: `https://api.meuatendeai.com.br/api/v1/meta/data-deletion`

Não apontar para localhost.

## 13. Stripe

- Webhook: `https://api.meuatendeai.com.br/api/v1/billing/webhooks/stripe`
- Success/cancel/portal = URLs `BILLING_*` em `https://painel.meuatendeai.com.br/#/billing/...`

Não ativar cobrança até as keys de live e o webhook estiverem testados em modo test.

## 14. Smoke

- `https://meuatendeai.com.br` carrega a landing
- `https://painel.meuatendeai.com.br` carrega o login do admin
- Login
- Overview, Conversas, Automações, Ações, Templates, WhatsApp, Equipe
- Superadmin: Clientes, Cobrança
- `GET https://api.meuatendeai.com.br/health`
- `GET https://api.meuatendeai.com.br/webhook` (Meta verify)

## 15. Backup

Antes de qualquer upgrade:

```bash
CONTAINER=$(docker compose -f docker-compose.production.yml ps -q mysql)
MYSQL_ROOT_PASSWORD=... CONTAINER=$CONTAINER ./scripts/backup_mysql.sh
cp .env.production .env.production.bak
git rev-parse HEAD
```

Política inicial: dump diário, retenção 7 dias.

## 16. Rollback

```bash
git checkout <tag-anterior>
API_BASE_URL=https://api.meuatendeai.com.br ./scripts/build_admin_web.sh
docker compose -f docker-compose.production.yml --env-file .env.production up -d --build
```

Se o schema mudou, restaurar dump:

```bash
# somente com backup prévio e janela de manutenção
MYSQL_ROOT_PASSWORD=... CONTAINER=$CONTAINER ./scripts/restore_mysql.sh backups/<file>.sql.gz atenda_restore_probe
```

## 17. Budget AWS

Criar Budget com alerta (ex. 80% de um teto mensal) **antes** de deixar a instância 24/7.

## 18. Segurança do `.env`

```bash
chown deploy:deploy .env.production
chmod 600 .env.production
```

Não commitar. Não colar em issue/chat.
