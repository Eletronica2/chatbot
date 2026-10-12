# Multi-tenancy

## Princípios

1. **Identidade prevalece sobre o JSON.** Cada credencial de serviço tem uma lista fechada de tenants e escopos
   (`respond`, `knowledge:read`, `knowledge:write`). `tenant_id` no corpo:
   - ausente → usa o único tenant da credencial; se a credencial tiver vários → 400 `tenant_required`;
   - formato inválido (`*`, `../`, maiúsculas, espaços) → 400 `tenant_invalid`;
   - fora da lista da credencial → 403 `tenant_forbidden` (nunca é "corrigido" silenciosamente);
   - autorizado mas não cadastrado em `config/tenants.json` → 404 `tenant_unknown`.
2. **Isolamento na camada de dados, não no prompt.** Toda leitura, escrita, contagem e exclusão no Qdrant passa por
   `tenant_filter(tenant_id)`, que recusa tenant vazio/inválido (`TenantScopeError`) e gera um filtro `must`
   aplicado **no servidor** — inclusive dentro de cada `prefetch` da busca híbrida. Não existe rota de busca global.
3. **Verificação de saída.** Cada ponto retornado é conferido; payload de outro tenant gera erro em vez de resposta.
4. **Coleção única** `atende_knowledge` com índice de payload `tenant_id` (`is_tenant=true`), que agrupa os dados
   por tenant no armazenamento do Qdrant.

## Ciclo de vida de documentos

- `upsert`: chunking por seção → embeddings → pontos com `tenant_id, document_id, document_version, section,
  chunk_id, content_hash, updated_at, source`. A versão nova é gravada e em seguida **todos** os chunks de outras
  versões do mesmo documento (no mesmo tenant) são removidos.
- `delete`: remove por `tenant_id + document_id`; um tenant não consegue apagar documento de outro (0 chunks).
- Conversas do WhatsApp **não** são indexadas na base de conhecimento.

## Credenciais (fase IA-01)

Geradas pelo `scripts/bootstrap.sh` no servidor: tokens aleatórios em `secrets/tokens.env` (600) e apenas
hashes SHA-256 em `config/credentials.json`. Credenciais de teste:

| key_id | tenants | escopos |
|---|---|---|
| bella-svc | pizzaria_bella_massa | respond, knowledge:read, knowledge:write |
| ze-svc | pastelaria_do_ze | respond, knowledge:read, knowledge:write |
| bella-readonly | pizzaria_bella_massa | respond, knowledge:read |
| multi-test | ambos | respond, knowledge:read |

Na IA-02, a AWS receberá uma credencial própria (escopo por tenant ou lista de tenants) via WireGuard.
