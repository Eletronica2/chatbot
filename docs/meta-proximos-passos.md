# Meta — o que fazer agora (Access Verification + App Review)

App: **Atenda Ai** (`873826165763092`)  
Empresa: **34.144.027 ARTHUR GABRIEL MARTINS LARANJO** · CNPJ **34.144.027/0001-70**  
Tipo: **Independent Tech Provider**

Ignore o aviso cosmético `fb:app_id` no depurador. Não bloqueia nada.

---

## Ordem (não pule etapas)

```
1. Access Verification (formulário Tech Provider)
2. Gravar 2 vídeos (se ainda não tiver)
3. Reenviar App Review (só messaging + management)
4. Após Advanced Access aprovado → coexistência BR de novo
```

`manage_app_solution` **não** entra nesta rodada — só depois do Access Verification aprovado.

---

## Passo 1 — Access Verification

1. Abra: [App Dashboard → Verifications](https://developers.facebook.com/apps/873826165763092/settings/basic/)  
   (procure **Access verification** / **Verificação de acesso**, ou use o link do e-mail da Meta aos admins do Business)
2. Confirme que **Business Verification** já está concluída (Central de Segurança)
3. Preencha o formulário com os textos abaixo
4. Envie e aguarde (~5 dias úteis)

### Textos para colar (inglês — Meta costuma pedir em inglês)

**Primary category / How will your app use business assets?**

```
We are an Independent Tech Provider (SaaS). Atenda Ai lets restaurants and local businesses connect their own WhatsApp Business accounts to our platform so they can automate customer service and reply from our admin panel.
```

**What is your business use case?**

```
Atenda Ai is a B2B WhatsApp customer-service automation platform operated by 34.144.027 ARTHUR GABRIEL MARTINS LARANJO (CNPJ 34.144.027/0001-70, Uberaba-MG, Brazil).

Our customers (other businesses) connect their WhatsApp Business Account (WABA) via Embedded Signup / coexistence. We process messages, templates, and account metadata on their behalf so they can run automated flows and human agent replies inside our product.

We only access another business's WhatsApp assets after that business explicitly authorizes our app during onboarding.
```

**How do you obtain consent / onboard customers?**

```
Business owners sign up on Atenda Ai, then complete Meta Embedded Signup (including coexistence when applicable) from our admin panel. They grant WhatsApp permissions to our Meta app (ID 873826165763092) for their own WABA and phone number. We store tokens and IDs only for that tenant and use them to send/receive messages and manage templates.
```

**Privacy / company identity**

```
Privacy Policy: https://eletronica2.github.io/chatbot/privacy.html
Terms: https://eletronica2.github.io/chatbot/terms.html
Legal entity: 34.144.027 ARTHUR GABRIEL MARTINS LARANJO — CNPJ 34.144.027/0001-70
Contact: atendaai@gmail.com
```

Doc oficial: [Access Verification](https://developers.facebook.com/documentation/development/release/access-verification)

---

## Passo 2 — Confirmar URLs no App Dashboard

| Campo | Valor |
|-------|--------|
| Site | https://eletronica2.github.io/chatbot/ |
| Privacy | https://eletronica2.github.io/chatbot/privacy.html |
| Terms | https://eletronica2.github.io/chatbot/terms.html |
| Domínio do app | `eletronica2.github.io` |
| Categoria | Business |
| Ícone | 1024×1024 |

---

## Passo 3 — Gravar os 2 vídeos

Roteiro: [gravar-videos-app-review.md](./gravar-videos-app-review.md)

| Vídeo | Permissão | O que mostrar |
|-------|-----------|----------------|
| 1 | `whatsapp_business_messaging` | Painel **Conversas** → enviar resposta → celular recebe |
| 2 | `whatsapp_business_management` | **WhatsApp → Modelos** → criar template → status **PENDING** |

Checklist técnico antes de gravar:

- Docker + túnel Cloudflare (ou domínio fixo) ativos  
- Seu número como **destinatário de teste** na API Setup da Meta  
- Login demo: `admin@bellamassa.com.br` / `Bella@2026!`  
- Token WhatsApp da Bella Massa válido no painel  

Smoke test: `scripts/smoke-test-app-review.ps1`

---

## Passo 4 — Reenviar App Review

Abrir: [App Review → Permissions](https://developers.facebook.com/apps/873826165763092/app-review/permissions/)

**Pedir Advanced Access só para:**

- `whatsapp_business_messaging`
- `whatsapp_business_management`
- `public_profile` (se a Meta listar)

**Não pedir agora:**

- `manage_app_solution` (espera Access Verification)
- `whatsapp_business_manage_events` (Conversions API — não usamos)

### Notas da submissão (colar)

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

Antes de Submit:

- [ ] Vídeo 1 anexado  
- [ ] Vídeo 2 anexado  
- [ ] Privacy URL atualizada (com CNPJ / razão social)  
- [ ] `manage_app_solution` **fora** desta submissão  

---

## Passo 5 — Depois da aprovação

1. Confirme **Advanced Access: Approved** nas duas permissões WhatsApp  
2. Publique o app (se ainda estiver em Development para produção)  
3. Repita coexistência com o número BR (+55 34 3195-1773)  
4. Só então avance `manage_app_solution`, se a Meta ainda exigir  

---

## Links rápidos

| O quê | Link |
|-------|------|
| App | https://developers.facebook.com/apps/873826165763092/ |
| Permissions / App Review | https://developers.facebook.com/apps/873826165763092/app-review/permissions/ |
| Access Verification doc | https://developers.facebook.com/documentation/development/release/access-verification |
| Depurador privacy | https://developers.facebook.com/tools/debug/?q=https://eletronica2.github.io/chatbot/privacy.html |
| Business Manager | https://business.facebook.com/ |
