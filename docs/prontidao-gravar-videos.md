# Prontidão para gravar vídeos App Review

Última verificação automática: **06/06/2026**

---

## Resumo executivo

| Item | Status |
|------|--------|
| Stack Atenda Ai (Docker) | **OK** — smoke test passou |
| Envio pelo painel Atenda Ai | **OK** — `Message sent successfully` para `553492665547` |
| Cloudflare tunnel | **Ativo** — ver URL abaixo |
| Health API — WABA billing | **Ainda BLOCKED** (erro 141006) — pagamento pode não ter propagado |
| Gravar Vídeo 1 agora? | **Só se a mensagem chegar no seu celular** |
| Gravar Vídeo 2 agora? | **Sim, após renovar token** — criar modelo → PENDING |
| Tela Templates WhatsApp (envio teste) | **Implementada** — só envia APPROVED para `5534992665547` |

---

## Health Meta (billing)

Rodar com token **da API Setup** (não use token de app deletado):

```powershell
$env:META_ACCESS_TOKEN = "<token de https://developers.facebook.com/apps/1009915888389805/whatsapp-business/wa-dev-console/>"
powershell -ExecutionPolicy Bypass -File scripts/check-meta-health.ps1
```

Último resultado com token válido: WABA `1651453995905846` ainda **BLOCKED** com **141006** (método de pagamento).

Mesmo assim a Graph API **aceitou** envios (`wamid` + HTTP 200). Confirme no **celular** e no **webhook Meta** se o status é `delivered` ou ainda `failed` + `#131031`.

---

## Stack local (pronto)

```text
Webhook tunnel: https://anymore-control-bundle-flexibility.trycloudflare.com/webhook
Verify token:   super-secret-webhook-token
```

Configure na Meta → WhatsApp → Webhook → Callback URL (URL muda se reiniciar o túnel).

```powershell
cd infra
docker compose up -d
cloudflared tunnel --url http://localhost:40000
powershell -ExecutionPolicy Bypass -File scripts/smoke-test-app-review.ps1
```

---

## Antes de gravar — confirme no celular

1. Abra o WhatsApp do número **+55 34 9266-5547** (destinatário de teste).
2. Veja se chegou mensagem de teste do número **+1 555-651-6123**.
3. No painel Meta → Registro webhook → último evento deve ser `sent` ou `delivered`, **não** `failed`.

Se **chegou no celular** → pode gravar **Vídeo 1** seguindo [gravar-videos-app-review.md](./gravar-videos-app-review.md).

Se **não chegou** → aguarde billing liberar (health WABA AVAILABLE) ou revise https://business.facebook.com/billing_hub/accounts

---

## Gravação

| Vídeo | Login | Onde |
|-------|-------|------|
| 1 — mensagens | `admin@bellamassa.com.br` / `Bella@2026!` | Conversas → responder → mostrar celular |
| 2 — templates | idem | Backoffice → WhatsApp → Modelos WhatsApp (Meta) |
| Extra — disparo | idem | Menu **Templates WhatsApp** (após APPROVED) |

IDs da conta:

| Campo | Valor |
|-------|-------|
| WABA | `1651453995905846` |
| Phone Number ID | `1121301321069602` |
| Número teste Meta | `+1 555-651-6123` |

---

## Atenção: token no `whatsapp-gateway/.env`

O arquivo local pode ter **Phone Number ID / token de outro app**. O backoffice (MySQL) está sincronizado com `1121301321069602` e WABA `1651453995905846`. Para testes pelo painel, use sempre o token renovado na **API Setup** e salve no **Backoffice → WhatsApp**.

---

## Submissão App Review

Após gravar: [app-review-submission.md](./app-review-submission.md)
