# Atende Ai — relatório da Fase IA-02

Atualizado em: 2026-10-15. Referência de código implantada: `db32c4977514827f0d9c0f901aebc38609f9442f`.

## Status

**Código IA-02 implantado e integração operacional privada HMAC validada; ainda não está pronta para piloto.** A implantação manteve `AI_PROVIDER=gemini`, `LOCAL_AI_ENABLED=false` e todos os quatro registros atuais de `tenant_settings` em `gemini`/`0`. Nenhum tenant foi ativado, nenhuma mensagem WhatsApp foi enviada e não houve alteração em Meta/WABA ou Stripe LIVE.

## Trabalho concluído nesta continuação

- Acesso SSH funcional à EC2 `3.218.194.130` e ao servidor local `atendeai` em `192.168.0.50`. O acesso local continuou por Wi-Fi (`wlxe01cfca274a9`); rota default permaneceu em `192.168.0.1`.
- Backup pré-deploy do MySQL criado em `/home/ec2-user/db-backups/atenda-ia02-predeploy-20261012T220059Z.sql.gz` (15.489 bytes, modo `600`, SHA-256 `4788113b11149cc011d9ef98abbc3bf2f20ddd557b951ee9e34680da1c73f8ef`). `gzip -t` passou. Não houve teste de restauração; o arquivo está no mesmo host/disco.
- Snapshot pré-deploy do código em `/home/ec2-user/deploy-backups/ia02-predeploy-source-20261012T220059Z.tar.gz` (modo `600`, SHA-256 `a5017728ce2300625fb5a53cc6e181b9a43492e47c8f9fdbade0fa8949815961`). `.env.production` ficou fora do pacote e não foi lido nem copiado.
- Migration aditiva `011_tenant_ai_provider.sql` aplicada e registrada em `schema_migrations`. `tenant_settings` contém as duas colunas novas; os quatro registros existentes seguem `gemini` com `local_ai_enabled=0`.
- Backend API e AI Engine foram reconstruídos a partir do commit IA-02 e implantados. Flow Engine, WhatsApp Gateway e MySQL não foram reconstruídos nem reiniciados. O painel Flutter foi compilado em release apontando para `https://api.meuatendeai.com.br` e publicado. Bundle: SHA-256 `4a1633663cb4ae120dd633b5ea82610e8f2bcbd397734be75205e4a90403d945`; sem endpoint localhost embutido.
- Smoke pós-deploy: MySQL, Backend API, Flow Engine, AI Engine e WhatsApp Gateway healthy; Nginx running sem healthcheck próprio. Todos os seis contêineres tiveram `RestartCount=0`. Landing, painel, `main.dart.js`, API `/health` e `127.0.0.1:8080/` responderam HTTP 200.
- Portas: Nginx publicado apenas em `127.0.0.1:8080`; MySQL, Backend, Flow, AI Engine e Gateway não têm porta publicada no host. Não apareceu nova porta pública.
- Rollback de aplicação preparado em `/home/ec2-user/deploy-backups/ia02-rollback-20261012T220059Z.txt`, com snapshots e IDs das imagens antigas. O rollback de aplicação mantém a migration aditiva; restauração integral do banco exige decisão separada por poder descartar mensagens/dados posteriores ao backup.

## Testes e validações

- Os 31 testes MySQL de Billing V2, antes pulados, passaram (`31 passed`, 5,80 s) contra MySQL 8.4.11 em container efêmero descartável. A base recebeu schema/migrations fictícios e foi removida ao fim. Um aviso de depreciação do Pydantic permaneceu.
- `flutter build web` passou em modo release com a URL de API de produção.
- `flutter analyze` falhou duas vezes com `FormatException: Unexpected end of input` no protocolo do servidor de análise Dart. A análise direta equivalente, `dart analyze`, concluiu sem erros: sete avisos informativos de estilo/depreciação em telas existentes.
- Os resultados do checkpoint anterior continuam registrados: Backend API `70 passed`; AI Engine `8 passed`; API local `69 passed`. A execução anterior da API local usou stubs para Torch/SentenceTransformer, sem inferência de modelo.
- `docker compose ... config --quiet` com o `.env.production` da EC2 passou. O conteúdo do arquivo não foi exibido.

