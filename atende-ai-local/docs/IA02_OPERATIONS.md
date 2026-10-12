# IA-02 — operação e segurança

## Estado e ativação

A IA local é opt-in por tenant (`ai_provider=local` e `local_ai_enabled=1`). O default de banco é `gemini` e flag local `0`. A API de settings exige Superadmin para alterar essas opções e grava auditoria. O AI Engine também exige `LOCAL_AI_ENABLED=true` e segredo HMAC configurado; sem a chave global ou com o serviço local indisponível, não tenta mascarar a falha com outro modelo: deixa a resposta vazia e encaminha a conversa para humano.

Não ativar tenants reais antes de concluir VPN, backup externo, autorização de dados e teste de isolamento. A migração aditiva está em `database/migrations/011_tenant_ai_provider.sql`; o bootstrap da API também garante as colunas em MySQL 8.4.

## Rede planejada

WireGuard usa `10.77.0.0/30` (AWS `10.77.0.1`, servidor `10.77.0.2`), somente as rotas de peer, sem alterar rota default. O host local inicia a sessão e usa `PersistentKeepalive=25`; não se abre porta no roteador Wi-Fi. Ollama e Qdrant ficam em redes Docker privadas. FastAPI segue no loopback e um socket proxy expõe `10.77.0.2:8100` somente pela interface do túnel. `setup-local.sh`, `setup-aws.sh`, `netwatch.sh` e `rollback-local.sh` são scripts preparados, ainda não executados.

No lado AWS, revisar a necessidade de UDP 51820 antes de qualquer mudança no Security Group. O endpoint de IA nunca deve ser publicado na Internet. Regras de encaminhamento devem continuar impedindo acesso da AWS à LAN e redes Docker locais.

## Autenticação e isolamento

Chamadas internas usam HMAC-SHA256 sobre método, path, timestamp, nonce, tenant, request ID e hash do corpo. Nonces repetidos e timestamps fora da janela são recusados. A chave restringe tenants e escopos. Na API local, o tenant autenticado é usado em todos os filtros Qdrant. A API não recebe acesso ao MySQL AWS. A chave global local permanece desabilitada por padrão e não deve ser registrada nos logs.

## Knowledge sync e prompt

O endpoint `/v1/knowledge/sync` processa upsert/delete versionados, valida SHA-256, ignora versões antigas e mantém tombstone de remoção. Os testes devem usar apenas fixtures. A origem AWS precisa fornecer uma fila/outbox com retentativa limitada e reconciliação; não há conexão direta ao banco.

Prompt local: política global, empresa, dados estruturados, documentos recuperados, estado do fluxo, histórico curto e mensagem. O conteúdo do cliente não valida afirmações sobre o negócio. Preços, números, promoções, disponibilidade e afirmações de existência sem fonte são substituídos por resposta segura.

## Resiliência e observabilidade

Inferência: concorrência 1, fila limitada, limite por tenant e 503 com `Retry-After`. O cliente AI Engine usa deadline total, retry limitado com jitter, circuit breaker e request ID idempotente. O netwatch registra Wi-Fi/gateway/handshake e só tenta reiniciar o WireGuard com o gateway local disponível, limitado por intervalo. Ele não reinicia host nem contêineres.

Logs incluem request/tenant/provider/model/timing/uso/erro, sem mensagens, documentos nem credenciais. `/health` mede liveness e `/ready` inclui Qdrant, Ollama, embedding, modelo e inferência curta com cache.

## Backup, rollback e deploy

O backup Qdrant atual está no mesmo HD. `scripts/backup_offsite.sh` usa Restic para criptografar, aplicar retenção, verificar integridade e testar restore. Aceita apenas repositórios remotos SFTP/S3/REST/rclone; exige arquivo de senha 600/400 e não guarda senha no Git. Nenhum destino externo foi escolhido ou configurado, e o script ainda não foi executado.

Depois de escolher um destino externo autorizado, instale o pacote Restic do Ubuntu. Configure `/etc/atende-ai/restic.env` (modo 600) com `RESTIC_REPOSITORY` remoto e `RESTIC_PASSWORD_FILE=/etc/atende-ai/restic-password`; coloque a senha Restic no arquivo de modo 600. Inicialize uma vez com `sudo .../backup_offsite.sh init`, instale `backup/atende-ai-offsite-backup.service` e `.timer` em `/etc/systemd/system`, então habilite o timer. Rode `backup`, `check` e `restore-test` manualmente e confirme a evidência antes de sincronizar documentos reais.

Antes de deploy AWS, fazer dump MySQL, guardar Compose/config AI e registrar rollback. Nenhuma dessas etapas foi realizada nesta fase da auditoria.

Rollback local preparado: `sudo bash /opt/atende-ai-local/wireguard/rollback-local.sh`. Não executar até validar que a sessão SSH de administração permanece independente da VPN. O rollback AWS planejado desativa apenas `wg-quick@wg0`; as mudanças de Security Group devem ser revertidas separadamente.
