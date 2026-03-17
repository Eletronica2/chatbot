# Treinamento Local + Fallback Gemini

Este documento define o processo recomendado para responder primeiro com fluxos locais (`.yaml`) e somente usar IA generativa quando nao houver resposta programada.

## 1. Estrategia Recomendada

1. Fluxo local primeiro: respostas previsiveis, consistentes e baratas.
2. Gemini como fallback: perguntas abertas, fora do fluxo, duvidas nao mapeadas.
3. Revisao continua: novas perguntas recorrentes devem voltar para o YAML.

## 2. Como o sistema decide (resumo)

1. Mensagem entra no WhatsApp Gateway.
2. Backend chama o Flow Engine (`start.yaml`, `faq.yaml`, etc.).
3. Se o fluxo resolver: responde com a mensagem do estado.
4. Se nao resolver: Backend chama o AI Engine.
5. Com `MOCK_AI=false` e `AI_PROVIDER=gemini`, o AI Engine usa Gemini.

## 3. Configuracao Gemini no AI Engine

Arquivo: `ai-engine/.env`

```env
MOCK_AI=false
AI_PROVIDER=gemini
GEMINI_API_KEY=COLE_SUA_CHAVE_AQUI
GEMINI_MODEL=gemini-1.5-flash
```

Opcional OpenAI (nao necessario para Gemini):

```env
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4o-mini
```

Depois de alterar:

```bash
cd infra
docker compose up -d --build ai-engine backend-api flow-engine whatsapp-gateway
```

## 4. Como "treinar" localmente com YAML

Nao existe treino de modelo aqui; o treino local e organizar regras e respostas no Flow Engine.

### 4.1 Estrutura minima de fluxo

```yaml
name: start
start_state: greeting
states:
  greeting:
    message: "Oi! Posso ajudar com pedidos, pagamento ou entrega."
    options:
      - label: "Entrega"
        value: "entrega"
      - label: "Pagamento"
        value: "pagamento"
    transitions:
      - condition: "contains:entrega"
        target: shipping
      - condition: "contains:pagamento"
        target: payment

  shipping:
    message: "Entregamos em ate 5 dias uteis."

  payment:
    message: "Aceitamos Pix, cartao e boleto."
```

### 4.2 Boas praticas

1. Um estado por intencao principal.
2. Mensagens curtas e objetivas.
3. Usar `options` para guiar o usuario.
4. Criar transicoes por termos reais que clientes usam.
5. Evitar regras ambigas que colidem.

### 4.3 Ciclo semanal de melhoria

1. Exportar conversas nao resolvidas.
2. Identificar top 20 perguntas recorrentes.
3. Criar/ajustar estados e transicoes no YAML.
4. Publicar e validar com equipe.
5. Repetir.

## 5. Processo operacional sugerido

1. Nova pergunta apareceu varias vezes.
2. Time adiciona estado no YAML via Admin Panel (Settings -> Editor de fluxos YAML).
3. Salva e recarrega fluxo.
4. Testa no WhatsApp.
5. Se ainda houver lacunas, Gemini cobre fallback.

## 6. Quando usar Gemini

Use Gemini para:

1. Perguntas abertas sem padrao fixo.
2. Reformulacoes complexas do usuario.
3. Contexto conversacional fora das regras.

Nao use Gemini para:

1. Politicas oficiais (preco, prazo, regras legais) sem validacao.
2. Respostas criticas que exigem texto fixo.

## 7. Checklist de publicacao

1. `MOCK_AI=false`
2. `AI_PROVIDER=gemini`
3. `GEMINI_API_KEY` configurada
4. Fluxos principais revisados (`start.yaml`, `faq.yaml`, `atendimento.yaml`)
5. Testes manuais de 10 perguntas comuns
6. Monitoramento de falhas e perguntas novas

## 8. Observacoes importantes

- Free tier do Gemini possui limites de uso.
- Se bater limite/quota, o AI Engine retorna indisponibilidade e o fluxo local continua sendo a base.
- Mantendo o YAML atualizado, o custo e dependencia de IA caem bastante.