## Rede e segurança operacional

- Os scripts WireGuard foram executados manualmente nos dois hosts. A EC2 tem `wg0=10.77.0.1/30`, porta UDP 51820, peer local `10.77.0.2/32`; o Ubuntu tem `wg0=10.77.0.2/30`, endpoint `3.218.194.130:51820`, `AllowedIPs=10.77.0.1/32` e keepalive de 25 s. Na saída local, handshake ocorreu há 2 s, com 92 B recebidos e 180 B enviados. A partir da EC2, `ip route get 10.77.0.2` selecionou `wg0`; HTTP privado para `10.77.0.2:8100/health` retornou 200 em 434 ms.
- A EC2 acessou `10.77.0.2:8100/ready` pela VPN: `ready=true`, Qdrant, Ollama, modelo Qwen3 4B e embedding carregados; a sonda real de inferência gerou 2 tokens (`load_ms=3478`, `total_ms=4112`). FastAPI responde em `127.0.0.1:8100` e o proxy de túnel escuta somente em `10.77.0.2:8100`. Rota default local continuou em `192.168.0.1` via Wi-Fi; SSH permaneceu em IPv4 e IPv6.
- O `atende-ai-netwatch.timer`, `atende-ai-vpn-proxy.socket` e `wg-quick@wg0` estão ativos. O journal mostrou quatro execuções periódicas do netwatch concluídas sem erro/restart. Isso confirma monitoramento, mas não simula queda e recuperação do link.
- As suítes em runners isolados passaram: API local `30 passed` (2,25 s) e AI Engine `8 passed` (0,52 s; um aviso de depreciação Pydantic). O harness real AWS→Ubuntu também passou: autenticou três identidades de fixture, rejeitou credencial ausente/inválida, adulteração de corpo/caminho, timestamp expirado, replay, tenant não autorizado e escopo insuficiente; confirmou que tenant do corpo não amplia identidade.
- A imagem local Ubuntu foi atualizada manualmente, com backup e rollback, recriando somente `ai-api`. O HMAC key ID Bella e as rotas `/sync` e `/manifest` foram validados no serviço. A API ficou healthy após reinício; os resets de conexão observados durante startup foram transitórios.
- O harness executou sync de documentos fictícios exclusivos para Bella Massa e Pastelaria do Zé, retrieval em ambos os tenants com filtro correto e cleanup final de ambas as fixtures. Inferência real via `LocalAIClient`/`generate_local` pela VPN respondeu `R$ 65,00` com Qwen3 4B e retrieval Qdrant (`total_ms=15.094`, servidor `14.686 ms`, retrieval `205 ms`, geração `14.479 ms`, 37 tokens de saída). O teste de fato desconhecido não inventou disponibilidade de Wi-Fi.
- Concorrência no tenant Bella: três solicitações; duas admitidas (ativa + fila) e uma rejeitada com `503 local_ai_saturated`; ambas admitidas usaram tokens Qwen reais. Timeout curto, porta fechada e classificação de 503/Retry-After passaram. As fixtures foram removidas pelo próprio harness. `LOCAL_AI_ENABLED=false` permaneceu e nenhuma mensagem WhatsApp foi enviada.
- O protocolo HMAC existente foi auditado: `LocalAIClient.sign` assina método, caminho, timestamp, nonce, tenant, request ID e SHA-256 do corpo. `ServiceVerifier` valida key ID, janela temporal, assinatura, nonce, escopo determinado pela rota e allowlist explícita de tenants. O cache de nonce é limitado e em memória no processo único; reinício o limpa, enquanto timestamp fora da janela é recusado.
- No provisionamento de teste, três chaves de smoke com 256 bits CSPRNG, validade de 48 h e tenants/escopos restritos foram transferidas por SSH autenticado para staging nos dois hosts. Os segredos não foram impressos nem incluídos no workspace/evidências. Após o harness, foram removidas conforme os resultados registrados abaixo.
- O runner `ai-engine/scripts/ia02_hmac_smoke.py` usa `LocalAIClient` e `generate_local` reais via execução explícita dentro do container AI Engine. Ele mantém `LOCAL_AI_ENABLED=false`, não cria endpoint público nem aciona WhatsApp; cria documentos fictícios únicos, testa auth/replay/isolamento/inferência/concorrência e remove somente seus fixtures.
- O pytest foi instalado apenas em runners descartáveis/isolados para testar os arquivos do workspace. Não foi instalado na imagem de produção nem se usou MySQL de produção como base de testes.
- Sub-redes observadas: LAN local `192.168.0.0/24`, Docker local `172.17.0.0/16`–`172.21.0.0/16`, VPC AWS `172.31.64.0/20`. `10.77.0.0/30` não conflita com as rotas vistas.
- O IPv6 global está atribuído ao Wi-Fi local e o SSH escuta em `[::]:22`. Auditoria reportou UFW inativo, INPUT IPv6 com política ACCEPT, sem regra nft que mencione a porta 22, sshd nas portas 22 em `0.0.0.0` e `[::]`, e power save Wi-Fi `on` (somente leitura). A energia do Wi-Fi não foi alterada.
- Security Group correto anexado à EC2: `sg-0eaa966854eb4344e` (`launch-wizard-1`, VPC `vpc-0a427c352561770e4`). O Console AWS mostrou as regras existentes HTTP 80, SSH 22 da origem `189.101.62.25/32` e HTTPS 443; todas foram preservadas. Adicionada e confirmada com sucesso somente a regra inbound UDP `51820`, origem `189.101.62.25/32`, descrição `WireGuard IA-02 - peer local atual`. O endpoint é EC2 `3.218.194.130`; rollback: remover essa regra exata. A origem pode mudar se o ISP trocar o IP.
- A primeira inspeção revelou que a imagem anterior da API local não implementava HMAC; a imagem foi então atualizada manualmente usando o script de deploy reversível. As tentativas anteriores do harness que receberam 401/404 não gravaram fixtures. A execução final do harness passou integralmente e limpou as fixtures criadas nessa execução. Fluxo contextual, BillingGate e handoff humano continuam sem smoke pelo caminho real.
- Restic off-host não foi configurado. Destino S3 e IAM aguardam autorização; nenhum bucket foi criado. Backups continuam sem cópia fora do host/disco.
- As chaves temporárias expiraram e foram removidas das configurações, dos snapshots específicos e dos bundles após a validação final; provider global continua desligado.
- Não foram testados reboot, perda/retorno do Wi-Fi, reconexão WireGuard, benchmark na VPN ou teste WhatsApp real. Não houve alteração em Billing V2 além da migration aditiva de `tenant_settings`.

