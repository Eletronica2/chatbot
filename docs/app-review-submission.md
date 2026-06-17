# Meta App Review — submission checklist and copy-paste text

Use this after recording both videos. Full recording guide: [gravar-videos-app-review.md](./gravar-videos-app-review.md).

---

## URLs to paste in App Dashboard

| Field | URL |
|-------|-----|
| Site / Landing | https://eletronica2.github.io/chatbot/ |
| Privacy Policy | https://eletronica2.github.io/chatbot/privacy.html |
| Terms of Use | https://eletronica2.github.io/chatbot/terms.html |
| Data Deletion (status page) | https://eletronica2.github.io/chatbot/data-deletion.html |
| Data Deletion Callback (POST) | `https://<SEU_BACKEND_PUBLICO>/api/v1/meta/data-deletion` |
| Webhook (WhatsApp) | `https://<SEU_TUNNEL>.trycloudflare.com/webhook` |

Erro `#131031 Business Account locked`? Ver [meta-waba-locked-131031.md](./meta-waba-locked-131031.md) e `scripts/check-meta-health.ps1`.

Integration type: **Independent Tech Provider**.

---

## Permissions to request

| Permission | Access level | Video proof |
|------------|--------------|-------------|
| `whatsapp_business_messaging` | Advanced Access | Vídeo 1 — painel **Conversas** → enviar resposta → celular recebe |
| `whatsapp_business_management` | Advanced Access | Vídeo 2 — backoffice **WhatsApp** → criar template → status **PENDING** |

---

## App Review notes (English — paste in submission)

```
Atenda Ai is a B2B SaaS platform for WhatsApp customer service automation.

Business admins connect their WhatsApp Business account via Embedded Signup (coexistence) or manual linking, configure automated conversation flows, and reply to customers from the admin panel.

We use whatsapp_business_messaging to send and receive customer messages on behalf of our business customers.

We use whatsapp_business_management to onboard WhatsApp Business accounts and create/manage official message templates on behalf of our customers.

Demo login (reviewer may use if needed):
- Email: admin@bellamassa.com.br
- Password: Bella@2026!
- Tenant: Pizzaria Bella Massa (demo restaurant)

Public site: https://eletronica2.github.io/chatbot/
Privacy: https://eletronica2.github.io/chatbot/privacy.html
Terms: https://eletronica2.github.io/chatbot/terms.html
```

---

## Before you click Submit

- [ ] Vídeo 1 anexado (MP4, ~1–3 min, mostra envio pelo painel + recebimento no WhatsApp)
- [ ] Vídeo 2 anexado (MP4, ~1–3 min, mostra criação de template com status PENDING)
- [ ] Seu celular verificado como **test recipient** na Meta (API Setup → Para)
- [ ] Webhook HTTPS ativo (Cloudflare tunnel ou domínio fixo)
- [ ] Access Token da conta Bella Massa válido no backoffice (renovar se expirou)
- [ ] Ícone 1024×1024 e categoria **Business** preenchidos no app

---

## If Meta requests more detail

**How do you use messaging?**  
Customers message the business WhatsApp number. Our gateway receives webhooks, the backend runs configured flows, and agents can reply manually from the **Conversas** screen. Outbound messages go through the WhatsApp Cloud API.

**How do you use management?**  
Business admins open **Backoffice → WhatsApp → Modelos WhatsApp (Meta)** to create official templates (name, category, language, body). Templates are submitted to Meta for approval and appear with status PENDING.

**Data deletion:**  
Users can request deletion via the privacy page. Meta's signed_request hits `POST /api/v1/meta/data-deletion` on our backend.
