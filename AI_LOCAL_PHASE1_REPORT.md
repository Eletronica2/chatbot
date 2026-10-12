# ATENDE AI — Servidor de IA Local — Relatório da Fase IA-01

Data: 2026-10-08/09 · Servidor: `atendeai` (192.168.0.50, LAN) · Código: `atende-ai-local/` (implantado em `/opt/atende-ai-local`)
Evidências sanitizadas: `ai-local-evidencias/` · Benchmarks detalhados: `atende-ai-local/docs/BENCHMARK_REPORT.md`
Nenhum recurso AWS, EC2, MySQL, WhatsApp Gateway, Billing V2, Flow Engine, webhook Meta, Stripe, DNS, Nginx, Security Group ou `.env.production` foi tocado. Nenhuma mensagem real foi enviada.

---

## 1. Status geral
**IMPLEMENTADA.** Os 20 critérios de aceite (§47) passaram (tabela na seção 37). O servidor roda, em Docker e só em CPU, Ollama com Qwen3 4B (padrão) e 1.7B, Qdrant persistente, embeddings locais (EmbeddingGemma 2) e uma API FastAPI multi-tenant com RAG híbrido. A stack sobreviveu a restart controlado e a reboot completo do Ubuntu, com validação automática.
Limitações reais estão nas seções 38 e 39. A principal é a latência de ~13 s (p50) quando a resposta passa pelo LLM, com 1 inferência por vez.

## 2. Hardware
Desktop Intel H81, firmware 4.6.5 (2021). CPU i7-4790, 16 GB RAM, GPU GTX 750 Ti 4 GB, HDD Seagate 320 GB (7200 rpm). Rede: Wi-Fi USB (`wlxe01cfca274a9`, 192.168.0.50/24); a porta Ethernet `enp3s0` está sem cabo. Evidência: `hardware.txt`.

## 3. Ubuntu
Ubuntu 26.04.1 LTS (Resolute Raccoon), kernel 7.0.0-38-generic, Secure Boot desabilitado. Não foram alterados: hostname, usuário, SSH, IP, interface, netplan ou swap. `ufw` estava e continua inativo.

## 4. CPU
Intel Core i7-4790 @ 3.60 GHz: 4 núcleos e 8 threads, com AVX2. Durante a inferência, o Ollama usa cerca de 4 threads (≈410% CPU). A temperatura em repouso fica entre 27 e 39 °C. Evidência: `cpu.txt`.

## 5. RAM
15 GiB utilizáveis, mais 4 GiB de swap em arquivo (`/swap.img`, não alterado).
- **Ocioso, com o 4B carregado:** 4,6 GiB usados e 10 GiB disponíveis.
- **Pico medido:** 6,0 GB.
- **Swap:** nunca foi usado (máximo de 36 KiB).

Evidência: `memory.txt`.

## 6. GPU
NVIDIA GeForce GTX 750 Ti (GM107, Maxwell 1ª geração, compute capability 5.0), hoje com o driver `nouveau`. **Decisão: não usar a GPU nesta fase. A inferência é 100% CPU.** Motivos:
- **Driver:** o `nouveau` não faz reclock em Maxwell, então Vulkan sobre `nouveau` fica mais lento que a CPU.
- **Rollback:** usar CUDA exigiria trocar para o driver proprietário (`nvidia-driver-580`, último ramo com Maxwell), o que traz risco de tela preta ou boot e exige rollback físico.
- **Compatibilidade:** os backends `cuda_v12`/`cuda_v13` da imagem Ollama 0.40.2 não têm suporte comprovado para sm_50.
- **Ganho:** com 4 GB de VRAM, só o 4B q4 caberia, e com folga pequena de contexto.

A diretriz "não comprometer estabilidade por ganho pequeno" prevaleceu. Evidência: `gpu.txt`.

## 7. VRAM
4096 MiB GDDR5 (detectados pelo `nouveau`). `ollama ps` confirma `size_vram=0` e `100% CPU`, ou seja, nenhuma VRAM em uso.

