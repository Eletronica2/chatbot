# Atende Ai Local AI — Arquitetura (Fase IA-01)

## Visão geral

```
                (IA-02: AWS backend → WireGuard)
                               │
                     127.0.0.1:8100 (host)
                               │
                ┌──────────────▼──────────────┐
                │  ai-api (FastAPI)           │  rede ai_egress (porta publicada só em loopback)
                │  - auth serviço→tenant      │
                │  - prompt builder           │
                │  - RAG (EmbeddingGemma 2)   │
                │  - fila/backpressure        │
                └──────┬───────────────┬──────┘
         rede ai_internal (internal: true, sem saída)
                ┌──────▼─────┐   ┌─────▼──────┐
                │  ollama    │   │  qdrant    │
                │ Qwen3 CPU  │   │ atende_    │
                │ (sem porta)│   │ knowledge  │
                └────────────┘   └────────────┘
```

- **ollama** (`ollama/ollama:0.40.2`): inferência CPU, `OLLAMA_NUM_PARALLEL=1`, `OLLAMA_MAX_LOADED_MODELS=1`,
  `OLLAMA_NO_CLOUD=1`, `CUDA_VISIBLE_DEVICES=""`, keep-alive 30 min, contexto padrão 4096. Sem porta publicada.
  Também está em `ai_egress` apenas para baixar modelos.
- **qdrant** (`qdrant/qdrant:v1.19.2`): só na rede interna, API key obrigatória, telemetria desligada.
  Coleção única `atende_knowledge` com vetor denso `dense` + vetor esparso `bm25` (IDF no servidor).
- **ai-api**: FastAPI (1 worker), única porta publicada: `127.0.0.1:8100`.

## Fluxo de `/v1/respond` (estratégia em 3 níveis)

1. **Autenticação**: Bearer token → credencial (hash SHA-256) → tenants e escopos autorizados.
   O tenant efetivo vem da identidade; tenant divergente no JSON → 403.
2. **Handoff**: pedidos, alterações, cancelamentos e status → resposta fixa + `actions[handoff_required]`.
   O LLM nunca confirma pedido, pagamento, agendamento ou entrega.
3. **Nível 1 — determinístico**: preço, horário, entrega por bairro e formas de pagamento a partir do
   `business_context` (dados estruturados do Atende Ai). Só responde se **toda** a pergunta foi coberta;
   ambiguidade (ex.: "calabresa" sem tamanho) ou partes extras → sobe de nível. Sem LLM.
4. **Nível 2/3 — RAG + LLM**: embedding da pergunta → busca híbrida (denso + BM25 + RRF) filtrada pelo
   tenant no servidor → prompt em camadas → Qwen3 via fila → pós-processamento:
   - remoção de blocos `<think>`;
   - **guarda de preço**: qualquer `R$` na resposta que não exista nos dados estruturados, documentos
     recuperados, histórico ou mensagem → resposta substituída por fallback seguro (`guard=price_not_in_context`).

## Prompt Builder (ordem das camadas)

`GLOBAL POLICY` → `EMPRESA ATUAL/perfil` → `ESTADO DO ATENDIMENTO` (flow_context, chaves permitidas) →
`DADOS OFICIAIS` (business_context) → `DOCUMENTOS` (cercados por `<documento>`, declarados como não-instruções)
→ histórico recente (≤6 mensagens / 1500 caracteres) → mensagem do usuário.
As camadas estáticas vêm primeiro para reaproveitar o cache de prefixo do Ollama.

## Fila / backpressure

`InferenceGate`: semáforo (`LLM_CONCURRENCY=1`) + fila limitada (`LLM_MAX_QUEUE=3`) + timeout de espera
(`LLM_QUEUE_TIMEOUT_S=90`). Excedeu → HTTP 503 `{"error_code":"saturated","retry_after_s":N}` com header
`Retry-After`, para a AWS aplicar retry, fallback ou transferência humana.

## Persistência

Volumes nomeados: `ollama-models`, `qdrant-data`, `qdrant-snapshots`, `hf-models`. Configuração em `./config`
(somente leitura no container). Segredos em `.env` e `secrets/` (chmod 600, fora do git).
