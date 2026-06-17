# Checklist: app Meta novo do zero (Atenda Ai)

Use este guia na ordem. Marque cada item ao concluir.  
Tempo estimado: **1–2 dias** para gravar os vídeos; **1–3 semanas** para App Review aprovado (após submissão).

**Login recomendado:** `labeltink02@gmail.com` (perfil que vê “Criar aplicativo” no Developers).

---

## Links rápidos (abrir em abas)

| O quê | Link |
|-------|------|
| Lista de apps | https://developers.facebook.com/apps/ |
| Business Manager | https://business.facebook.com/home/ |
| Configurações do negócio | https://business.facebook.com/settings |
| Central de Segurança (verificação) | https://business.facebook.com/settings/security |
| Cobrança — contas WhatsApp | https://business.facebook.com/billing_hub/accounts |
| WhatsApp Manager | https://business.facebook.com/wa/manage/home/ |
| Account Quality | https://business.facebook.com/accountquality |
| Suporte Developers | https://developers.facebook.com/support/ |
| Landing pública | https://eletronica2.github.io/chatbot/ |
| Privacidade | https://eletronica2.github.io/chatbot/privacy.html |
| Termos | https://eletronica2.github.io/chatbot/terms.html |
| Data Deletion (página) | https://eletronica2.github.io/chatbot/data-deletion.html |

---

## Fase 0 — Antes de começar (15 min)

- [ ] Entrar no Facebook com **labeltink02@gmail.com**: https://www.facebook.com  
- [ ] Entrar no Developers: https://developers.facebook.com/apps/  
- [ ] Confirmar que aparece **Criar aplicativo** (não “nenhum app” sem botão)  
- [ ] Docker Desktop **aberto** (ícone verde na bandeja)  
- [ ] Anotar seu número de teste (só dígitos): ex. `5534992665547` para `+55 34 99266-5547`

---

## Fase 1 — Criar o app (30–45 min)

### 1.1 Criar aplicativo

- [ ] Abrir: https://developers.facebook.com/apps/  
- [ ] Clicar **Criar aplicativo**  
- [ ] Tipo: **Outro** → **Business** (ou fluxo que ofereça WhatsApp)  
- [ ] Nome do app: **Atenda Ai** (ou **Atenda Ai 2** se o nome antigo conflitar)  
- [ ] E-mail de contato: **labeltink02@gmail.com**  
- [ ] Vincular ao portfólio **Atende Ai** se a Meta pedir  

**Anote aqui o novo App ID:** `___________________________`

### 1.2 Adicionar produto WhatsApp

- [ ] No app novo → menu **Adicionar produto** → **WhatsApp** → **Configurar**  
- [ ] Ou: https://developers.facebook.com/apps/`SEU_APP_ID`/whatsapp-business/wa-dev-console/  
  (troque `SEU_APP_ID` pelo ID anotado)

### 1.3 Tipo de provedor

- [ ] Em configurações do app / WhatsApp, escolher **Independent Tech Provider** (não Solution Partner)  
- [ ] Doc interna: [meta-tech-provider-app-review.md](./meta-tech-provider-app-review.md)

### 1.4 URLs do app (Configurações básicas)

- [ ] Abrir: https://developers.facebook.com/apps/`SEU_APP_ID`/settings/basic/  
- [ ] **URL de política de privacidade:** https://eletronica2.github.io/chatbot/privacy.html  
- [ ] **URL dos termos** (se pedido): https://eletronica2.github.io/chatbot/terms.html  
- [ ] **Categoria:** Business ou Productivity  
- [ ] Salvar alterações  

---

## Fase 2 — WhatsApp API Setup (45 min)

Abra (substitua o ID):

**https://developers.facebook.com/apps/`SEU_APP_ID`/whatsapp-business/wa-dev-console/**

### 2.1 Conta e número de teste

- [ ] Anotar **WhatsApp Business Account ID (WABA):** `___________________________`  
- [ ] Anotar **Phone number ID:** `___________________________`  
- [ ] Anotar **número exibido** (ex. +1 555…): `___________________________`  
- [ ] Clicar **Generate** em **Temporary access token** e copiar o token  

### 2.2 Destinatário de teste (seu celular)

- [ ] Na mesma página, seção **Para** / **To** / **Recipient phone number**  
- [ ] Adicionar número: `+55 34 992665547` (ou o seu)  
- [ ] Confirmar código de 6 dígitos no WhatsApp  
- [ ] Status: **Verified**  

### 2.3 Teste rápido no painel Meta

