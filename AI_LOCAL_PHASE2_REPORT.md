# Atende Ai — relatório da Fase IA-02

Data: 2026-10-12. Escopo: auditoria e implementação no repositório, mais inspeção remota somente de leitura do servidor local. Nenhum deploy, alteração de rede, regra de firewall, Security Group, serviço AWS, documento de cliente ou envio de WhatsApp foi realizado.

## Status

**Implementação local em andamento; integração operacional AWS↔servidor local não estabelecida. Não está pronta para piloto controlado.**

A IA-01 está preservada e versionada nos commits `af9908a` (servidor local) e `43c0a2c` (relatório e evidências). O checkpoint anterior já existia no histórico antes desta tarefa. A árvore continha alterações não commitadas da IA-02; elas foram preservadas e ampliadas.

## Implementado nesta etapa

- Provider local no AI Engine, com HMAC-SHA256, timestamp, nonce, escopo de tenant, request ID, limite total, retries com backoff/jitter, respeito a `Retry-After`, circuit breaker e deduplicação no servidor local.
- API local com autorização HMAC por tenant, sincronização versionada e idempotente de documentos, tombstones para exclusões, limite de fila por tenant, prazo de processamento, logs sem conteúdo de mensagens e telemetria de rede opcional.
- Contexto selecionado do Flow Engine e dos dados estruturados chega ao prompt local. Guardas recusam alegações comerciais e afirmações de existência sem evidência; a política geral exige pt-BR e resposta de handoff quando a informação não está cadastrada.
- A verificação de fundamentação usa apenas dados comerciais estruturados, documentos e perfil da empresa. A pergunta, histórico e campos coletados do fluxo não podem validar preço, disponibilidade ou comodidade.
- Configuração persistente `ai_provider` e `local_ai_enabled` por tenant, com default Gemini/desabilitado para IA local, autorização Superadmin e evento no log administrativo. A tela de configurações mostra o seletor somente ao Superadmin.
- Falha do provider local mantém a entrada e sinaliza handoff humano sem criar resposta de saída. Assim, o BillingGate não reserva mensagem para uma resposta vazia.
- Script de migração aditiva `database/migrations/011_tenant_ai_provider.sql`; bootstrap também aplica as colunas aditivamente para MySQL 8.4.
- Scripts propostos para WireGuard de peer a peer, API no endereço privado por proxy socket, regras locais restritas, monitor de rede com reinício limitado do túnel e rollback.
- Mecanismo off-host preparado em `atende-ai-local/scripts/backup_offsite.sh`: Restic criptografado, retenção, verificação de dados e teste de restauração, mais timer systemd. Não foi configurado nem executado porque ainda não há destino externo autorizado.

## Auditoria do servidor local (somente leitura)

- Host `atendeai` acessível via SSH em `192.168.0.50`. Wi-Fi `wlxe01cfca274a9` está UP com `192.168.0.50/24`; rota default permanece via `192.168.0.1`. Ethernet `enp3s0` está DOWN, como esperado. Nenhuma configuração de rede foi alterada.
- WireGuard ainda não está instalado (`wg` ausente). Não há interface/handshake nem API pela VPN.
- FastAPI responde em `127.0.0.1:8100`; `/ready` passou: FastAPI, Qdrant, Ollama, embedding, modelo Qwen3 4B e inferência curta OK. Status amostrado: fila vazia, concorrência 1, limite de fila 3.
- Ollama e Qdrant não têm portas publicadas no host; Docker mostra Qdrant apenas na rede interna e Ollama sem porta publicada. FastAPI está somente no loopback.
- IPv6 global está atribuído à interface Wi-Fi. SSH escuta em `0.0.0.0:22` e `[::]:22`. `sudo -n ufw`, `nft` e `sshd -T` não puderam ser lidos porque o usuário SSH requer autenticação sudo; não se conclui exposição externa apenas pelo endereço global. A auditoria de firewall IPv6 e um teste externo continuam pendentes.
- Recursos no momento da leitura: 15 GiB RAM, 10 GiB disponíveis, swap sem uso, raiz 290 GB com 247 GB livres. Contêineres estavam healthy. Não houve reboot nesta etapa.

