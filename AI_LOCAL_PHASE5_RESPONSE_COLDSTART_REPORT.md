# Atende Ai — IA-05: respostas objetivas e partida a frio do Qwen3 local

Data: 27/10/2026.
Tenant de referência: Bella Massa (`pizzaria_bella_massa`).
Nenhuma mensagem WhatsApp enviada. WABA 3594, coexistência, Billing V2, integração Meta e outros tenants não alterados. Sem push.

## Resumo

| Indicador | Fase 4 | Fase 5 |
| --- | --- | --- |
| Turno de IA em conversa real, média (mesmas 2 conversas, 10 turnos) | 12,6 s | **9,7 s** (−23%) |
| Conversa com contexto (B) | 14,6 s | **7,4 s** (−49%) |
| Tokens gerados por turno, média | 46,8 | **29,5** (−37%) |
| Geração (decode) por turno, média | 8,8 s | **5,9 s** (−33%) |
| Ofertas não solicitadas / emojis nas respostas da IA | frequentes ("Quer saber sobre outro sabor ou combo? 😊") | **0** |
| 1ª mensagem logo após restart completo | 43,6 s | **25,7–29,6 s** |
| 2ª mensagem logo após restart | 29,1 s | **17,2 s** |
| Mensagem com cache quente após restart | 4,5 s | 5,0–5,4 s |
| Taxa de acerto | 10/10 (conversas), 10/10 (bancada) | **10/10 (conversas), 12/12 (bancada)** |

- Todas as primeiras mensagens após restart ficaram abaixo do prazo de produção (44,5 s), sem handoff e sem descarte.
- Os timeouts não foram alterados.

## 1. Respostas objetivas (configurável por tenant)

**Configuração:** `"response_style": "concise"` em `atende-ai-local/config/tenants.json`. Padrão `standard`; ativado só na Bella.

**Regras de estilo** (bloco estável depois do perfil da empresa, parte do prefixo em cache):
- Até duas frases para perguntas simples, só com o que foi perguntado.
- Sem tamanho ou variação informada: listar todas as opções em uma frase (a v1 respondia só "média" para "Qual o preço da calabresa?", o que foi corrigido).
- Não oferecer produtos, combos, sabores ou promoções não pedidos; não terminar com pergunta de venda.
- Não repetir saudação, apresentação ou cardápio.
- Listas, comparações e várias informações: resposta completa.
- Evitar emojis.
- Exemplos com placeholder (`R$ <preço>`) para não vazar preço de um tenant para outro.

**Pós-processamento** (somente estilo conciso, nunca quando um guarda já atuou):
- Remove apenas a frase final quando for pergunta de oferta ("Quer…", "Gostaria…", "Posso te sugerir…").
- Nunca remove a oferta de encaminhamento à equipe, nunca esvazia a resposta e não atua se o cliente pediu sugestões ou combos.
- Respostas como "não está listada nos dados da empresa" viram a resposta padrão de desconhecido, com encaminhamento (regra 4 da política).

**Medição:**

| Teste | Padrão | Conciso |
| --- | --- | --- |
| Conversas reais (dry-run AWS → backend → Flow → Qwen3) | 46,8 tokens / 12,6 s | **29,5 tokens / 9,7 s** |
| Bancada de 12 perguntas isoladas, cache quente | 28,1 tokens / 6,0 s / 12/12 | 28,4 tokens / 6,8 s / 12/12 |

- O ganho vem das conversas: com histórico, o modelo padrão alongava e oferecia upsell.
- Em perguntas isoladas as respostas já eram curtas, e o bloco de estilo acrescenta cerca de 230 tokens ao prefixo (cacheados, +0,35 s de processamento). Sem ganho ali, mas também sem perda de acerto.
- Exemplos finais:
  - "Quanto custa a pizza grande de calabresa?" → "A pizza grande de calabresa custa R$ 62,90."
  - "Qual o preço da calabresa?" → "A calabresa custa R$ 42,90 no broto, R$ 52,90 na média e R$ 62,90 no grande."
  - "Quais são os sabores de pizza doce?" → lista completa.

## 2. Partida a frio

**Diagnóstico (Fase 4):** após o restart, a primeira mensagem esperava a carga do modelo e processava o prompt inteiro a frio. O cancelamento do aquecimento em segundo plano levava cerca de 13 s, porque o Ollama só percebe o cancelamento entre lotes de 512 tokens.

**Alterações:**

1. **Aquecimento em estágios:**
   - Carga do modelo + "cabeça" do prompt (política + empresa + estilo, 810 tokens), que todo prompt do tenant compartilha. Não cancelável, cerca de 22 s a frio.
   - Depois, o prefixo completo da base em segundo plano, cancelável por mensagem de cliente.