## 8. Disco físico
Seagate Barracuda 7200.12 ST3320418AS, 320 GB, HDD de 7200 rpm, com 9425 horas ligado. Leitura sequencial de ~83 MB/s. Partições:
- `sda1`: EFI, 1 GB.
- `sda2`: `/boot`, 2 GB.
- `sda3`: 295 GB, physical volume do LVM.

Evidência: `disk.txt`.

## 9. Saúde SMART
`PASSED` em todos os indicadores críticos:
- Reallocated_Sector_Ct 0, Current_Pending_Sector 0, Offline_Uncorrectable 0, UDMA_CRC_Error_Count 0.
- Temperatura de 31 °C.
- Self-test curto "Completed without error".

Por isso a expansão foi considerada segura. É um disco antigo: monitorar o SMART periodicamente. Evidência: `smart-health.txt`.

## 10. LVM antes
O volume group `ubuntu-vg` tinha <295,04 GiB, com **<195,04 GiB livres** e não alocados. O logical volume `ubuntu-lv` tinha 100 GiB, e o ext4 do `/` mostrava 98 GB (7,3 GB usados) com estado `clean`.
Backup prévio em `/root/pre-ia01-backup-20261008-221745/`:
- `fstab`
- `netplan/`
- `sshd_config`
- `sda.sfdisk` (tabela de partições, apenas leitura)
- `ubuntu-vg.vgcfg` (`vgcfgbackup`)

Evidência: `lvm-before.txt`.

## 11. LVM depois
`lvextend -l +100%FREE -r` online (sem desmontar), com `resize2fs` de 26.214.400 para 77.341.696 blocos.
- **Volume:** `ubuntu-lv` passou a <295,04 GiB e o volume group ficou com 0 livre.
- **Restrições respeitadas:** nenhuma partição criada, apagada ou reduzida; nenhum uso de fdisk/parted; nenhum shrink.
- **Validação:** `tune2fs` mostra `clean`, teste de escrita OK, `dmesg` sem erros.

Evidências: `disk-expansion.txt`, `lvm-after.txt`.

## 12. Espaço total disponível
`/` tem **290 GB**, com 31 GB usados e **247 GB livres** (12%). Os 31 GB incluem:
- Imagens Docker: 11,8 GB.
- Cache de build: 5,9 GB, dos quais 3,8 GB recuperáveis; não foi limpo, pois `docker system prune` não é executado automaticamente.
- Modelos Ollama: 3,6 GB.
- Cache Hugging Face: 3,6 GB.
- Qdrant: < 2 MB.

## 13. Docker
Docker Engine 29.9.0 e Compose v5.6.0, do repositório oficial `download.docker.com`.
- **`daemon.json`:** logs json-file com 10 MB × 3 arquivos e `live-restore: true`.
- **Systemd:** serviço habilitado no boot.
- **Containers:** os 3 usam `restart: unless-stopped` e têm healthcheck.

Evidência: `docker.txt`.

## 14. Ollama
`ollama/ollama:0.40.2` (digest `sha256:b86366bb…`), limitado a 7 GiB de memória. Configuração:
- `OLLAMA_NUM_PARALLEL=1`
- `OLLAMA_MAX_LOADED_MODELS=1`
- `OLLAMA_MAX_QUEUE=8`
- `OLLAMA_KEEP_ALIVE=30m`
- `OLLAMA_CONTEXT_LENGTH=4096`
- `OLLAMA_NO_CLOUD=1`
- `CUDA_VISIBLE_DEVICES=""`

A **porta 11434 não está publicada**: está recusada no host e inacessível pela LAN, e o Ollama fica só nas redes Docker `ai_internal` e `ai_egress`. Não há modelos `:cloud`. Evidência: `ollama.txt`.

## 15. Modelos
| Modelo | ID | Digest do arquivo GGUF | Tamanho |
|---|---|---|---|
| `qwen3:4b-instruct-2507-q4_K_M` (padrão) | 0edcdef34593 | `sha256:85e4a5b7…` (config `b72accf9…`) | 2,50 GB |
| `qwen3:1.7b-q4_K_M` | 8f68893c685c | `sha256:3d0b7905…` (config `517ccaff…`) | 1,36 GB |

