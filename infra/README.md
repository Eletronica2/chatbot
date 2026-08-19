# Infraestrutura local

Stack Docker do chatbot SaaS:

- MySQL `3310`
- Backend API `8000`
- Flow Engine `8002`
- AI Engine `8003`
- WhatsApp Gateway `40000`

O admin panel Flutter Web **não** sobe no Compose.

## Portas

A porta **8000** precisa estar livre no host. O Compose publica `backend-api` em `0.0.0.0:8000`. Se outro processo já usar essa porta, o backend não inicia.

As demais portas padrão do projeto:

| Serviço | Host |
|---|---|
| backend-api | `8000` |
| flow-engine | `8002` |
| ai-engine | `8003` |
| whatsapp-gateway | `40000` |
| mysql | `3310` |

Não altere essas portas só por conflito local de outro projeto.

## Subir tudo (Docker + painel + túneis)

Na raiz do repositório:

```bash
./start-online.sh
```

O script sobe o Compose, o Flutter em `:4173`, abre túneis Cloudflare e imprime as URLs (webhook e painel). `Ctrl+C` encerra túneis e Flutter; o Docker continua. `SKIP_BUILD=1` pula o rebuild das imagens.

## Subir só o Docker

```bash
cd infra
docker compose up --build -d
```

Derrubar (mantém o volume do MySQL):

```bash
docker compose down --remove-orphans
```

Reset completo do banco local (apaga o volume `mysqldata`):

```bash
docker compose down -v
docker compose up --build -d
```

Healthchecks:

- http://localhost:8000/health
- http://localhost:8002/health
- http://localhost:8003/health
- http://localhost:40000/health

## Admin panel (Flutter Web)

```bash
cd admin-panel
flutter pub get
```

Com Chrome:

```bash
flutter run -d chrome
```

Sem Chrome (servidor web local):

```bash
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 4173
```

A API padrão do painel é `http://localhost:8000`.