## Pendências e decisão de prontidão

**P0 observado:** nenhum no caminho IA-02 testado. **P1:** firewall IPv6 local pendente de auditoria privilegiada; falta backup off-host e restore-test; queda/recuperação Wi-Fi e reconexão real não simuladas; seleção por tenant sem validação visual autenticada; fluxo contextual, BillingGate e fallback humano ainda sem smoke pelo caminho real.

**Pronto para piloto? Ainda não.** O provider permanece desabilitado globalmente e por tenant, mas o caminho privado HMAC, retrieval, inferência e isolamento por tenant passaram pelo harness. Pendências operacionais: firewall IPv6 local; backup off-host/restore-test; simulação de queda/reconexão; seleção por tenant na interface autenticada; contexto/BillingGate/handoff; e decisão sobre Restic/IAM. Nenhum WhatsApp real foi enviado.

## Hardening final — auditoria de 2026-10-15

### Credenciais e artefatos temporários

- A inspeção dos bundles identificou três credenciais de teste com validade configurada até `2026-10-14T23:21:25Z`: `ia02-9xsjLC2mHwA3CGTSAiqeByYn` (Bella Massa: `respond`, `knowledge:read`, `knowledge:write`); `ia02-sJqu3G3Eh5vrKVJdcSUmDz6u` (Pastelaria do Zé: mesmos escopos); `ia02-KNjs51pea4zFHoNylk76j-dv` (Bella Massa: `respond`). O prazo já havia passado antes da revogação (`2026-10-14T23:21:25Z`). O usuário executou a revogação manualmente em 2026-10-15; a chave antiga retornou `401 key_unknown` nos dois serviços. Os segredos não foram exibidos.
- A configuração local de `ai-api` contém as três chaves; a configuração de `ai-engine` na AWS contém apenas a identidade de escopo completo da Bella. O engine segue `LOCAL_AI_ENABLED=false`. Bundles privados mode 600 estavam nos diretórios `ia02-wireguard` dos dois hosts. Há snapshots de `.env` anteriores ao teste que também continham credenciais.
- Foram preparados scripts cirúrgicos e idempotentes: `atende-ai-local/scripts/revoke_ia02_hmac_test_keys.sh` e `infra/wireguard/revoke-aws-ia02-hmac-test-key.sh`. Eles removem apenas os IDs conferidos no bundle, recriam somente `ai-api` ou `ai-engine`, validam readiness e resposta `401 key_unknown`, verificam a proteção de replay no processo local e sanitizam snapshots de configuração correspondentes. Só depois removem os bundles e harnesses temporários.
- Em 2026-10-15, o usuário executou manualmente a revogação nos dois hosts. No Ubuntu: `TEMP_TEST_KEYS_REMOVED=3`, `OTHER_SERVICE_KEYS_PRESERVED=0`, API healthy/ready, chave antiga retornou `401 key_unknown`, replay protection confirmou ativa, dois snapshots `.env` sanitizados, bundles e arquivo de origem temporário removidos. Na AWS: chave temporária removida, `LOCAL_AI_ENABLED=false`, AI Engine healthy sem HMAC key de teste, a chave antiga retornou `401 key_unknown`, um snapshot `.env.production` sanitizado, bundle e harness temporário removidos. As implementações HMAC e WireGuard foram preservadas.

