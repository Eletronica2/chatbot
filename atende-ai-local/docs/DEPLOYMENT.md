# Deployment — servidor local `atendeai` (192.168.0.50)

## Pré-requisitos (já executados na IA-01)
- Ubuntu 26.04.1, LVM expandido (`/` = 290 GB), SMART PASSED.
- Docker Engine 29.9 + Compose v5.6 (repositório oficial Docker), `daemon.json` com rotação de logs
  (json-file 10 MB × 3) e `live-restore`.

## Instalação
```bash
sudo mkdir -p /opt/atende-ai-local && sudo chown atendeai: /opt/atende-ai-local
# copiar o diretório atende-ai-local/ do repositório para /opt/atende-ai-local
cd /opt/atende-ai-local
./scripts/bootstrap.sh      # gera .env/segredos, baixa modelos, builda e sobe a stack
./scripts/healthcheck.sh    # sai com 0 somente se /ready = true
```
`bootstrap.sh` é idempotente: não sobrescreve `.env`, nem credenciais existentes.

## Operação
| Ação | Comando |
|---|---|
| Status | `docker compose ps` / `./scripts/healthcheck.sh` |
| Logs (JSON, sem conteúdo de mensagens) | `docker compose logs -f ai-api` |
| Restart controlado | `docker compose restart && ./scripts/validate.sh` |
| Validação pós-restart/reboot | `./scripts/validate.sh` (Docker, /ready, Qdrant persistente, isolamento, inferência real, filesystem) |
| Trocar modelo padrão | editar `LLM_MODEL` no `.env` → `docker compose up -d ai-api` |
| Benchmarks | `./scripts/benchmark.sh models <modelo> <ctx>` / `ptbr <modelo>` / `security` / `concurrency <modelo> 1,2,3,5` |
| Backup Qdrant | `./scripts/backup.sh` |

## Backup e restore do Qdrant
- `backup.sh` cria snapshot da coleção (`wait=true`), copia para `/var/backups/atende-ai-local/qdrant/`,
  confere SHA-256 contra o checksum do Qdrant e grava um `.json` com contagem de pontos. Mantém 7.
- **Mesmo disco físico**: isto protege contra erro lógico, não contra falha do HD. Copiar para mídia externa
  (ou para a AWS, na IA-02) é obrigatório para proteção real.
- Teste de restore (não destrutivo): `./scripts/restore_test.sh` confere o SHA-256 do backup mais recente,
  restaura em `atende_knowledge_restore_test`, compara pontos/tenants/metadados/índices com a coleção ativa e
  apaga só a coleção temporária. Só substituir a coleção principal com janela de manutenção.
- `backup.sh` e `restore_test.sh` usam `sudo` (diretório de backup é do root): rodar interativamente ou via cron do root.

## Rede
- Única porta publicada: `127.0.0.1:8100`. Ollama (11434) e Qdrant (6333/6334) não são publicados.
- `ai_internal` é `internal: true` (sem rota para fora). Qdrant está só nela.
- Nenhuma regra de roteador, túnel ou firewall foi alterada. SSH continua como estava.

## Rollback
`docker compose down` (sem `-v`) para parar mantendo volumes. Configurações anteriores do sistema estão em
`/root/pre-ia01-backup-*/` (fstab, netplan, sshd_config, tabela de partições, metadados LVM).