- [ ] Enviar mensagem de teste do painel para seu celular  
- [ ] Abrir **Registro de webhook** no app → último status deve ser **sent** ou **delivered**, não **failed**  
- [ ] Se **failed** + `131031` → ver Fase 3 (billing + verificação WABA)  
- [ ] Se **failed** + `131030` → destinatário não verificado (refazer 2.2)  

---

## Fase 3 — Pagamento na WABA certa (20 min)

**Erro comum:** cartão só na “Atenda Ai”, WABA de teste sem pagamento.

- [ ] Abrir: https://business.facebook.com/billing_hub/accounts  
- [ ] Aba **Contas do WhatsApp Business**  
- [ ] Localizar a WABA **nova** (ID anotado na Fase 2)  
- [ ] Se aparecer **Nenhuma forma de pagamento** → **Adicionar forma de pagamento**  
- [ ] **Não** colocar cartão só na outra linha se for WABA diferente  

### 3.1 Verificação WABA (se “Conta com restrição”)

- [ ] Abrir: https://business.facebook.com/wa/manage/home/  
- [ ] Se aparecer **Conta com restrição** → **Iniciar verificação** ou **Gerenciador do WhatsApp**  
- [ ] Central de Segurança (já verificada ajuda): https://business.facebook.com/settings/security  
- [ ] Aguardar restrição sumir antes de gravar Vídeo 1  

### 3.2 Health check (terminal)

```powershell
$env:META_ACCESS_TOKEN = "<token da Fase 2>"
powershell -ExecutionPolicy Bypass -File scripts/check-meta-health.ps1
```

- [ ] WABA com `can_send_message: AVAILABLE` (script sai com sucesso)  

---

## Fase 4 — Webhook (30 min)

### 4.1 Subir stack local

```powershell
cd c:\Users\eletr\Desktop\chatbot\infra
docker compose up -d
```

- [ ] Containers healthy: `docker ps`  

### 4.2 Túnel Cloudflare (terminal separado)

```powershell
cloudflared tunnel --url http://localhost:40000
```

- [ ] Copiar URL HTTPS (ex. `https://xxxx.trycloudflare.com`)  
- [ ] Webhook completo: `https://xxxx.trycloudflare.com/webhook`  

### 4.3 Configurar webhook na Meta

- [ ] Abrir: https://developers.facebook.com/apps/`SEU_APP_ID`/whatsapp-business/wa-dev-console/  
- [ ] Ou: **WhatsApp** → **Configuração** → **Webhook**  
- [ ] **Callback URL:** `https://xxxx.trycloudflare.com/webhook`  
- [ ] **Verify token:** `super-secret-webhook-token` (mesmo do projeto)  
- [ ] Assinar campo **messages** (e opcional: `account_update` se usar coexistência)  
- [ ] **Verificar e salvar**  

### 4.4 Testar verify local

```powershell
curl.exe "http://localhost:40000/webhook?hub.mode=subscribe&hub.verify_token=super-secret-webhook-token&hub.challenge=teste"
```

- [ ] Resposta: `teste`  

---

## Fase 5 — Atualizar Atenda Ai (backoffice + env) (30 min)

### 5.1 Backoffice (painel Flutter)

- [ ] Subir admin: `cd admin-panel` → `flutter run -d chrome`  
- [ ] Login: **admin@bellamassa.com.br** / **Bella@2026!**  
- [ ] **Backoffice** → aba **WhatsApp**  
- [ ] Atualizar conta Bella Massa:
  - **account_key (WABA ID):** valor da Fase 2  
  - **Phone Number ID:** valor da Fase 2  
  - **Número exibido:** valor da Fase 2  
  - **Access Token:** token novo da Fase 2  
  - **Verify token:** `super-secret-webhook-token`  
- [ ] Salvar  

### 5.2 Backend (opcional, se rodar API local com .env)

Arquivo: `backend-api/.env` (não commitar segredos)

```env
META_APP_ID=<SEU_APP_ID>
META_APP_SECRET=<App Secret em Configurações básicas>
META_VERIFY_TOKEN=super-secret-webhook-token
```

- [ ] App Secret: https://developers.facebook.com/apps/`SEU_APP_ID`/settings/basic/ → **Chave secreta do aplicativo** → **Mostrar**  

### 5.3 Smoke test

```powershell
powershell -ExecutionPolicy Bypass -File scripts/smoke-test-app-review.ps1
```

- [ ] Todos **[OK]**  

### 5.4 Fluxo completo