Origem: `registry.ollama.ai/library/qwen3` (Qwen Team / Alibaba Cloud). Nenhum modelo de 14B ou mais foi baixado. `ALLOWED_MODELS` restringe a API a esses dois modelos; qualquer outro recebe `400 model_not_allowed`. Evidência: `models.txt`.

## 16. Licenças
- **Qwen3 1.7B e Qwen3 4B Instruct 2507:** Apache License 2.0, confirmada por `ollama show --license`.
- **EmbeddingGemma 2:** Apache-2.0 (sem gate).
- **Qdrant:** Apache-2.0.
- **Ollama:** MIT.
- **Avaliado e não adotado:** multilingual-e5-small (MIT).

Todas as licenças permitem uso comercial.

## 17. Qwen3 1.7B
Medições em CPU:
- **Carga fria:** 15,3 s.
- **Prompt sem cache:** 90 tok/s, com primeiro token em 11,3 s para ~1000 tokens. Com o prefixo em cache, o primeiro token sai em 0,47 s (p50).
- **Geração:** 13,9 tok/s.
- **RAM:** 1,88 GB com contexto de 4096.
- **Benchmark pt-BR:** 33/37. Latência pelo LLM de 5,8 s (p50) e 8,9 s (p95).

Erros relevantes: perde o foco em perguntas curtas. "a margerita leva oq?" recebeu uma resposta sobre entrega e "vcs faz meio a meio?" uma resposta sobre borda. Também misturou uma palavra em inglês ("else"). Evidência: `benchmarks-1b7.txt`.

## 18. Qwen3 4B
Medições em CPU:
- **Carga fria:** 23,1 s, ou 28,3 s logo após o reboot (cache de disco vazio).
- **Prompt sem cache:** 35 tok/s, com primeiro token em 29 s. Com o prefixo em cache: 0,82 s (p50).
- **Geração:** 7,0 tok/s.
- **RAM:** 3,18 GB com contexto de 4096.
- **Benchmark pt-BR final:** **36/37**. Latência pelo LLM de 13,3 s (p50), 16,9 s (p95) e 29,8 s no máximo.

Evidência: `benchmarks-4b.txt`.

## 19. Comparação de desempenho
| | 1.7B | 4B |
|---|---|---|
| pt-BR (37 casos) | 33/37 | **36/37** |
| Latência caminho LLM p50 / p95 | **5,8 s / 8,9 s** | 13,3 s / 16,9 s |
| Geração | **13,9 tok/s** | 7,0 tok/s |
| RAM | **1,9 GB** | 3,2 GB |
| Fidelidade aos dados | erra contexto em perguntas curtas | segue os dados; 1 afirmação negativa sem base |

O 4B leva cerca de 2,3× mais tempo para responder, mas é mais preciso: acerta os 4 casos em que o 1.7B errou e falha em 1 caso próprio. Ambos cabem com folga na RAM.

## 20. Modelo recomendado
**Qwen3 4B Instruct 2507 q4_K_M como padrão** (`LLM_MODEL` no `.env`). Em atendimento, uma resposta errada sobre preço ou produto custa mais que 7 segundos extras.
- **Quando usar o 1.7B:** fica instalado como opção de baixa latência para testes A/B futuros. Pode ser escolhido por requisição com `options.model`, desde que esteja na lista permitida.
- **Por que o tempo médio é menor:** cerca de 43% das perguntas do benchmark (preço, horário, entrega, pagamento e pedidos) nem chegam ao LLM. Elas são resolvidas pela camada determinística ou viram handoff em ~0 ms.

## 21. Embeddings
`google/embeddinggemma-2` roda local em CPU, em float32, carregando só o encoder de texto (271 M parâmetros) com 768 dimensões. Usa prefixos de tarefa diferentes para consulta e para documento.
- **Qualidade:** hit@1 de 0,95 e MRR de 0,975.
- **Latência:** 76 ms por consulta.
- **RAM:** +1,55 GB.