## AWS, VPN, backup e dados reais

- Tentativa SSH somente de leitura à EC2 foi recusada por autenticação de chave; logo não foi possível verificar estado corrente do host/Compose nem fazer smoke test privado. A evidência de produção existente é anterior e não substitui uma validação atual.
- A AWS ainda não tem evidência de WireGuard/handshake. O Security Group não foi modificado. O próprio escopo exige aprovação antes de abrir UDP 51820; essa autorização operacional não consta desta conversa.
- Backup externo criptografado, retenção e teste de restauração têm scripts preparados, mas ainda não há destino autorizado/configurado. Os backups IA-01 permanecem no mesmo disco físico. Fixtures fictícias são a única base para sync nesta fase; documentos reais não foram sincronizados.
- Não houve backup MySQL porque não houve deploy nem acesso AWS. Não houve migração de banco aplicada, mudança em Billing V2, Meta/WABA, Stripe, planos, produção ou provider global.

## Limitações e pendências

| Item | Estado | Evidência necessária para encerrar |
|---|---|---|
| Testes automatizados | Backend: 70 passed, 31 skipped; AI Engine: 8 passed; API local: 69 passed | 31 testes de backend foram pulados por exigirem MySQL de integração. Flutter/Dart SDK não está instalado para analyze/build |
| Security Group e WireGuard AWS | Não configurados | Aprovação para UDP 51820, acesso AWS e execução dos scripts com chaves privadas mantidas nos hosts |
| Firewall IPv6 local | Não auditado por falta de sudo interativo | Saída sanitizada de `nft`, UFW e `sshd -T`, mais verificação externa autorizada |
| Provider local por tenant | Implementado em código, não habilitado em produção | Backup, migração controlada, config global mestre habilitada e teste Superadmin/RBAC; tenant permanece Gemini por default |
| Knowledge sync | Endpoint e fixtures idempotentes implementados | Fila/outbox AWS e reconciliação com fonte de verdade; autorização e backup off-host antes de dados reais |
| Latência pela VPN / concorrência | Não medida | VPN ativa e benchmarks controlados de 1, 2 e até 4 chamadas |
| Queda/reconexão/reboot | Scripts preparados; não executados | Teste com sessão SSH independente e rollback verificado |
| Produção AWS e Billing V2 | Sem alteração | Backup MySQL, checkpoint do deploy, smoke test e regressão em janela autorizada |

Validações estáticas: `git diff --check`, compilação sintática Python, `bash -n` dos scripts WireGuard e `docker compose config --quiet` com `.env.example` temporário passaram. As suítes foram executadas em ambiente Python 3.14 isolado; testes de API local usaram stubs de imports de Torch/SentenceTransformer para não baixar modelos nem inferir.

**P0 observado:** nenhum vazamento, segredo exposto, perda de dados, cobrança duplicada, alteração de WABA ou envio real foi observado nesta etapa. **P1 pendentes:** VPN/reconexão ainda sem execução; auditoria IPv6 incompleta; backup off-host indisponível; latência e retry real não medidos; integração AWS e regressão de Billing V2 com MySQL ainda não executadas.

## Próximo passo operacional

Providenciar acesso SSH/AWS com chave autorizada e aprovar explicitamente a regra mínima UDP 51820 no Security Group. Em paralelo, escolher destino off-host criptografado. Após isso: backup e checkpoint de deploy, configurar primeiro o peer AWS, configurar o peer Wi-Fi sem mexer em rota default/SSH, validar handshake e API, executar testes e benchmarks com fixtures, aplicar migração aditiva e manter o provider local desligado globalmente e por tenant até o piloto autorizado.