### Saúde e rede

- Nova leitura sem privilégios confirmou AWS MySQL, Backend API, AI Engine, Flow Engine e WhatsApp Gateway `running/healthy`; Nginx permanece sem healthcheck. No servidor local, FastAPI, Qdrant e Ollama estão `running/healthy`, e `/ready` retornou `ready=true`, incluindo checagem de registry, embedding e inferência. `LOCAL_AI_ENABLED=false` continua configurado.
- O handshake WireGuard não foi revalidado nesta execução porque `wg show` requer privilégio no Ubuntu. A revogação não alterou WireGuard; evidência anterior de handshake não comprova o estado atual.
- IPv6: Wi-Fi `wlxe01cfca274a9` tem endereços globais e rota default IPv6 via RA; SSH escuta em `[::]:22`. FastAPI escuta em `127.0.0.1:8100` e `10.77.0.2:8100`; Qdrant/Ollama não aparecem como portas host em escuta. Auditoria completa do firewall ficou pendente: UFW/nftables exigem root e nenhum comando privilegiado foi executado. Não foi possível alcançar os endereços IPv6 a partir da EC2 (sem rota IPv6), então isso não comprova nem descarta exposição externa. Regras do roteador não verificadas. Nenhuma regra de firewall, Wi-Fi ou AWS foi alterada nesta etapa.

### Backup off-host