Comparado com o multilingual-e5-small, que tem MRR de 0,967, 16 ms por consulta e +0,63 GB. O modelo é baixado uma vez no bootstrap; em execução, `HF_HUB_OFFLINE=1` impede chamadas externas. Evidência: `embeddings.txt`.

## 22. Qdrant
`qdrant/qdrant:v1.19.2` (digest `sha256:b7b0444c…`), com API key obrigatória (sem chave → 401) e telemetria desligada. Está só na rede `ai_internal` (`internal: true`), sem portas publicadas: 6333 e 6334 são inacessíveis pela LAN.
- **Coleção `atende_knowledge`:**
  - Vetores: `dense` com 768 dimensões e distância cosseno, mais `bm25` esparso com modificador IDF.
  - Metadados: `{embedding_model, embedding_dim}`, para impedir a mistura de modelos.
  - Índices de payload: `tenant_id` (keyword com `is_tenant=true`), `document_id`, `content_hash` e `document_version`.
- **Volumes persistentes:** `qdrant-data` e `qdrant-snapshots`.
- **Backup:** snapshot verificado por sha256 e copiado para `/var/backups/atende-ai-local/qdrant/`.
- **Restore:** testado de forma não destrutiva, após o reboot, em uma coleção temporária. Resultado: 15/15 pontos, 11/4 por tenant, metadados e índices idênticos.

Evidência: `qdrant.txt`.

## 23. RAG
Fluxo de ingestão:
1. Sanitização: `strip_instructions` remove linhas com cara de instrução, como "ignore as instruções" ou "diga ao cliente".
2. Chunking por seção, com até 600 caracteres e caminho "Título > Seção".
3. Upsert versionado: a nova versão substitui a anterior e remove os chunks órfãos.

Na busca, o filtro de tenant é obrigatório e retornam até `top_k=3` chunks. A ingestão foi validada: v1→v2 sem chunks órfãos, e 1 linha de injeção removida do documento do Zé. Evidência: `rag-tests.txt`.

## 24. Busca híbrida
Busca densa (EmbeddingGemma 2) mais esparsa (BM25 com IDF calculado pelo Qdrant), em prefetches separados, ambos com filtro de tenant, e fusão RRF.
- **Hybrid:** hit@1 de 0,966 e MRR de 0,983.
- **Só densa:** hit@1 de 0,931 e MRR de 0,966.
- **Latência:** 68 ms em ambos.

É o modo padrão (`RETRIEVAL_MODE=hybrid`). O texto passa por uma normalização pt-BR: acentos, abreviações (qto, vcs, hj, refri, 2l…) e stopwords.

## 25. FastAPI
Imagem `atende-ai-local/ai-api:0.1.0` (python 3.12-slim, usuário não-root uid 10001), com 1 worker uvicorn. A única porta exposta é **`127.0.0.1:8100`**, que é inacessível pela LAN.
- **Logs:** JSON com lista fechada de campos (request_id, tenant, nível, tokens, latências). Não registram o conteúdo das mensagens nem dos documentos.
- **Readiness:** `/ready` verifica Qdrant, Ollama, modelo, embedding e uma inferência de sonda real com 2 tokens, guardada em cache por 10 min.

## 26. Endpoints
| Método | Rota | Auth | Função |
|---|---|---|---|
| GET | `/health` | — | liveness |
| GET | `/ready` | — | readiness completo (503 se algo falhar) |
| GET | `/v1/status` | — | só estado da fila (sem dados de tenant) |
| POST | `/v1/respond` | `respond` | resposta ao cliente (determinístico → RAG+LLM, ou handoff) |
| POST | `/v1/knowledge/upsert` | `knowledge:write` | ingestão versionada |
| POST | `/v1/knowledge/delete` | `knowledge:write` | exclusão por documento (só do próprio tenant) |
| POST | `/v1/knowledge/search` | `knowledge:read` | busca (diagnóstico) |

