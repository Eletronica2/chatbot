# Verificação empresarial da Meta e restrições de WABA (#141010, #131031)

Guia reutilizável para clientes Atende Ai quando a **WABA do portfólio proprietário** está restrita, com ou sem erro **#131031**, e o `health_status` mostra **BUSINESS LIMITED** ou **#141010**.

Documenta o caso **homologado em 26/11/2026** (tenant `pizzaria_bella_massa`, WABA `1299741078262298`, business `1348385330573371`, número final **3594**). Sem tokens, senhas ou dados pessoais.

Relacionado: [meta-waba-locked-131031.md](./meta-waba-locked-131031.md) (foco em billing **141006** e outras causas de #131031).

---

## Sintomas típicos

| Onde | O que aparece |
|------|----------------|
| Webhook envio | `failed` **#131031** — Business Account locked |
| Graph `health_status` | `BUSINESS` **LIMITED** — erro **#141010** (empresa não verificada no portfólio **dono da WABA**) |
| Graph WABA | `account_review_status` **PENDING** (enquanto negócio não verificado) |
| WhatsApp Manager | Conta restrita / “Verificar empresa” |
| Painel Atende Ai | Inbound OK, outbound falha ou IA sem resposta (outras causas abaixo) |

**Importante:** verificação do portfólio do **app** (ex.: Atende Ai) **não substitui** a verificação do portfólio **proprietário da WABA**. Compartilhar a WABA com o parceiro **não remove** a exigência.

---

## Caso real (26/11/2026) — causa comprovada

O portfólio **Pizzaria Bella Massa** (`1348385330573371`), dono da WABA, **não tinha** verificação empresarial concluída. O portfólio **Atende Ai** já estava verificado com o mesmo CNPJ/MEI, mas a Meta exige verificação **no business que possui a WABA**.

Contexto preservado: Embedded Signup V5, coexistência ativa, tokens e permissões corretos, sem migrar/desconectar número.

---

## Solução aplicada (oficial Meta)

1. **Meta Business Suite** → portfólio **proprietário da WABA** → **Central de Segurança**.
2. Caso de uso: configurar conta WhatsApp Business → verificação com **dados jurídicos verdadeiros** e documentação válida (CNPJ, endereço, telefone, site).
3. Concluir desafios (registro público, SMS, etc.) sem dados falsos.
4. Aguardar aprovação da Meta.
5. Conferir: business **Verificada**, messaging account **Aprovada**, `business_verification_status=verified`, `account_review_status=APPROVED`.
6. Rodar diagnóstico Graph (ver checklist): `health_status` **AVAILABLE** em WABA/BUSINESS/APP.
7. Teste real: inbound → fluxo/IA → outbound → webhooks **sent** → **delivered** (não confundir `delivered` de mensagens antigas).

---

## Resultado comprovado (pós-verificação)

- Business **VERIFIED** (25/11/2026 no portfólio Bella).
- WABA **APPROVED**, `status=ACTIVE`.
- `BUSINESS` / `WABA` `can_send_message` = **AVAILABLE**.
- Número **CONNECTED** / **LIVE**, coexistência (`is_on_biz_app=true`).
- **#141010** e **#131031** deixaram de ocorrer no teste E2E (26/11/2026 01:59 UTC).
- Webhook, Qwen3 local, outbound com **DELIVERED** confirmado.

---

## O que isso **não** resolve automaticamente

| Tópico | Nota |
|--------|------|
| Nome de exibição WhatsApp | Aprovação **separada**; pode manter `messaging_limit_tier` menor até aprovar nome |
| Templates de mensagem | Verificação empresarial **≠** aprovação de template UTILITY/MARKETING |
| Billing WABA | Cartão/método na WABA certa ainda necessário ([131031 por 141006](./meta-waba-locked-131031.md)) |
| Sessão em modo humano | `assignment_mode=human` **bloqueia IA** mesmo com WABA saudável — usar **Finalizar atendimento** / `return-to-ai` no painel |

---

## O que **não** fazer

- Desconectar número, migrar WABA para outro portfólio ou recriar WABA **antes** de ler `health_status` e `business_verification_status`.
- Presumir que todo **#131031** é falta de verificação (pode ser billing, política, PIN, etc.).
- Declarar campanhas/templates liberados só porque o business foi verificado.

---

## Checklist de diagnóstico (futuros clientes)

1. **Identificar o business dono da WABA** (não só o portfólio do SaaS): WhatsApp → conta de mensagens → “Propriedade de …”.
2. **Graph — número** `/{phone_number_id}?fields=health_status,status,display_phone_number,messaging_limit_tier`
3. **Graph — WABA** `/{waba_id}?fields=account_review_status,business_verification_status,health_status,status`
4. Anotar cada entidade em `health_status.entities[]`: `can_send_message`, `errors[]` (**141010**, **141006**, **131031**, etc.).
5. **Business Suite — Informações da empresa** do portfólio dono: status **Verificada**?
6. **WhatsApp Manager**: conta **Aprovada**? Pagamento ativo?
7. **Atende Ai — produção:** `python scripts/ia03_wa_health.py` no container `backend-api` (somente GET).
8. Se inbound OK e sem resposta: MySQL — `sessions.assignment_mode` e `human_handoff_pending`.
9. Teste controlado (1 número autorizado): confirmar **wamid novo** + **delivered** no mesmo wamid.
10. Se template/campanha: status **APPROVED** na Meta (Graph é fonte após sync); não enviar em **PENDING**.

Ferramentas: `scripts/check-meta-health.ps1`, `scripts/ia03_bella_monitor.sh` (rastreio sanitizado pós-teste).

---

## Referência rápida IDs (Bella Massa — homologação)

| Campo | Valor |
|-------|--------|
| Tenant | `pizzaria_bella_massa` (ID 5) |
| WABA | `1299741078262298` |
| Phone Number ID | `1155710810954749` |
| Business dono | `1348385330573371` |