- Nenhum bucket, usuário/policy IAM, repositório Restic, credencial ou recurso pago foi criado; nenhum dado real foi enviado para fora. `backup_offsite.sh` exige backend remoto, senha em arquivo mode 600/400, retenção diária 7/semanal 4/mensal 6, `restic check --read-data` e restore-test temporário. A configuração operacional ainda depende de aprovação do destino e identidade IAM mínima.
- A coleta anterior encontrou snapshot Qdrant de aproximadamente 1,03 MB e registry local de aproximadamente 48 KB. Com hipótese conservadora de 17 cópias completas (~18,2 MB), S3 Standard a US East (N. Virginia) a US$ 0,023/GB-mês daria cerca de US$ 0,0004/mês de armazenamento, antes de requisições e variação de dados; é uma estimativa de ordem de grandeza, não uma cotação. A tarifa depende da região, classe, volume, requests e retenção. A tabela oficial informa que os custos incluem componentes separados de storage, requests, transfer e management: [preços do Amazon S3](https://aws.amazon.com/s3/pricing/).
- Limitação encontrada no script atual: o Restic arquiva somente o diretório de snapshots Qdrant; o banco registry SQLite (`/data/registry.db`) não está incluído. Antes de usar dados reais, incluir uma cópia consistente do registry no conjunto protegido e definir retenção/volume real. Restauração real não executada; pendente aprovação, configuração e fixture isolada.

### Interface, Flutter e regressão

- Código confirma seletor provider na tela de configurações, com gravação protegida por `_isSuperadmin`; os caminhos de API incluem `ai_provider` e `local_ai_enabled`. Não havia navegador autenticado aberto nesta sessão e não foi solicitada senha. Portanto, interface real, erros visuais, status de provider, permissões de Tenant Admin/Agent e auditoria ponta a ponta não foram validados visualmente.
- `flutter analyze` falhou anteriormente no protocolo do servidor Dart (`FormatException: Unexpected end of input`). Nesta execução, `dart analyze` passou sem erros e reportou sete avisos informativos de estilo/depreciação existentes. `flutter test` não pode executar porque `admin-panel/test` não existe. `flutter build web --release` passou em 152,5 s.
- A tentativa de regressão Backend/API deste workspace não coletou testes: o `.venv` existente não tem FastAPI; pytest terminou com três erros de importação. Não instalei dependências nem usei banco de produção. Resultados históricos de runners isolados permanecem: Backend 70 passed/31 skipped, AI Engine 8 passed, API local 30 passed e Billing V2 31 passed em MySQL efêmero. Não houve rerun isolado nesta sessão; os pulados continuam pulados. Fallback humano, BillingGate e seleção/RBAC por sessão autenticada seguem sem teste ponta a ponta atual.

### Decisão de piloto

1. Credenciais temporárias removidas das configurações: **sim**, três na API local e uma configuração correspondente no AI Engine AWS.
2. Validação de revogação/replay: **sim**, chave antiga retornou `401 key_unknown` em ambos os hosts; replay protection permaneceu ativa no código local.
3. Bundles/harnesses temporários removidos: **sim**, após as verificações; snapshots específicos sanitizados (dois locais, um AWS).
4. WireGuard preservado: nenhuma mudança feita durante revogação; handshake atual segue pendente de leitura privilegiada.
5. Implementação HMAC IA-02 preservada; credenciais temporárias removidas. `LOCAL_AI_ENABLED=false`.
6–8. IPv6 parcialmente auditado; firewall/roteador e exposição externa conclusiva pendentes.
9–10. Backup off-host e restauração: **não configurados/não testados**.
11–12. UI Superadmin e RBAC visual: **não validados**; controles de código inspecionados apenas.
13. Flutter analyze direto passou com avisos informativos; teste ausente; build release passou.
14–18. Regressão nesta sessão: coleta Backend/API falhou por ambiente sem FastAPI; evidências históricas isoladas: Backend 70 passed/31 skipped, AI Engine 8, API local 30, Billing V2 31. Fallback real pendente.
19. Saúde após revogação: MySQL, Backend API, AI Engine, Flow Engine e WhatsApp Gateway healthy; API local, Qdrant e Ollama healthy/readiness true. `LOCAL_AI_ENABLED=false`. Handshake não atualizado.
20. P0: nenhum identificado na auditoria.
21. P1: auditoria firewall IPv6 e handshake; corrigir abrangência do backup; aprovação/configuração S3 e restore-test; sessão Superadmin para validação visual; recuperar ambiente de teste isolado e validar BillingGate/fallback.
22–23. Ações manuais: aprovação específica do destino/custos antes de criar S3/IAM; validar navegador com Superadmin sem compartilhar senha no chat; executar firewall/handshake com assistência sudo e devolver apenas saídas sanitizadas.
24. **Não pronto para piloto controlado** enquanto auditoria IPv6, backup/restauração e validação de UI/RBAC/fallback não estiverem concluídos. Provider global e por tenant permanecem desligados; nenhum WhatsApp, Meta, Stripe LIVE, billing ou dado real foi ativado/enviado.
