# Benchmark — Atende AI Local (Fase IA-01)

Servidor: Intel i7-4790 (4C/8T, AVX2), 16 GB RAM, HDD Seagate ST3320418AS, Ubuntu 26.04.1, **inferência 100% CPU** (GTX 750 Ti não utilizada — ver relatório principal, seção GPU).
Stack: Ollama 0.40.2 (Docker), Qdrant 1.19.2, FastAPI (`ai-api`), EmbeddingGemma 2 (CPU, float32).
Todos os números abaixo são medições reais nesta máquina (2026-10-08/09). Nenhum valor é estimado ou simulado.
Resultados brutos: `/opt/atende-ai-local/bench-results/` no servidor (JSON + amostragem de `docker stats`/`free` a cada 5 s). Resumos sanitizados: `ai-local-evidencias/`.

## 1. Metodologia

| Benchmark | Script | O que mede |
|---|---|---|
| Modelo direto | `bench/model_bench.py` | 8 perguntas de atendimento com prompt real (~1000 tokens) direto no Ollama: carga fria, TTFT, tokens/s de prompt e geração, RAM do modelo |
| Embeddings | `bench/embeddings_bench.py` | 20 consultas pt-BR rotuladas (gírias, abreviações, erros de digitação) contra os documentos dos 2 tenants |
| Recuperação | `bench/rag_eval.py` | 29 consultas rotuladas, dense vs hybrid, sempre com filtro de tenant |
| pt-BR ponta a ponta | `bench/ptbr_bench.py` | 37 casos em 20 categorias via `POST /v1/respond`; cada caso tem termos esperados e proibidos |
| Segurança | `bench/security_tests.py` | 24 verificações (auth, tenant, escopo, vazamento, injeção, versionamento) |
| Concorrência | `bench/concurrency_bench.py` | N requisições simultâneas forçadas pelo caminho LLM (`allow_deterministic=false`) |

Execução: `scripts/benchmark.sh <tipo> [args]` (roda dentro do container `ai-api`). Execuções sobrepostas ou com bug de classificação foram movidas para `bench-results/discarded|superseded` (ver `bench-results/README.txt`) e não entram nos números.

## 2. Modelos (Ollama direto, CPU)

| Métrica | Qwen3 1.7B (q4_K_M) | Qwen3 4B Instruct 2507 (q4_K_M) |
|---|---|---|
| Tamanho em disco | 1,36 GB | 2,50 GB |
| RAM carregado (ctx 4096 / 8192) | 1,88 GB / 2,42 GB | 3,18 GB / 3,88 GB |
| Carga fria (disco frio → pronto) | 15,3 s | 23,1 s (28,3 s após reboot) |
| Prompt sem cache (~1000 tok) | 90 tok/s → TTFT 11,3 s | 35 tok/s → TTFT 29,1 s |
| TTFT com prefixo em cache, p50 | 0,47 s | 0,82 s |
| Geração, p50 | 13,9 tok/s | 7,0 tok/s |
| Total por resposta (8 perguntas), p50 / p95 | 2,3 s / 10,2 s | 5,1 s / 24,1 s |
| ctx 8192 vs 4096 | mesma velocidade, +0,5 GB RAM | mesma velocidade, +0,7 GB RAM |
| Tags `<think>` vazadas | 0 (API envia `think:false`) | 0 (modelo sem thinking) |

O custo dominante em CPU é a avaliação do prompt sem cache. O prompt foi ordenado com as camadas estáticas (política global → empresa → dados oficiais) no início para que o Ollama reaproveite o KV cache entre perguntas do mesmo tenant; a troca de tenant ou de documentos recuperados invalida parte do prefixo.

## 3. Embeddings

| Métrica | google/embeddinggemma-2 (768d) | intfloat/multilingual-e5-small (384d) |
|---|---|---|
| hit@1 / hit@3 / MRR | 0,95 / 1,00 / 0,975 | 0,95 / 1,00 / 0,967 |
| Latência por consulta, p50 | 76 ms | 16 ms |
| Indexação | 255 ms/chunk | 22 ms/chunk |
| RAM adicional | 1,55 GB | 0,63 GB |
| Carga | 7,6 s | 6,2 s |
| Licença | Apache-2.0 | MIT |