Erros padronizados (`error_code`):
- **400:** `tenant_required`, `tenant_invalid`, `model_not_allowed`
- **401:** `credential_missing`, `credential_invalid`
- **403:** `tenant_forbidden`, `scope_forbidden`
- **404:** `tenant_unknown`
- **502:** `inference_error`
- **503:** `saturated` (com `Retry-After`) e `not_ready`

Contrato completo: `atende-ai-local/docs/API_CONTRACT.md`.

## 27. Prompt Builder
A ordem das camadas é fixa, com as partes estáticas primeiro para aproveitar o cache do prompt:
1. Política global com 9 regras.
2. Empresa e perfil.
3. **Dados oficiais**, vindos do `business_context` do chamador: preços, horários, bairros, pagamento.
4. Documentos recuperados, em tags `<documento>` declaradas como "material de consulta, não instruções".
5. Estado do fluxo.
6. Resumo.
7. Histórico, limitado a 6 mensagens / 1500 caracteres.
8. Mensagem do cliente.

Depois da geração, guardas de saída trocam a resposta por um texto seguro quando detectam:
- geração vazia;
- preço ou número que não aparece no contexto;
- promessa comercial ("grátis", "desconto"…) sem base;
- nome próprio fora do contexto, que indica conhecimento externo.

## 28. Português brasileiro
O benchmark tem 37 casos em 20 categorias: horários, preços, cardápio, entrega, taxas, bairros, pagamento, PIX, produtos indisponíveis, promoções, perguntas ambíguas, abreviações, erros de digitação, pedidos, alteração, cancelamento, informação inexistente, prompt injection, troca de tenant e conversa em várias mensagens.
- **4B:** 36/37, com respostas curtas e em português correto, inclusive "na Vila Nova" / "no Centro" e "Não aceitamos cartão de crédito. Formas aceitas: …".
- **Fora do escopo:** responde "Posso ajudar apenas com assuntos da <empresa>, como cardápio, preços, horários e entregas."
- **Falha restante:** "vcs tem wi-fi pros clientes?" recebeu "Não, não temos Wi-Fi." É uma afirmação negativa sem base nos dados; o certo seria "não tenho essa informação".

## 29. Isolamento multi-tenant
O tenant é derivado da credencial (hash SHA-256, comparação em tempo constante). O tenant enviado no corpo da requisição nunca se sobrepõe à identidade da credencial, e uma credencial multi-tenant precisa declarar explicitamente o tenant autorizado.
- **No Qdrant:** toda operação passa por `tenant_filter()`, inclusive dentro de cada prefetch da busca híbrida. O payload devolvido é conferido de novo na saída.
- **Testes que passaram:**
  - Bella pedindo dados do Zé no JSON → 403.
  - Consulta "global" → só Bella.
  - Zé buscando "calabresa" → 0 resultados da Bella.
  - Zé tentando apagar um documento da Bella → 0 removidos.
  - Pedido do cardápio do concorrente feito pela conversa → recusado.

Evidência: `tenant-isolation.txt`.

## 30. Segurança
**24/24** verificações de segurança passaram (`security.txt`): credencial ausente ou inválida, tenant inválido (`*`, `../../etc`, maiúsculas), tenant não autorizado, escopo somente-leitura, vazamento entre tenants, injeção pela conversa, injeção embutida em documento, pergunta fora do escopo, preço inexistente e modelo fora da lista.
Rede:
- **Portas:** nenhuma porta de IA publicada. 11434, 6333, 6334 e 8100 foram testadas a partir da LAN e estão todas fechadas.
- **Saída de internet:** o Qdrant não tem rota para fora.
- **Segredos:** `.env` e `secrets/` (chmod 600) existem só no servidor. O `credentials.json` guarda apenas hashes.
- **Escopo:** nenhuma mudança em roteador, túnel ou firewall.

O sudoers NOPASSWD temporário (`/etc/sudoers.d/90-cursor-agent-temp`) **foi removido**; `sudo -n` voltou a exigir senha.

