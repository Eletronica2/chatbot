# Atende Ai — IA-04: contexto completo no Qwen3 e roteamento de perguntas específicas

Data: 27/10/2026.
Tenant de referência: Bella Massa (`pizzaria_bella_massa`, tenant 5), número de teste Meta do Atende Ai.
Nenhuma mensagem real enviada. WABA 3594, coexistência e outros tenants não tocados. Sem push.

## Resumo

| Indicador (Qwen3 4B, CPU i7-4790) | Antes (RAG) | Depois (contexto completo) |
| --- | --- | --- |
| Pergunta isolada, cache quente (benchmark, média de 8–9 perguntas) | 18,4 s | **6,0 s** |
| — processamento do prompt | 14,7 s | **1,2 s** |
| — geração | 3,6 s | 4,8 s |
| Pergunta curta pelo caminho real AWS → HMAC → WireGuard → API local | 13–28 s | **4,3–4,9 s** |
| Turnos de IA em conversa real (dry-run backend + Flow + AI Engine) | 23–37 s (com menu repetido) | **7,8–19,4 s** (média 12,6 s) |
| Qualidade nos 10 casos de referência | 10/10 | **10/10** |
| "Quanto custa a pizza de calabresa?" | menu genérico | **preço da calabresa** |

- A meta de 3–5 s foi atingida para respostas curtas com o cache quente.
- Em conversa, o gargalo passou a ser a **geração**: cerca de 7 tokens/s; respostas de 50–80 tokens levam 7–15 s.

## Etapa 1 — contexto completo no prefixo do prompt

**Como funciona:**
- Ativado por tenant em `atende-ai-local/config/tenants.json` (`"context_mode": "full"`). O padrão é RAG.
- Só vale se a base couber nos limites: `FULL_CONTEXT_MAX_TOKENS=1800` (estimativa pessimista de 3 caracteres/token) e `FULL_CONTEXT_MAX_CHUNKS=40`.
  - Fora disso, a resposta cai para o RAG com Qdrant e o motivo é registrado (`too_many_tokens`, `too_many_chunks`, `empty`).
  - A Bella tem 8 documentos (≈1036 tokens estimados; o prompt total real tem ≈1950).
- Os documentos entram em ordem estável logo após a política e o perfil da empresa. Assim o warm-up calcula exatamente o mesmo prefixo das requisições reais.

**Isolamento:**
- O snapshot é lido com o mesmo `tenant_filter` do Qdrant e cada chunk é rejeitado se não for do tenant.
- O cache é indexado por tenant.
- Os guardas de preço, número e nome validam contra os documentos que entraram no prompt. O preço de outro tenant é bloqueado (testado).

**Invalidação:**
- Impressão digital = manifesto do registry (id, versão, hash, status) + contagem de chunks no Qdrant.
- Toda escrita (sync, upsert, delete) também invalida explicitamente.
- Validado ao vivo pelo HMAC da AWS: um documento temporário "estacionamento, 6 vagas" foi sincronizado. A resposta mudou para "Sim, temos estacionamento próprio com 6 vagas…" e, após a remoção, voltou para "Não tenho essa informação confirmada…". O documento temporário foi removido.

**Sem assumir que o Ollama mantém o cache:**
- Com um único slot, o cache guarda apenas o último prompt. A API rastreia qual prefixo está residente.
- Se o prefixo está frio e não cabe no prazo do chamador (estimativa ≈30 tokens/s), aquela requisição usa RAG (`fallback_reason=kv_cold`). O prefixo é reconstruído em segundo plano quando ocioso.
- Mensagem de cliente sempre cancela essa reconstrução.
- O `/ready` reaproveita o prefixo residente (1 token, cerca de 1 s) em vez de expulsá-lo. A sonda genérica só roda sem prefixo residente.
- O warm-up de startup é o mesmo mecanismo cancelável.

**Histórico fixo por conversa:**
- A janela de histórico só cresce entre requisições (até 2× o limite) e então recomeça.
- A AWS passou a enviar até 12 mensagens ao provider local, e a cópia da mensagem atual é removida do histórico.
- Cada prompt é prefixo do seguinte (testado).
- Efeito: processamento do prompt em conversa de 3,3–11,5 s para 2,1–3,8 s na maioria dos turnos.

**Recuperação após reinicialização** (stack local inteira reiniciada e pergunta imediata):

| Momento | Modo | Tempo |
| --- | --- | --- |
| Imediatamente | RAG (`kv_cold`) | 43,6 s (inclui carga do modelo) e 29,1 s |
| ≈75 s depois | contexto completo | **4,5 s e 4,3 s** |

**Benchmark RAG × contexto completo** (`bench/context_bench.py`, mesmas 10 perguntas):

| Fase | RAG | Completo |
| --- | --- | --- |
| Primeira pergunta (prefixo novo) | 21,5 s | 52,4 s |
| Quente, média | 18,4 s | 6,0 s |
| Após expulsão forçada do cache (sem prazo) | 24,3 s | 52,7 s |

