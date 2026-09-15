# AWS Production Deploy Report — Atende Ai

## 1. Status

Preparação local e bootstrap da EC2 concluídos. Produção ainda não está online: faltam DNS, credenciais novas de produção, build/start da stack, HTTPS, backup, reboot e smoke público.

## 2. Snapshot implantado

Baseline inicial: `main` / `ba89655`, árvore limpa. Foi enviada uma cópia sanitizada da árvore de trabalho com as correções desta etapa; como as mudanças ainda não têm commit, o snapshot implantável é identificado como `source-copy`.

## 3. Branding Atende Ai

PASS local. Textos visíveis, título, manifest, landing e login foram atualizados. Nomes internos históricos foram preservados.

## 4. EC2

- Nome: `Atende Ai`
- Instance ID: `i-0f8a52f8c7982590c`
- Região/AZ: `us-east-1` / `us-east-1f`
- Tipo: `t3.small`, 2 vCPU, 2 GiB RAM, x86_64
- Sistema real: Amazon Linux 2023 (a AMI não é Ubuntu, apesar da expectativa inicial)
- IPv4 privado: `172.31.77.86`
- Security Group: `sg-0eaa966854eb4344e`

## 5. Elastic IP

PASS. `3.218.194.130` associado à instância correta.

- Allocation ID: `eipalloc-0e3cdd25ebc86a778`
- Association ID: `eipassoc-061e7fba7f4f72ae5`

## 6. Security Group

PASS. Regras de entrada verificadas: SSH 22 apenas de `186.248.169.131/32`; HTTP 80 e HTTPS 443 de `0.0.0.0/0`. Não há exposição de 3306, 8000, 8002, 8003, 40000 ou 8080.

## 7–10. SSH, sistema, swap e Docker

- SSH por chave: PASS; host key verificada por TOFU, sem desabilitar `StrictHostKeyChecking`.
- Usuário correto da AMI: `ec2-user`.
- Atualizações do sistema: PASS, nada pendente no momento da execução.
- UTC/NTP: PASS.
- Swap: 2 GiB persistente, `vm.swappiness=10`, sem duplicação.
- Docker: 25.0.16 server / 25.0.14 client; hello-world PASS.
- Docker Compose oficial: v5.5.1, binário validado por SHA-256.
- `ec2-user` no grupo Docker; `docker ps` sem sudo PASS. O grupo Docker equivale a privilégio root.

## 11–19. Código, ambiente, domínios, DNS, Landing, Painel, API, Flutter e CORS

- Código sanitizado enviado para `/opt/atende-ai`; pacote sem `.pem`, `.env` real, `.git` ou caches.
- `.env.production` real ainda não foi criado: depende de credencial do provider de IA e definição segura do primeiro superadmin.
- Flutter release: PASS com `API_BASE_URL=https://api.meuatendeai.com.br`.
- Landing e painel: smoke local PASS; painel abre diretamente no login pelo hostname.
- Compose local: PASS; somente `127.0.0.1:8080` é publicado.
- CORS: landing e painel oficiais, sem wildcard.
- DNS em 2026-09-15: os três registros A ainda não resolvem para o EIP.

## 20–29. MySQL, migrations, persistência, serviços, Nginx e HTTPS

- MySQL permanece em Docker e sem porta publicada.
- Demo bootstrap foi desativado explicitamente na produção.
- Migrations existentes: `001` a `009`; `002` e `004` contêm dados demo e não serão aplicadas cegamente.
- Nginx host 1.30.4: vhosts HTTP instalados, `nginx -t` PASS e reload PASS.
- Certbot 2.6.0 + plugin Nginx instalados; `certbot-renew.timer` habilitado.
- Stack, persistência e HTTPS: PENDING por credenciais/DNS.

## 30–31. Webhook readiness

Rota encontrada: `/webhook` no WhatsApp Gateway, roteada pelo Nginx.

`META_WEBHOOK_URL=https://api.meuatendeai.com.br/webhook`

## 32–37. Backup, reboot, RAM, swap, CPU e disco

- Backup/reboot: ainda não executados, pois a stack não iniciou.
- RAM antes da stack: 1,9 GiB total, 281 MiB usados, 1,4 GiB disponíveis; swap sem uso.
- Disco: volume raiz de apenas 8,0 GiB, 4,3 GiB usados e 3,7 GiB livres. P1 de capacidade para build e operação contínua; qualquer ampliação exige confirmação específica de cobrança.

## 38–40. Smoke Tenant, Agent e Superadmin

Smoke local do bundle: PASS. Smoke público ainda não executado.

## 41. Security

- PASS: portas internas não publicadas e 8080 preso ao loopback.
- PASS: `DEBUG=false`, `MOCK_AI=false`, demo bootstrap desativado, rotação de logs configurada.
- PASS: health da IA falha fechado sem provider real.
- PASS: chave SSH não foi lida nem transferida.
- PENDING: `.env.production` com modo 600, HTTPS, CORS público e hardening pós-start.

## 42–43. Findings P0/P1/P2/P3

- P0 OPEN: provider real de IA e credenciais novas de produção ausentes; stack não pode ser declarada saudável.
- P0 OPEN: DNS/HTTPS, persistência, login e webhook públicos ainda não validados.
- P1 OPEN: volume raiz de 8 GiB é apertado para imagens, banco e logs.
- P1 FUTURO: backup off-instance/S3 não configurado.
- P2: Flutter analyze reporta seis avisos informativos.
- P2: não há migration ledger; migrations demo exigem tratamento explícito.

## 44. Blockers externos

1. Criar no Registro.br os A records `@`, `painel` e `api`, todos para `3.218.194.130`.
2. Definir um e-mail administrativo aprovado, o primeiro superadmin e a credencial real do provider de IA sem reutilizar segredos de homologação.
3. Confirmar separadamente eventual ampliação do EBS antes de qualquer alteração de cobrança.

## 45–47. Produção online, Meta e próximo passo

- Produção online? **NÃO**.
- Pronto para Meta? **NÃO**.
- Próximo passo: concluir DNS e segredos mínimos; depois executar compose, banco, health, Certbot, backup, reboot e smoke.

Meta/Facebook e Stripe Live não foram configurados.