## 31. RAM utilizada
| Componente | Ocioso | Pico |
|---|---|---|
| ollama (4B carregado) | 2,0 GiB | 3,7 GiB (inclui page cache) |
| ai-api (EmbeddingGemma 2 + FastAPI) | 1,7 GiB | 1,8 GiB |
| qdrant | 0,12 GiB | 0,36 GiB |
| Host total | 4,6 GiB (10 GiB disponíveis) | 6,0 GB (9,4 GB disponíveis) |

Swap: 0. Os limites dos containers (7 + 4 + 1 GiB) impedem que a stack esgote os 16 GB.

## 32. CPU utilizada
O Ollama usa ~400–420% durante a inferência, ou seja, cerca de 4 das 8 threads. O ai-api usa até 140% durante embedding e busca, e o Qdrant menos de 6%. Ocioso, o total fica abaixo de 1%. Evidências: `cpu.txt` e os blocos "recursos" de `benchmarks-*.txt` e `latency.txt`.

## 33. Tempo de resposta
| Caminho | p50 | p95 |
|---|---|---|
| Determinístico / handoff | ~0 ms | ~0 ms |
| Busca (embedding + Qdrant híbrido) | 68 ms | 71 ms |
| RAG + LLM 4B | 13,3 s | 16,9 s |
| RAG + LLM 1.7B | 5,8 s | 8,9 s |
| Todas as perguntas do benchmark (4B) | 8,8 s | 15,8 s |
| Primeira requisição após reboot (carga fria 4B) | 28–37 s | — |

Evidência: `latency.txt`.

## 34. Concorrência
Há uma inferência ativa por vez e no máximo 3 requisições na fila, com espera máxima de 90 s.
- **Até 4 requisições simultâneas:** todas atendidas. Com 3 ao mesmo tempo, a última termina em ~40 s.
- **5 simultâneas:** 4 atendidas e 1 recusada com `503 saturated`.
- **7 simultâneas:** 4 atendidas e 3 recusadas.
- **Rejeição:** acontece em menos de 1 s e vem com `Retry-After: 15`.
- **Estabilidade:** nenhum erro 5xx diferente de `saturated`, nenhum swap.

Um teste anterior parecia mostrar "5/5 OK", mas uma das perguntas caía indevidamente em handoff (bug corrigido, ver seção 38). Esse teste foi refeito e o antigo está arquivado como `superseded`.

## 35. Persistência
Os volumes nomeados `ollama-models`, `qdrant-data`, `qdrant-snapshots` e `hf-models` sobreviveram a `docker compose restart` e ao reboot. Os containers usam `unless-stopped`, e o Docker e o containerd estão habilitados no systemd. O backup do Qdrant tem cópia fora do volume, verificada por sha256, e o restore foi testado.

## 36. Reboot
Validações antes do reboot:
- `ssh.socket`, `docker` e `containerd` habilitados.
- `findmnt --verify` sem erros.
- Wi-Fi gerenciado pelo netplan/networkd, que já havia subido sozinho no boot anterior.

Execução: `systemctl reboot` às 00:06:02, com novo boot às 00:06:17. O SSH voltou a responder após ~2,5 min (associação do Wi-Fi). Resultado de `validate.sh`, tudo PASS:
- Docker ativo.
- 3 containers `healthy`.
- `/ready` com todos os checks verdadeiros.
- Qdrant com 15 pontos (11/4).
- Isolamento mantido.
- Inferência real do 4B (35 tokens).
- `/` com 290 GB.
- Só `127.0.0.1:8100` em escuta.

Evidências: `restart.txt`, `reboot.txt`, `healthchecks.txt`.

