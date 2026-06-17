# Expor o webhook do WhatsApp Gateway com Cloudflare Tunnel (`cloudflared`)

O **WhatsApp Cloud API** exige uma URL **HTTPS** pública para o webhook. Este guia usa o cliente **Cloudflare Tunnel** (`cloudflared`), que já está instalado na sua máquina, para encaminhar o tráfego da internet até o **whatsapp-gateway** local.

## Pré-requisitos

1. **`cloudflared` instalado** e no PATH (Windows: pode instalar pelo instalador oficial ou Winget/Chocolatey — confira `cloudflared --version`).
2. **Gateway rodando** localmente na porta **`40000`** (padrão do `infra/docker-compose.yml`, serviço `whatsapp-gateway`).
3. Nos **Webhook fields** na Meta / no app, o mesmo **Verify Token** configurado como `META_VERIFY_TOKEN` no `.env` do gateway.

Endpoints do projeto:

- Verificação (GET): `https://<seu-host>/webhook`
- Mensagens (POST): `https://<seu-host>/webhook`

Na Meta Developers, informe **`https://<seu-host>/webhook`** como URL do webhook.

---

## Opção rápida: túnel temporário (`trycloudflare`)

Ideal para desenvolvimento. A URL muda a cada vez que você reinicia o comando (exceto quando usa config nomeada).

1. Suba o stack (Docker) ou apenas o gateway na porta 40000.
2. Num terminal:

```powershell
cloudflared tunnel --url http://localhost:40000
```

3. Copie o host HTTPS que aparece no log (ex.: `abc.xyz.trycloudflare.com`).
4. Na Meta, configure:

   - **Callback URL:** `https://abc.xyz.trycloudflare.com/webhook`
   - **Verify token:** o valor de `META_VERIFY_TOKEN` do gateway

5. Salve e use o botão de verificação da Meta. O GET de verificação deve bater no seu gateway.

**Nota:** URLs `*.trycloudflare.com` são públicas; use só para testes e tokens de teste. Não exponha segredos desnecessários.

---

## Opção estável: túnel com nome e domínio (Cloudflare Zero Trust)

Para URL fixa no seu domínio (produção ou homologação longa):

1. Autentique o cliente (fluxo oficial da Cloudflare, via dashboard Zero Trust ou `cloudflared tunnel login`).
2. Crie um tunnel nomeado no dashboard (**Networks → Tunnels**) ou pela CLI conforme a documentação atual da Cloudflare.
3. Associe um **hostname** (ex.: `wa-gateway.suaempresa.com`) ao serviço **HTTP local** `http://localhost:40000`.
4. Na Meta use: `https://wa-gateway.suaempresa.com/webhook`.

Detalhes e mudanças de UI variam ao longo do tempo; siga sempre a documentação oficial: [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/).

---

## Conferências rápidas

| Item | Valor típico neste projeto |
|------|-----------------------------|
| Porta local do gateway | `40000` |
| Caminho do webhook | `/webhook` |
| Variável de verify | `META_VERIFY_TOKEN` (gateway `.env`) |

---

## Ver também

- [Passo a passo: cadastro do WhatsApp do cliente](cadastro-whatsapp-cliente.md) — contexto Meta, tokens e onde colar a URL.
