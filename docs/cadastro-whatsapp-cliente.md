# Passo a passo: cadastro do WhatsApp do cliente para automação

Este guia descreve o fluxo típico para conectar o **WhatsApp oficial (WhatsApp Cloud API / Business Platform)** de um cliente ao sistema **Chatbot Ops**, incluindo onde obter dados no **Meta for Developers** e o que preencher no painel administrativo.

> **Importante:** a interface da Meta/Facebook muda com frequência. Use os links oficiais abaixo; os nomes de menus podem variar (“Configuração da API”, “Getting Started”, etc.), mas os **conceitos** (IDs, tokens, webhook) são os mesmos.

---

## O que você precisa antes de começar

1. Acesso ao **Gerenciador de Negócios da Meta** do cliente (`Meta Business`): [https://business.facebook.com/](https://business.facebook.com/).
2. Uma conta no **Facebook Developers** vinculada a esse negócio: [https://developers.facebook.com/](https://developers.facebook.com/).
3. Um **aplicativo (App)** com o produto **WhatsApp** ativado: [https://developers.facebook.com/apps/](https://developers.facebook.com/apps/).
4. Um número de telefone habilitado na **WhatsApp Business Platform** (API em nuvem) — número de produção ou, em testes, o número de teste da Meta.
5. Uma URL **HTTPS** pública onde o **WhatsApp Gateway** do projeto esteja exposto — o webhook da Meta chama esse endereço. Em desenvolvimento local costuma-se usar um túnel (**[Cloudflare Tunnel](webhook-cloudflare-tunnel.md)**, ngrok, etc.); em produção, o domínio real do gateway.

Consulta oficial sobre a API em nuvem: [Introdução — WhatsApp Cloud API](https://developers.facebook.com/docs/whatsapp/cloud-api/overview/).

---

## Visão rápida: URLs úteis da Meta

| Finalidade | URL |
|-----------|-----|
| Portal de desenvolvedores | [developers.facebook.com](https://developers.facebook.com/) |
| Lista dos seus aplicativos | [developers.facebook.com/apps](https://developers.facebook.com/apps/) |
| Documentação WhatsApp Cloud API | [developers.facebook.com/docs/whatsapp/cloud-api](https://developers.facebook.com/docs/whatsapp/cloud-api) |
| Configurar webhook (guia Meta) | [Set up Webhooks — Cloud API](https://developers.facebook.com/docs/whatsapp/cloud-api/guides/set-up-webhooks) |
| Webhooks (visão geral Graph API) | [Webhooks Meta / Graph API](https://developers.facebook.com/docs/graph-api/webhooks) |
| Negócio do cliente | [business.facebook.com](https://business.facebook.com/) |
| Painel WhatsApp dentro do seu app Dev | Tipicamente: `developers.facebook.com` → **Meus aplicativos** → selecionar o app → menu lateral **WhatsApp** |

---

## Webhook e tokens: onde clicar na Meta + links

### Onde configuro o **webhook**?

Os webhooks da Cloud API ficam configurados **no próprio aplicativo** no Meta for Developers, na área do produto **WhatsApp**, não na Business Suite.

**Caminho na tela (nomes podem vir em inglês)**

1. Entre na lista de aplicativos: **[developers.facebook.com/apps](https://developers.facebook.com/apps/)**
2. **Abrir o aplicativo** usado pelo WhatsApp do cliente.
3. No menu **esquerdo**, clique em **WhatsApp**.
4. Abra **Configuration** (**Configuração**) — procure a sub-seção ou bloco chamado algo como **Webhook**.
5. Preencha **Callback URL**, **Verify token** e inscreva os campos (ex.: **`messages`**), depois **Verify and save / Verificar e salvar**.

Se não achar esse menu à primeira vista, dentro de **WhatsApp** vale abrir também **Getting started / Começar** — há atalhos e instruções que levam à mesma configuração.

**Documentação oficial (passo a passo da Meta)**

- [WhatsApp Cloud API — Configurar webhooks (*Set up Webhooks*)](https://developers.facebook.com/docs/whatsapp/cloud-api/guides/set-up-webhooks) — uso de callback URL, verify token e assinatura de campos.

**URL de callback esperada pelo Chatbot Ops (seu servidor)**  

Coloque sua URL HTTPS pública terminando em **`/webhook`** (serviço `whatsapp-gateway`):

```
https://<SEU_DOMINIO_PUBLICO>/webhook
```

O **Verify token** deve ser **exatamente o mesmo** que você guardar no formulário da conta WhatsApp no backoffice (**Token de verificação**): não é algo que você “baixa” da Meta; é uma sequência forte que você **define** e repete nos dois lugares.

---

### Onde encontro o **token**? (dois tokens diferentes)

| Token no Chatbot Ops | O que é | Onde aparece ou como obter |
|----------------------|---------|----------------------------|
| **Token de verificação** (`Verify Token` no webhook Meta) | Frase secreta só sua, para o Meta conseguir validar seu servidor. | **Você cria.** Cole o mesmo valor no Meta (Webhook) e no cadastro da conta WhatsApp no painel. Descrito nos passos da doc acima dos webhooks: [Set up Webhooks](https://developers.facebook.com/docs/whatsapp/cloud-api/guides/set-up-webhooks). |
| **Token de acesso** (`Access token` — envio de mensagens e API) | Credencial temporal ou de longo prazo com permissões do app. | **No painel do app**, em **WhatsApp** → área tipo **Getting started / API Setup / Configuração da API**, costuma aparecer um campo **Temporary access token** para testes. Para produção, use fluxo oficial de tokens de longa duração (business). |

**Links oficiais da Meta sobre tokens**

1. **[Cloud API — Get started](https://developers.facebook.com/docs/whatsapp/cloud-api/get-started)** — primeiro contato com o app WhatsApp e token de uso em desenvolvimento (quando disponível nesta página).
2. **[Access Tokens — WhatsApp Business Platform](https://developers.facebook.com/docs/whatsapp/access-tokens)** — tokens permanentes / System User / escopo e boas práticas.

**Resumo rápido**

- Para **Webhook + Verify token**: página [Set up Webhooks](https://developers.facebook.com/docs/whatsapp/cloud-api/guides/set-up-webhooks).
- Para **Phone number ID e token de uso da API**: [Get started](https://developers.facebook.com/docs/whatsapp/cloud-api/get-started) na prática combinado com **[Access Tokens](https://developers.facebook.com/docs/whatsapp/access-tokens)** em produção.

---

## Parte A — Meta (Facebook Developer): obter IDs e tokens


### 1. Entrar ou criar o aplicativo

1. Abra **[developers.facebook.com/apps](https://developers.facebook.com/apps/)**.
2. **Criar app** ou escolha um já usado para o WhatsApp Business.
3. No app, adicione o produto **WhatsApp** (**Adicionar produto** → **WhatsApp**), se ainda não estiver ativo.

### 2. Onde ficam Phone number ID, token e webhook no painel Meta

Fluxo habitual (os rótulos podem mudar de idioma/versão):

1. Continuando no mesmo app → menu **WhatsApp** (à esquerda).
2. Abra **`Getting Started` / Começar** ou **Configuração da API** (`API Setup`).

Ali costumam aparecer:

- Lista de números e o **Phone number ID** ao selecionar o número — é o número longo (`Phone number ID`) que você deve copiar.
- Área para gerar ou ver **temporary access token** (ambiente de teste).
- Link para configurar **Webhook** (Webhook fields, callback URL, verify token).

Outra porta de entrada útil: dentro de **WhatsApp** → **Configuração** → **Webhook** (callback URL / campos de mensagem).

| No painel do Chatbot Ops | Onde obter ou definir na Meta |
|--------------------------|------------------------------|
| **ID do número no WhatsApp** | **Phone number ID** na área WhatsApp → API Setup / número selecionado. |
| **Número exibido** | O número público configurado para essa conta (formato tipo `+55 11 …`). Serve para você e o cliente reconhecerem a linha. |
| **Token de acesso** | Campo **Access token** nos passos GET STARTED/API ou um token de **longa duração** gerado conforme [Access tokens — WhatsApp](https://developers.facebook.com/docs/whatsapp/access-tokens). Em produção use fluxo próprio para token permanente (**System Users** na Business). |
| **Token de verificação** | **Não existe na Meta** — você **cria uma string forte** e cola **a mesma string** tanto no formulário Meta (Webhook → Verify Token) quanto no diálogo do sistema (vide Parte B). |

**WhatsApp Business Account ID (WABA)** aparece nas mesmas telas da API; ajuda em suporte, mas o formulário atual do sistema foca em **Phone number ID** + tokens.

### 3. Lembrete rápido sobre webhook (detalhes já estão na seção acima)

O preenchimento na Meta segue: **WhatsApp** → **Configuration** → **Webhook** (callback + verify token + campo `messages`). Guia passo a passo e links: **[Set up Webhooks](https://developers.facebook.com/docs/whatsapp/cloud-api/guides/set-up-webhooks)**. No seu projeto, a URL de callback termina em **`/webhook`** (gateway).

### 4. Produção vs testes

- **Sandbox / número de teste Meta:** rápido para validar webhook e envio só para números permitidos pela Meta.
- **Produção:** número do cliente vinculado ao WABA, políticas Meta cumpridas, token de longo prazo com escopos corretos (veja novamente [Access tokens](https://developers.facebook.com/docs/whatsapp/access-tokens)).

---

## Parte B — Cadastro no painel Chatbot Ops (WhatsApp por empresa)

### Onde clicar

1. Login como perfil administrador com acesso ao **backoffice**.
2. Separador/visual **WhatsApp** — selecione a **empresa (tenant)** do cliente.
3. **Vincular WhatsApp** / **Nova conta WhatsApp** (fluxo igual ao formulário dentro do tenant no detalhe da empresa).

### Campos do diálogo (como aparece no código atual)

| Campo | Regra | O que é |
|-------|-------|---------|
| **Identificador da conta** | Obrigatório na criação; não editável depois no fluxo atual | Slug interno (ex.: `loja_centro_linha_principal`). Sem equivalente direto Meta. |
| **Nome amigável** | Obrigatório | Etiqueta no painel. |
| **ID do número no WhatsApp** | Obrigatório | **Phone number ID** da Meta. |
| **Número exibido** | Obrigatório | Para exibir no sistema e coincidir com o número configurado para esse Phone number ID na Meta. |
| **Token de verificação** | Recomendado | Mesmo valor do webhook Meta (**Verify Token**). |
| **Token de acesso** | Obrigatório na criação; na edição vazio preserva token salvo | **Access token** válido Cloud API dessa conta. |
| **Conta principal** | Opcional estratégico | Define default se houver vários números no tenant. |

---

## Parte C — Checklist rápido

- [ ] Webhook com `https://…/webhook` e Verify Token igual ao cadastro.
- [ ] Phone number ID e Access Token válidos na conta criada para o tenant certo.
- [ ] Fluxos/automação publicados, se já for responder em nome do cliente em produção.
- [ ] Teste real: mensagem sua → aparece sessão/atividade na plataforma.

---

## Problemas comuns

| Sintoma | O que checar |
|--------|----------------|
| Falha ao salvar webhook | HTTPS acessível; caminho **`/webhook`**; firewall; token idêntico. |
| Nada chega no sistema | Gateway público resolvendo até o servidor; conta salva para o Phone number ID que aparece nos eventos Meta. |
| Não envia resposta | Token de acesso válido (tokens expiram); permissões WhatsApp Messaging no app. |

---

## Referências no repositório (dev)

- API de contas: `GET`/`POST` em `/api/v1/tenants/{tenant_id}/whatsapp-accounts`.
- Gateway: `whatsapp-gateway/webhook.py` — rotas `GET /webhook` e `POST /webhook`.
- Variáveis de fallback: `whatsapp-gateway/.env.example`.

Este texto pode ser compartilhado com cliente final removendo detalhes de `tenant` e paths internos, se preferir.