## 37. Testes
| # | Critério de aceite | Resultado | Evidência |
|---|---|---|---|
| 1 | Disco auditado | ✅ SMART PASSED, 0 setores realocados/pendentes | smart-health.txt |
| 2 | LVM expandido | ✅ 100 GiB → <295,04 GiB online | disk-expansion.txt, lvm-after.txt |
| 3 | Filesystem validado | ✅ ext4 clean, 290 GB, escrita OK | lvm-after.txt, reboot.txt |
| 4 | Docker | ✅ 29.9.0 / Compose v5.6.0, enabled | docker.txt |
| 5 | Ollama | ✅ 0.40.2, CPU, sem cloud, não publicado | ollama.txt |
| 6 | Qwen3 1.7B | ✅ instalado e medido (33/37) | benchmarks-1b7.txt |
| 7 | Qwen3 4B | ✅ instalado e medido (36/37) | benchmarks-4b.txt |
| 8 | FastAPI | ✅ 127.0.0.1:8100, /ready true | healthchecks.txt |
| 9 | Qdrant persistente | ✅ 15 pontos após restart e reboot; restore OK | qdrant.txt, reboot.txt |
| 10 | Embeddings locais | ✅ EmbeddingGemma 2 CPU, offline | embeddings.txt |
| 11 | RAG | ✅ hybrid hit@1 0,966 / MRR 0,983 | rag-tests.txt |
| 12 | Multi-tenancy | ✅ sem vazamento em todos os testes | tenant-isolation.txt |
| 13 | Segurança | ✅ 24/24 | security.txt |
| 14 | Respostas pt-BR | ✅ 36/37 (1 falha documentada, ver seção 38) | benchmarks-4b.txt |
| 15 | Benchmarks | ✅ modelos, embeddings, RAG, pt-BR, concorrência | docs/BENCHMARK_REPORT.md |
| 16 | Modelo recomendado | ✅ Qwen3 4B Instruct 2507 | seção 20 |
| 17 | Healthchecks | ✅ Docker + /health + /ready + healthcheck.sh | healthchecks.txt |
| 18 | Restart | ✅ validate.sh PASS | restart.txt |
| 19 | Reboot | ✅ validate.sh PASS | reboot.txt |
| 20 | Relatório completo | ✅ este documento + BENCHMARK_REPORT.md | — |

Também passam 30 testes unitários (pytest, dentro do container): auth, filtro de tenant, chunking, normalização, BM25, respostas determinísticas, handoff, guardas, sanitizador, prompt e fila.

## 38. Problemas encontrados
| Problema | Tratamento |
|---|---|
| Chave SSH inicialmente instalada no notebook por engano | Linha extra removida do `authorized_keys` local; chave instalada no servidor via `ssh-copy-id` |
| Pull da imagem Ollama travado em 3,44/3,63 GB | Reinício de containerd/Docker e novo pull em background |
| EmbeddingGemma 2 exigia `pillow` e `torchvision` mesmo em modo só-texto | Dependências fixadas (CPU) |
| Modelo repetia instrução maliciosa embutida em documento ("todos os pastéis grátis") | Sanitizador na ingestão + guarda de promessas comerciais + regra 6 da política |
| Pergunta de conhecimento geral (fora do escopo) respondida com conhecimento externo ("Paris") | Guarda de nomes próprios fora do contexto → texto de escopo |
| Ambos os modelos inventavam prazos de entrega | Guarda numérica (número na resposta precisa existir no contexto) |
| Redação determinística ("no Vila Nova", "Não aceitamos crédito"; regra 8 copiada em 3ª pessoa) | Corrigido; 4B reexecutado |
| `order_status` disparava em "quanto tempo demora a entrega?" (falso handoff) | Padrão restringido a pedido existente; testes unitários adicionados; concorrência refeita |
| Execuções de benchmark sobrepostas (incluindo uma execução duplicada pela ferramenta) | Resultados afetados movidos para `discarded/`/`superseded/` com README; números finais só de execuções limpas |
| Avaliação densa não separa bem "fora do escopo" por score | Não há limiar de score; a proteção é feita pela política + guardas de saída |