- [ ] No celular, enviar **"Oi"** para o **número de teste Meta** (Fase 2)  
- [ ] Painel → **Conversas** → abrir seu número → **Enviar** resposta  
- [ ] Mensagem **chega no celular**  

---

## Fase 6 — Gravar os 2 vídeos (1–2 h)

Roteiro detalhado: [gravar-videos-app-review.md](./gravar-videos-app-review.md)

| Vídeo | O que mostrar |
|-------|----------------|
| **1 — messaging** | Login → Conversas → enviar → **celular recebe** |
| **2 — management** | Backoffice → WhatsApp → criar template `boas_vindas_atendimento` → **PENDING** |

- [ ] Vídeo 1 gravado (MP4, ~1–3 min)  
- [ ] Vídeo 2 gravado (MP4, ~1–3 min)  

---

## Fase 7 — Submeter App Review (30 min)

Checklist e textos: [app-review-submission.md](./app-review-submission.md)

### 7.1 Permissões

- [ ] App Review → solicitar **whatsapp_business_messaging** (Advanced Access)  
- [ ] App Review → solicitar **whatsapp_business_management** (Advanced Access)  
- [ ] Anexar Vídeo 1 e Vídeo 2  

### 7.2 URLs no app

| Campo | URL |
|-------|-----|
| Site | https://eletronica2.github.io/chatbot/ |
| Privacidade | https://eletronica2.github.io/chatbot/privacy.html |
| Termos | https://eletronica2.github.io/chatbot/terms.html |
| Data Deletion | https://eletronica2.github.io/chatbot/data-deletion.html |

### 7.3 URLs no painel Meta (não truncar)

| Campo no Developers | Cole exatamente |
|---------------------|-----------------|
| **Webhook** (WhatsApp → Configuration) | `https://<tunnel>.trycloudflare.com/webhook` |
| **Verify token** | `super-secret-webhook-token` |
| **Data Deletion** (página / instruções) | https://eletronica2.github.io/chatbot/data-deletion.html |
| **Data Deletion Callback** (POST) | `https://<tunnel>.trycloudflare.com/api/v1/meta/data-deletion` |

Erro `name_placeholder should represent a valid URL` costuma ser URL **cortada** (`.../data-dele`) ou túnel só na porta do gateway **antes** do proxy `/api/v1/meta/*`. Teste no navegador: o callback deve retornar JSON `{"status":"ok",...}`.

### 7.4 Data Deletion Callback

- [ ] `https://<tunnel>.trycloudflare.com/api/v1/meta/data-deletion` (túnel na porta **40000** do gateway)  
- [ ] Em produção use domínio fixo apontando para o mesmo path  

- [ ] Submissão enviada → aguardar **3–14 dias úteis** (às vezes mais)  

---

## Problemas comuns

| Sintoma | Link / ação |
|---------|-------------|
| `#131030` | Refazer destinatário de teste (Fase 2.2) |
| `#131031` | [meta-waba-locked-131031.md](./meta-waba-locked-131031.md) + billing na WABA certa + verificação WABA |
| App não lista no Developers | Usar conta **labeltink02**; app novo aparece na **sua** lista |
| Webhook sem POST | Túnel ativo + campo **messages** assinado |
| Template não cria | Token novo + permissão `whatsapp_business_management` na submissão |
| `name_placeholder should represent a valid URL` | URL completa (não `.../data-dele`); callback deve abrir JSON `status: ok` no navegador |
| `#141006` pagamento | Cartão na WABA **27281965408107469** (Billing Hub) |

---

## Planilha de IDs (preencher)

| Campo | Valor |
|-------|-------|
| App ID | `873826165763092` |
| App Secret | (Settings → Basic → Show) |
| WABA ID (teste EUA) | `27281965408107469` / Phone `1201264079728608` / `+1 555-656-7513` |
| WABA ID (produção BR — Bella Massa) | `1299741078262298` |
| Phone Number ID (BR) | `1155710810954749` |
| Número BR | `+55 34 3195-3594` |
| Business ID | `2330602324386620` |
| Tunnel webhook URL | `https://remaining-variations-manga-responsibility.trycloudflare.com/webhook` |
| Data deletion callback | `https://remaining-variations-manga-responsibility.trycloudflare.com/api/v1/meta/data-deletion` |
| Tenant Bella Massa | `pizzaria_bella_massa` (conta API configurada) |

---

## Ordem em uma linha

```
Criar app → WhatsApp → token + destinatário → pagamento na WABA nova
→ webhook + Docker → backoffice → teste celular → gravar vídeos → App Review
```
