# Meta Tech Provider — App Review e Embedded Signup

Guia operacional para o app **Atenda Ai / Chatbot Ops** como **Independent Tech Provider** na Meta.

---

## URLs públicas (App Dashboard)

| Campo Meta | Valor |
|-----------|-------|
| Site / Landing | https://eletronica2.github.io/chatbot/ |
| Política de Privacidade | https://eletronica2.github.io/chatbot/privacy.html |
| Termos de Uso | https://eletronica2.github.io/chatbot/terms.html |
| Data Deletion (status) | https://eletronica2.github.io/chatbot/data-deletion.html |
| Data Deletion Callback (POST) | `https://<SEU_BACKEND_PUBLICO>/api/v1/meta/data-deletion` |
| Webhook WhatsApp | `https://<SEU_TUNNEL_OU_DOMINIO>/webhook` |

---

## Fase A — Configurações do app (Dashboard Meta)

1. **developers.facebook.com** → seu app → **Configurações do app**
2. Preencher:
   - Ícone 1024×1024 (logo Atenda Ai)
   - Categoria: **Business** ou **Productivity**
   - URL de Política de Privacidade (tabela acima)
3. **Facebook Login / Domínios do app** (quando Embedded Signup estiver ativo):
   - Domínio do admin panel em produção
   - `localhost` para desenvolvimento
4. **OAuth Redirect URIs**: URL do admin web (ex.: `https://seu-dominio.com/`)
5. **WhatsApp → Configuração**:
   - Callback URL: `https://<host>/webhook`
   - Verify token: mesmo valor de `META_VERIFY_TOKEN`
   - Assinar campos: `messages`, `history`, `smb_message_echoes`, `smb_app_state_sync`, `account_update`
6. **Data Deletion Callback URL**: endpoint POST do backend (tabela acima)
7. Variáveis no backend ([backend-api/.env.example](../backend-api/.env.example)):
   - `META_APP_ID`
   - `META_APP_SECRET`
   - `META_EMBEDDED_CONFIG_ID`
   - `META_VERIFY_TOKEN`

Tipo de integração: **Independent Tech Provider**.

---

## Fase B — Gravar vídeos (App Review)

Guia detalhado com roteiro minuto a minuto, checklist e smoke test: **[gravar-videos-app-review.md](./gravar-videos-app-review.md)**.

Resumo:

### Vídeo 1 — `whatsapp_business_messaging`

Mostrar envio de mensagem **do app** → recebimento no WhatsApp.

**Roteiro (~2 min):**

1. Abrir https://eletronica2.github.io/chatbot/
2. Login no admin → **Backoffice → WhatsApp**
3. Empresa **Pizzaria Bella Massa** com conta vinculada
4. Enviar mensagem do celular para o número de teste Meta
5. Mostrar log Docker: `POST /webhook` + resposta automática no WhatsApp
6. (Opcional) Abrir conversa no painel → responder manualmente

**Pré-requisitos:** Docker up, Cloudflare tunnel ativo, destinatário de teste verificado na Meta.

### Vídeo 2 — `whatsapp_business_management`

Mostrar **criação de modelo WhatsApp** no painel (não confundir com fluxos YAML).

**Roteiro (~2 min):**

1. Admin → Backoffice → WhatsApp → seção **Modelos WhatsApp (Meta)**
2. Criar modelo: `boas_vindas_atendimento`, categoria `UTILITY`, idioma `pt_BR`
3. Mostrar status `PENDING` na lista
4. (Opcional) Após aprovação Meta, enviar template

---

## Fase C — Submeter App Review

Texto sugerido (App Review notes):

> Atenda Ai is a B2B SaaS platform for WhatsApp customer service automation. Business admins connect their WhatsApp Business account via Embedded Signup (coexistence) or manual linking, configure automated flows, and reply to customers. We use whatsapp_business_messaging to send/receive customer messages and whatsapp_business_management to onboard business accounts and manage message templates on behalf of our customers.

Permissões:

- `whatsapp_business_messaging` — Advanced Access
- `whatsapp_business_management` — Advanced Access

Anexar os dois vídeos e URLs públicas (landing, privacy, terms). Checklist completo: [app-review-submission.md](./app-review-submission.md).

---

## Fase D — Embedded Signup + Coexistência (no produto)

### Backend

- `GET /api/v1/meta/embedded-signup/config` — retorna `app_id`, `config_id`
- `POST /api/v1/tenants/{tenant_id}/whatsapp-onboarding/exchange` — troca `code` por token e salva conta

### Admin panel (Flutter Web)

- Botão **Conectar via Meta (Coexistência)** no backoffice WhatsApp
- Usa Facebook JS SDK + `featureType: whatsapp_business_app_onboarding`

### Fluxo do cliente

1. Cliente usa WhatsApp Business App 2.24.17+ no celular
2. Clica **Conectar via Meta** no painel
3. Completa Embedded Signup na Meta (QR / código no app)
4. **Não** chamar `POST /register` manualmente — coexistência já registra o número

Doc Meta: [Onboard WhatsApp Business app users](https://developers.facebook.com/docs/whatsapp/embedded-signup/custom-flows/onboarding-business-app-users/)

### Cadastro hospedado pela Meta (alternativa temporária)

Enquanto aguarda aprovação, use o link **Cadastro incorporado hospedado pela Meta** no dashboard para testar com 1–2 clientes piloto.

---

## Fase E — Piloto BR (+55) pós-aprovação

Checklist:

- [ ] App Review aprovado (Advanced Access)
- [ ] `META_EMBEDDED_CONFIG_ID` configurado
- [ ] Cliente piloto com número BR no WhatsApp Business App
- [ ] Conectar via **Conectar via Meta (Coexistência)**
- [ ] Verificar Graph API: `GET /{PHONE_NUMBER_ID}?fields=is_on_biz_app,platform_type` → `true` + `CLOUD_API`
- [ ] Enviar mensagem do celular → webhook `POST /webhook`
- [ ] Resposta automática da Bella Massa / fluxo configurado

---

## Fase F — Upgrade Tech Partner (futuro)

Critérios Meta (não bloqueiam review inicial):

- ≥ 2.500 mensagens WhatsApp/dia (média 7 dias)
- ≥ 10 clientes ativos/mês
- Quality rating ≥ 90%

---

## Referências no código

| Recurso | Arquivo |
|---------|---------|
| Data deletion callback | `backend-api/app/api/routes/meta_callbacks.py` |
| Templates API | `backend-api/app/api/routes/whatsapp_templates.py` |
| Embedded Signup exchange | `backend-api/app/api/routes/whatsapp_onboarding.py` |
| UI templates + Meta connect | `admin-panel/lib/widgets/whatsapp_meta_panels.dart` |
| Coexistence webhooks | `whatsapp-gateway/webhook.py` |
| Webhook + assinatura | `META_APP_SECRET` no gateway |

---

## Troubleshooting

| Problema | Solução |
|----------|---------|
| `#2655122` número já no WhatsApp | Usar fluxo **Coexistência**, não registro manual |
| `#131030` destinatário não permitido | Adicionar número em destinatários de teste (Meta) |
| Webhook sem POST | Assinar campo `messages` no app Meta |
| Template rejeitado | Usar categoria `UTILITY`, texto claro, sem URLs encurtadas |
| Embedded Signup não abre | Rodar admin em **Flutter Web**; conferir `META_APP_ID` e `config_id` |