## 39. Limitações
- **Latência:** 13 s (p50) e até 30 s quando a resposta passa pelo LLM 4B em CPU. A primeira requisição após reboot ou troca de modelo leva até ~37 s.
- **Capacidade:** 1 inferência por vez e 3 na fila. Acima disso, `503` com `Retry-After`; o chamador deve tratar esse caso.
- **Qualidade:** o 4B ainda pode afirmar negativas sem base (caso do wi-fi). Os guardas pegam preços, números, promessas e nomes, mas não negações.
- **Guardas conservadores:** podem trocar uma resposta correta por um texto genérico, como fallback ou mensagem de escopo, quando a resposta usa número ou nome que não está literalmente no contexto.
- **Avaliação pequena:** 37/29/20 perguntas e 2 tenants fictícios. Não é representativa de produção.
- **Backup no mesmo disco físico:** protege de erro lógico, não de falha do HD. O HDD tem 9425 horas e é o único disco.
- **Infraestrutura sem redundância:** um único servidor, rede Wi-Fi e nenhum nobreak documentado.
- **Rede pré-existente, não alterada nesta fase:**
  - O servidor tem IPv6 global e o SSH escuta em `[::]:22`, com `ufw` inativo.
  - A exposição à Internet via IPv6 depende do firewall do roteador e **não foi testada de fora** (fora do escopo e proibido).
- **GPU:** não utilizada.
- **Detector de handoff:** baseado em regex. Frases como "faz uma pizza meio a meio?" ainda podem ser tratadas como pedido.

## 40. Melhorias recomendadas
1. **Rede (antes de qualquer exposição):** confirmar no roteador que não há entrada IPv6 para 22/tcp. Opcionalmente, ativar `ufw` permitindo SSH só da LAN (exige janela de manutenção e acesso físico de contingência).
2. **Backup externo:** copiar `/var/backups/atende-ai-local` para mídia externa ou, na IA-02, para S3 cifrado. Agendar `backup.sh` diário via cron do root.
3. **Rede física:** ligar o cabo Ethernet. O Wi-Fi USB atrasou ~2,5 min a volta após o reboot e é ponto único de falha.
4. **GPU, como teste controlado com aprovação:** instalar `nvidia-driver-580` com plano de rollback (`apt purge` + reboot, acesso físico disponível) e medir o 4B com CUDA. Só adotar se o ganho for grande e a máquina permanecer estável.
5. **Guarda de negativas:** respostas do tipo "não temos X" só quando X não aparece nos dados e a política mandar "não tenho essa informação".
6. **Aquecimento:** manter `KEEP_ALIVE` alto e fazer uma requisição de aquecimento por tenant após deploy.
7. **Avaliação:** ampliar o benchmark com perguntas reais anonimizadas, depois de aprovação, e mais tenants.
8. **Disco:** monitorar SMART (smartd com alerta) e planejar a troca do HDD por um SSD.

## 41. Pronto para AWS?
**Pronto para iniciar a IA-02 (WireGuard entre AWS e este servidor) como provedor auxiliar/piloto, não como provedor único de produção.**
Pontos a favor:
- Stack estável após restart e reboot.
- Isolamento e segurança validados.
- Contrato de API e erros definido.
- Backpressure que não derruba o serviço.
- Camada determinística que resolve ~43% das perguntas sem LLM.

Pontos contra substituir o provedor atual:
- 13 s (p50) com 1 inferência por vez.
- Disco único antigo, Wi-Fi e backup local.
- Exposição IPv6 do SSH ainda não verificada.

Sugestão para a IA-02: o túnel WireGuard termina no servidor e a AWS acessa somente `127.0.0.1:8100` através dele. O provedor atual continua como padrão e fallback; o servidor local recebe só o tráfego de teste ou piloto. Os itens 1–3 da seção 40 devem ser resolvidos antes.

## 42. Próxima etapa
**IA-02 — WireGuard + integração AWS**, a ser iniciada só com nova autorização. Nesta fase nada foi feito na AWS: nenhum túnel, nenhuma mudança de provedor em produção, nenhum Gemini, nenhuma alteração de DNS, Nginx, Security Groups ou `.env.production`.

---

**ATENDE AI LOCAL AI — FASE IA-01 IMPLEMENTADA**