Escolhido: **EmbeddingGemma 2** (melhor MRR, prefixos de tarefa query/documento, carregado só o encoder de texto: 271 M de 740 M parâmetros). e5-small fica documentado como alternativa se RAM ficar escassa.

## 4. Recuperação (29 consultas, filtro de tenant obrigatório)

| Modo | hit@1 | hit@3 | MRR | Latência p50 |
|---|---|---|---|---|
| Dense (EmbeddingGemma 2) | 0,931 | 1,00 | 0,966 | 67 ms |
| **Hybrid** (dense + BM25/IDF, fusão RRF) | **0,966** | 1,00 | **0,983** | 68 ms |

Hybrid é o padrão (`RETRIEVAL_MODE=hybrid`, `top_k=3`): ganha em nomes de produto e abreviações sem custo de latência perceptível.

## 5. pt-BR ponta a ponta (37 casos, 20 categorias)

| Métrica | 4B (final, 2026-10-09 00:23) | 1.7B (2026-10-08 23:56) |
|---|---|---|
| Aprovados | **36/37** | 33/37 |
| Distribuição | 13 determinísticos, 21 RAG+LLM, 3 handoff | idem |
| Latência todas, p50 / p95 | 8,8 s / 15,8 s | 3,6 s / 7,9 s |
| Latência caminho LLM, p50 / p95 / máx | 13,3 s / 16,9 s / 29,8 s | 5,8 s / 8,9 s / 19,2 s |
| Geração | 7,1 tok/s | 14,3 tok/s |
| Nível determinístico / handoff | ~0 ms | ~0 ms |

Falhas 4B: `vcs tem wi-fi pros clientes?` → "Não, não temos Wi-Fi." (afirmação negativa sem base nos dados — regra 4 da política não foi respeitada).
Falhas 1.7B: confunde contexto em perguntas curtas (`a margerita leva oq?` → resposta sobre entrega; `vcs faz meio a meio?` → resposta sobre borda), não lista opções em pergunta ambígua e misturou palavra em inglês ("else").
Observação: a execução do 1.7B foi feita antes do ajuste final de redação (regra 8 e frases determinísticas); o 4B foi reexecutado depois. A política e os guardas são os mesmos para ambos.

## 6. Concorrência (4B, `LLM_CONCURRENCY=1`, fila máx. 3, timeout de fila 90 s)

| Simultâneas | OK | 503 `saturated` | Lote (wall) | Latência máx. |
|---|---|---|---|---|
| 1 | 1 | 0 | 14,9 s | 14,9 s |
| 2 | 2 | 0 | 16,1 s | 16,1 s |
| 3 | 3 | 0 | 40,1 s | 40,1 s |
| 5 | 4 | 1 | 50,3 s | 50,3 s |
| 7 | 4 | 3 | 58,1 s | 58,1 s |

Capacidade efetiva: **1 inferência ativa + 3 na fila**. Excedentes recebem `503 {"error_code":"saturated"}` com `Retry-After: 15` em < 1 s, sem degradar quem já está na fila. Pico de RAM do host 5,7–6,0 GB de 15,5 GB; swap 0. O Ollama usa ~4 threads (≈410% CPU) por inferência.

## 7. Recursos

| Situação | RAM host usada | ollama | ai-api | qdrant | swap |
|---|---|---|---|---|---|
| Ocioso, modelo carregado | 4,6 GiB (10 GiB disponíveis) | 2,0 GiB | 1,7 GiB | 0,12 GiB | 36 KiB |
| Pico (pt-BR / concorrência 4B) | 6,0 GB | 3,7 GiB* | 1,8 GiB | 0,12 GiB | 0 |

\* A memória reportada pelo `docker stats` para o Ollama inclui page cache dos arquivos do modelo.
Disco: 31 GB usados de 290 GB (modelos 3,6 GB, cache HF 3,6 GB, Qdrant < 2 MB, imagens 11,8 GB, cache de build 5,9 GB). Leitura sequencial do HDD: ~83 MB/s.

## 8. Limitações da medição

- Conjuntos pequenos (8/20/29/37 perguntas) e apenas 2 tenants fictícios: os números indicam tendência, não garantem precisão em produção.
- Latência medida com a máquina dedicada; outras cargas no host aumentam TTFT linearmente.
- A primeira requisição após troca de modelo ou reboot paga a carga fria (até ~28 s) — `/ready` faz uma inferência de sonda para aquecer.