- O caso frio mais caro do modo completo é o motivo do desvio `kv_cold` acima; com o prazo de produção ele não ocorre.
- Qualidade 10/10 nos dois modos: preços da calabresa e do frango por tamanho, "pizza grande" (45 cm), Wi-Fi → "não confirmado", pepperoni (inexistente) sem preço inventado, horário de domingo, PIX e pergunta fora do assunto.

## Etapa 2 — roteamento de perguntas específicas (opt-in por fluxo)

**Opção:**
- `prefer_ai_for_specific_questions: true` (padrão `false`) e, opcionalmente, `specific_question_generic_terms`.
- Ativada só no fluxo da Bella. Nenhum outro tenant tem fluxo no Flow Engine.

**Pergunta específica** = formulada como pergunta + não é navegação ("quero ver o cardápio", "menu") + tem pelo menos um termo concreto além dos genéricos.

**O que é pulado e o que continua igual:**
- Pula apenas regras por palavra-chave (`contains:`, gatilhos de intenção) e a saudação inicial.
- Continuam determinísticos:
  - transferência para atendente;
  - estados de coleta (pedido em andamento);
  - opções numéricas (`equals:`);
  - regex;
  - navegação clara.

**Matriz validada no fluxo real da Bella:**

| Mensagem | Antes | Depois |
| --- | --- | --- |
| Quanto custa a pizza de calabresa? | menu genérico | IA: broto 42,90 / média 52,90 / grande 62,90 |
| Vocês têm pizza grande? / Qual o preço da calabresa? / Quanto custa uma pizza de frango? / Vocês oferecem Wi-Fi? | IA (mas após palavra-chave em alguns estados) | IA |
| Quero ver o cardápio. (no estado cardápio) | **abria pedido** ("qual é o seu nome?") | cardápio |
| Qual o horário? / Tem promoção hoje? | determinístico | determinístico |
| Quero fazer um pedido / Posso falar com um atendente? | determinístico | determinístico |

- O fluxo da Bella também ganhou "cardápio/menu" antes de "quero/pedido" no estado `cardapio_principal`.

## Correções encontradas na validação

- **Guarda de entidades:** tratava "Preço" no início de linha Markdown ("…  \nPreço:") como nome próprio inventado e trocava respostas corretas pela mensagem "fora do assunto". Agora ignora inícios de linha com espaços ou marcadores. Nomes no meio da frase continuam bloqueados (Morumbi, Heineken, Paris, Margherita).
- Os guardas registram o termo que os acionou (nunca o texto da mensagem).

## Testes

| Componente | Resultado |
| --- | --- |
| API local | 94 passando (15 novos: isolamento, limites, invalidação, fallback RAG, cache frio/quente, prefixo, histórico fixo, prontidão, guardas) |
| Flow Engine | 39 passando (21 novos) |
| AI Engine | 18 passando |
| Backend | 111 (+35 que exigem MySQL), sem alteração nesta fase |

**Isolamento multi-tenant:** chave da Bella para outro tenant → 403; segredo errado → 401.

## Deploy e rollback

**API local:**
- Imagens anteriores marcadas `atende-ai-local/ai-api:pre-*-20261027`.
- Códigos e `tenants.json` anteriores em `~/backups/ia04-20261027/` no servidor.
- Rollback rápido do modo: remover `context_mode` da Bella e reiniciar o `ai-api` (volta ao RAG).

**AWS:**
- Flow Engine (`pre-specific-questions-20261027`) e AI Engine (`pre-history12-20261027`) com imagens e arquivos anteriores em `/var/backups/atende-ai-ia02/pre-ia03-bella-20261022T012139Z/`.
- Rollback do roteamento: remover `prefer_ai_for_specific_questions` do YAML da Bella.

**Benchmarks:** rodaram um por vez (`flock`), com `timeout` dentro e fora do contêiner e limpeza ao final.

## Limitações e próximos passos

1. **Geração é o gargalo.** Respostas em conversa ficaram mais longas (oferecem "outro sabor ou combo"). Reforçar na política "até 2 frases, sem oferecer produtos não pedidos" deve cortar 30–50% do tempo sem perder precisão. Precisa de nova validação.
2. **Primeiro minuto após reinicialização:** cache frio em qualquer modo (RAG ≈30–44 s, perto do prazo de 44,5 s). Melhorias: prazo maior só para requisições com cache frio, ou reboot fora do horário.
3. **Expulsão desconhecida do cache:** qualquer uso direto do Ollama fora da API (por exemplo um benchmark manual) faz a próxima requisição pagar o prefixo inteiro e pode estourar o prazo uma vez. Por isso os benchmarks devem rodar com o lock e reiniciar o `ai-api` ao final.
4. **Um único slot:** com mais de um tenant em modo completo, cada troca de tenant esfria o cache do outro. `OLLAMA_NUM_PARALLEL=2` é a evolução natural (mais RAM de KV, sem perda para um tenant).