2. **Política fria = RAG:** com prazo e sem o prefixo completo em cache, a requisição sempre usa RAG sobre a cabeça em cache (cerca de 15 s) em vez do contexto completo frio (32–52 s). Configurável (`FULL_CONTEXT_COLD_POLICY=fit` mantém o critério antigo de "cabe no prazo").
3. **Rastreio da cabeça em cache** e custo frio a partir dos tamanhos medidos no aquecimento (a estimativa por caracteres subestimava: 1036 contra 1374 tokens).
4. **Se nem a cabeça estiver em cache**, o RAG usa 2 trechos em vez de 3.
5. **Modelo descarregado sem a API saber** (Ollama reiniciado ou `keep_alive` expirado): consulta `/api/ps` antes de confiar no cache.
6. **`num_batch=128` em todas as chamadas:**

   | `num_batch` | Prefill | Liberação após cancelamento |
   | --- | --- | --- |
   | 512 | 29,2 tok/s | 12,95 s |
   | 256 | 26,7 tok/s | 4,7 s |
   | 128 | 26,6 tok/s | **0,84 s** |

   Custo: cerca de +0,2 s por turno quente.
7. `/ready` reaproveita a cabeça ou o prefixo residente em vez de expulsá-lo.
8. **Timeout** durante a inferência: o estado do cache passa a "desconhecido"; a mensagem segue para o humano (preservada).

**Restart completo da stack local** (Ollama + Qdrant + API) e mensagens pelo caminho real AWS → HMAC → WireGuard:

| Momento | Fase 4 | Fase 5 final |
| --- | --- | --- |
| API healthy | 16 s | 15–17 s |
| 1ª mensagem imediata | 43,6 s | 29,6 s (13,4 s de fila na cabeça + 12,6 s de prefill RAG) |
| 2ª mensagem imediata | 29,1 s | 17,2 s |
| +30 s (reaquecimento ainda em andamento) | — | 23,2 s (RAG) |
| +90 s | 4,5 s | 5,0–5,4 s (contexto completo) |

- Rodadas intermediárias: política "fit" → 36,6 s e 51,9 s (o 2º caso motivou a política fria = RAG); política RAG com `num_batch` 512 → 25,7 s e 29,6 s.
- **Ordem de inicialização:**
  - Compose: `ai-api` só sobe com Ollama e Qdrant healthy.
  - Após reboot do host, o túnel WireGuard sobe cerca de 2 min depois (netwatch), quando o aquecimento já terminou.
  - No restart só de contêineres (deploy), mensagens podem chegar já com a API healthy, cenário medido acima.

## 3. Bancadas e memória

- Todas sequenciais, com `flock` e `timeout` dentro e fora do contêiner. Nenhum processo residual.
- Novo `atende-ai-local/scripts/run_bench.sh` aplica lock e timeouts e **sempre reinicia o `ai-api` ao final**. Benchmarks usam o Ollama diretamente; sem esse restart, a API acreditaria em um cache que já não existe (verificado nesta fase e corrigido com restart).
- **Memória** (sem mudança em relação à Fase 4; `num_ctx` 4096 mantido):

  | Componente | Uso |
  | --- | --- |
  | Ollama | 3,26–3,32 GiB (modelo 3,2 GB) |
  | `ai-api` | 1,69 GiB (modelo de embeddings) |
  | Qdrant | 46 MiB |
  | Host | 15 GiB, cerca de 9,3 GiB disponíveis |

- Evidências em `ai-phase2-evidencias/ia05/`.

## 4. Testes

| Componente | Resultado |
| --- | --- |
| API local | **110 passando** (16 novos) |
| Flow Engine e AI Engine | inalterados nesta fase (39 e 18 passando na Fase 4) |

Os 16 testes novos cobrem:
- estilo por tenant;
- filtro de oferta (casos removidos e preservados);
- normalização de desconhecido;
- custo frio medido;
- RAG reduzido sem cabeça;
- modelo descarregado;
- `num_batch` em toda chamada;
- aquecimento em estágios.

**Isolamento:** bloco de estilo e cache são por tenant; exemplos sem dados reais. Guardas inalterados e ativos (0 disparos falsos nas conversas finais).

## 5. Deploy e rollback

- Deploy local em etapas, cada uma com 109–110 testes no build antes de subir.
- Imagens anteriores: `atende-ai-local/ai-api:pre-phase5-20261027`, `pre-coldpolicy-20261027`, `pre-numbatch-20261027`.
- Códigos e `tenants.json` anteriores em `~/backups/ia05-20261027/` no servidor.
- Rollback do estilo: remover `response_style` da Bella e reiniciar o `ai-api`.
- Commits locais: `4029ee4`, `20d2c18`, `74a2f60` e o relatório.

## 6. Pendências e próximos passos

1. **Pior caso da 1ª mensagem:** uma mensagem chegando no instante zero de um restart, com o modelo fora do cache de disco (reboot: carga de 18–29 s), pode chegar a cerca de 45–50 s.
   - Após reboot o túnel ainda não está de pé, o que mitiga.
   - Para deploys, uma opção é atrasar a liberação da porta do túnel até o fim do estágio de cabeça.
2. **Piso de latência quente ≈ 5 s** (geração a cerca de 7 tokens/s em CPU). Abaixo disso só com modelo menor para perguntas simples, GPU ou CPU mais rápida.
3. **Contexto completo frio ≈ 50–65 s** de prefill (2184 tokens): só acontece em segundo plano. Mais de um tenant em modo completo exigirá `OLLAMA_NUM_PARALLEL=2` (mais RAM de KV).
4. **Teste real pelo número de teste da Meta** (+1 555-656-7513), mediante sua autorização.
