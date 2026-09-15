# Erro #131031 — Business Account locked

Guia para diagnosticar e resolver quando mensagens falham com `status: failed` e código **131031** no webhook da Meta.

---

## Sintoma no webhook Meta

```json
{
  "status": "failed",
  "errors": [{
    "code": 131031,
    "title": "Business Account locked",
    "message": "Business Account locked",
    "error_data": { "details": "Business account has been locked." }
  }]
}
```

Isso **não** é erro de destinatário de teste (`#131030`) nem token inválido. A Meta aceita o envio (gera `wamid`) mas **bloqueia a entrega** na camada WABA.

---

## Diagnóstico automático (Health Status API)

```powershell
$env:META_ACCESS_TOKEN = "<seu_token>"
powershell -ExecutionPolicy Bypass -File scripts/check-meta-health.ps1
```

Ou manualmente:

```http
GET https://graph.facebook.com/v22.0/1121301321069602?fields=health_status
Authorization: Bearer <TOKEN>
```

### Resultado atual deste projeto (30/05/2026)

| Entidade | ID | can_send_message | Causa |
|----------|-----|------------------|-------|
| PHONE_NUMBER | `1121301321069602` | AVAILABLE | OK |
| **WABA** | **`1651453995905846`** | **BLOCKED** | **Erro 141006 — método de pagamento** |
| BUSINESS | `2330602324386620` | AVAILABLE | OK |
| APP | `1009915888389805` | AVAILABLE | OK |

**Causa raiz:** WABA bloqueada porque há **erro no método de pagamento** (`141006`). Mensagens iniciadas pelo negócio ficam bloqueadas até corrigir billing.

**Empresa verificada ≠ WABA liberada:** verificação na Central de Segurança não resolve billing da WABA.

---

## Como corrigir (método de pagamento)

1. Abra **Billing Hub**: https://business.facebook.com/billing_hub/accounts
2. Selecione a conta de negócios vinculada ao WhatsApp
3. **Adicione ou atualize** cartão/método de pagamento válido
4. Em **WhatsApp Manager**: https://business.facebook.com/wa/manage/home/
   - Confirme que a WABA `1651453995905846` está associada à conta de billing correta
5. Aguarde alguns minutos e rode novamente `scripts/check-meta-health.ps1`
6. Quando `can_send_message` = **AVAILABLE** no nó WABA, reteste envio na API Setup

Documentação Meta: [WhatsApp Business Platform pricing](https://developers.facebook.com/docs/whatsapp/pricing)

---

## Se não for pagamento (outras causas de 131031)

**Caso deste projeto (30/05/2026):** Health Status confirmou erro **141006 — método de pagamento inválido/ausente**. Corrija billing **antes** de abrir ticket de apelação.

| Causa | Onde verificar | Ação |
|-------|----------------|------|
| Violação de política | https://business.facebook.com/accountquality | Request Review |
| Dados do negócio incompletos | https://business.facebook.com/settings/info | Preencher website, nome legal |
| Restrição na WABA | https://business.facebook.com/business-support-home | Apelar / suporte |
| PIN 2FA incorreto | WhatsApp Manager → número | Resetar PIN e re-registrar |

---

## Texto para ticket Meta (se billing OK e erro persistir)

```
App ID: 1009915888389805
WABA ID: 1651453995905846
Phone Number ID: 1121301321069602
Display number: +1 555-651-6123

Error: #131031 Business Account locked on message delivery webhook.
Business verification: completed.
Health Status API shows WABA can_send_message: BLOCKED (or AVAILABLE but delivery still fails).

Please review and unlock messaging for this development / Tech Provider app.
```

Suporte: https://developers.facebook.com/support/

---

## Depois do desbloqueio — alinhar Atende Ai

IDs corretos da conta atual:

| Campo | Valor |
|-------|-------|
| WABA (`account_key`) | `1651453995905846` |
| Phone Number ID | `1121301321069602` |
| Número exibido | `+1 555-651-6123` |

Backoffice → **WhatsApp** → conta Bella Massa → atualizar **account_key (WABA)**, **Phone Number ID** e **Access Token** se necessário.

Reteste:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/smoke-test-app-review.ps1
```
