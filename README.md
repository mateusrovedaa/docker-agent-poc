# Docker Agent — PoC e Aprendizados

Repositório de exploração do [Docker Agent](https://docs.docker.com/ai/docker-agent/), framework open-source da Docker para orquestrar times de agentes IA especializados.

## O que é o Docker Agent

Docker Agent é um framework que permite criar equipes de agentes IA onde cada agente tem:

- **Modelo próprio** — você escolhe o LLM por agente (OpenAI, Anthropic, Google, modelos locais)
- **Contexto isolado** — agentes não compartilham histórico de conversa entre si
- **Ferramentas específicas** — filesystem, shell, servidores MCP por agente
- **Delegação hierárquica** — um agente raiz distribui tarefas para sub-agentes

A configuração é feita via YAML e os agentes são empacotados como artefatos OCI, podendo ser distribuídos via Docker Hub como imagens de container.

## Por que isso é interessante

| Problema comum | Como o Docker Agent resolve |
|---|---|
| Um único LLM para tudo fica caro | Modelos diferentes por agente — use o pesado só onde importa |
| Contexto do LLM fica enorme com tarefas complexas | Contextos isolados — cada agente vê só o que precisa |
| Difícil reusar pipelines em outros projetos | Empacota como OCI — `docker agent share push/pull` |
| Setup de agentes exige muito código | YAML declarativo — sem framework Python pesado |

## Casos de uso

O Docker Agent brilha em cenários onde uma única chamada de LLM não é suficiente — seja por complexidade, custo, ou necessidade de especialização.

### Pipelines de processamento de conteúdo

**Filtragem e extração de artigos** (esta PoC)
- Agente 1 filtra relevância com modelo leve
- Agente 2 extrai dados estruturados só dos artigos aprovados
- Economiza tokens: artigos irrelevantes nunca chegam ao extrator

**Moderação de conteúdo em camadas**
- Agente rápido faz triagem inicial (spam, conteúdo óbvio)
- Agente especializado analisa casos ambíguos em profundidade
- Agente de auditoria registra decisões com justificativa

### Desenvolvimento de software

**Time de code review**
- `investigator`: analisa o diff, identifica bugs e riscos
- `style-reviewer`: verifica padrões, nomenclatura, cobertura de testes
- `orchestrator`: consolida os feedbacks e prioriza o que bloqueia o merge

**Pipeline de debugging**
- `analyzer`: lê stack trace e código, formula hipóteses
- `fixer`: implementa a correção focada na hipótese do analyzer
- Contextos isolados evitam que o fixer "contamine" sua análise com suposições do analyzer

**Geração de features com TDD**
- `spec-writer`: transforma requisito em casos de teste
- `implementer`: escreve código para passar nos testes
- `reviewer`: valida se a implementação atende o requisito original

### Produto e pesquisa

**Pesquisa e síntese**
- `searcher`: busca informações via MCP (web, banco de dados, documentos)
- `synthesizer`: consolida as fontes em resposta coerente
- `fact-checker`: valida afirmações contra as fontes originais

**Geração de PRD / documentação**
- `interviewer`: faz perguntas ao usuário para elicitar requisitos
- `writer`: transforma respostas em documento estruturado
- `reviewer`: identifica lacunas e inconsistências no documento gerado

### Distribuição de times reutilizáveis

Por empacotar como OCI, o mesmo time de agentes pode ser:

```bash
# Publicado uma vez
docker agent share push ./pipeline.yaml time/article-pipeline

# Reutilizado em qualquer projeto
GOOGLE_API_KEY=... docker agent run time/article-pipeline
```

Isso permite criar uma **biblioteca interna de times especializados** — um time de code review, um de extração de dados, um de geração de docs — e reusar em todos os projetos sem copiar YAML.

## Instalação

O Docker Agent vem embutido no Docker Desktop 4.63+. Para Linux standalone:

```bash
# Baixar o binário (verificar versão atual em github.com/docker/docker-agent/releases)
curl -fsSL -L https://github.com/docker/docker-agent/releases/download/v1.70.2/docker-agent-linux-amd64 \
  -o ~/.docker/cli-plugins/docker-agent

chmod +x ~/.docker/cli-plugins/docker-agent

# Verificar
docker agent version
```

## Estrutura de um agente (YAML)

```yaml
agents:
  root:                              # nome do agente raiz
    model: anthropic/claude-sonnet-4-5
    description: Papel resumido do agente
    instruction: |
      Instruções detalhadas do que este agente faz...
    sub_agents: [filtro, extrator]   # agentes que pode acionar
    toolsets:
      - type: filesystem             # acesso a arquivos
      - type: shell                  # execução de comandos
      - type: mcp                    # servidor MCP externo
        ref: docker:duckduckgo

  filtro:
    model: openai/gpt-4o-mini
    description: Avalia relevância
    instruction: |
      Instruções específicas...
```

### Campos principais

| Campo | Descrição |
|---|---|
| `model` | `provider/modelo` — ex: `google/gemini-2.5-flash`, `anthropic/claude-sonnet-4-5` |
| `description` | Resumo do papel (usado pelo agente raiz para decidir a quem delegar) |
| `instruction` | System prompt do agente |
| `sub_agents` | Lista de agentes que este pode acionar |
| `toolsets` | Ferramentas disponíveis: `filesystem`, `shell`, `mcp` |

## Comandos essenciais

```bash
# Rodar um agente interativamente
docker agent run ./meu-agente.yaml

# Rodar com mensagem inicial direto
docker agent run ./meu-agente.yaml "Analise este texto: ..."

# Listar modelos disponíveis (com credenciais configuradas)
docker agent models

# Empacotar e publicar como artefato OCI
docker agent share push ./meu-agente.yaml usuario/nome-do-agente

# Baixar e rodar agente publicado
docker agent share pull usuario/nome-do-agente
docker agent run usuario/nome-do-agente
```

## Configuração

Crie um `.env` na pasta do agente com as variáveis genéricas:

```bash
LLM_API_KEY=sua-chave-aqui
LLM_MODEL=anthropic/claude-sonnet-4-5     # modelo do orchestrator
LLM_SUBAGENT_MODEL=openai/gpt-4o-mini    # modelo dos sub-agentes
```

O `run.sh` detecta o provider pelo prefixo do modelo (`google/`, `anthropic/`, `openai/`) e mapeia `LLM_API_KEY` para a variável correta do Docker Agent automaticamente. Para trocar de provider, basta alterar o `.env` — sem tocar no YAML.

## PoC — Pipeline de Filtragem de Artigos

### Objetivo

Demonstrar orquestração multi-agente com contextos isolados e delegação condicional.

### Arquitetura

```
Usuário (cola texto ou informa path de arquivo)
    │
    ▼
[orchestrator]  ← lê arquivo via toolset filesystem (se path informado)
    │
    ├──► [filter]     →  score + justificativa
    │
    ├──► [extractor]  →  título, autores, tema, metodologia, pontos-chave
    │         (só se score ≥ 0.5)
    │
    └──► [summarizer] →  resumo executivo em 3-5 frases
              (só se score ≥ 0.5)
                  │
                  ▼
        Output estruturado final
```

### Fluxo

1. Usuário cola o texto ou informa o path de um arquivo `.md`/`.txt`
2. `orchestrator` lê o arquivo (se path) via toolset `filesystem`
3. `orchestrator` passa o texto para `filter`
4. `filter` retorna: `RELEVANTE`, `SCORE` (0.0–1.0), `JUSTIFICATIVA`
5. Se score ≥ 0.5, `orchestrator` aciona `extractor` e `summarizer` em paralelo
6. `extractor` retorna: título, autores, tema, metodologia, pontos-chave
7. `summarizer` retorna: resumo executivo em 3–5 frases para não especialistas
8. `orchestrator` monta o bloco estruturado final

### Rodar

```bash
cd article-pipeline
./run.sh

# Opção 1: cole o texto do artigo diretamente no chat
# Opção 2: informe o caminho de um arquivo
# > Analise o arquivo /caminho/para/artigo.md
```

### Distribuir como OCI

```bash
# Publicar
docker agent share push ./article-pipeline/pipeline.yaml seunome/article-pipeline

# Qualquer pessoa pode rodar com:
docker agent run seunome/article-pipeline
```

## Uso em produção

O Docker Agent não é só para CLI local — ele expõe agentes como serviços prontos para integração via `docker agent serve`.

### Modos de exposição

**`serve chat`** — API compatível com OpenAI
```bash
docker agent serve chat ./pipeline.yaml \
  --listen 0.0.0.0:8083 \
  --api-key-env AGENT_TOKEN \
  --cors-origin https://seuapp.com \
  --conversations-max 100 \
  --conversation-ttl 30m
```
Qualquer SDK ou frontend que fala com a API da OpenAI conecta diretamente. Tem autenticação por Bearer token, CORS configurável e cache de conversas server-side.

**`serve api`** — API própria com sessões persistidas
```bash
docker agent serve api ./pipeline.yaml \
  --listen 0.0.0.0:8080 \
  --session-db ./sessions.db \
  --pull-interval 60
```
Persiste sessões em SQLite. O `--pull-interval` é especialmente útil para produto: publique uma nova versão do agente no Docker Hub e todos os servidores atualizam automaticamente, sem redeploy da aplicação.

**`serve mcp`** — expõe o agente como ferramenta MCP
```bash
docker agent serve mcp ./pipeline.yaml --http --listen 0.0.0.0:8081
```
Permite que Claude Code, Cursor, ou qualquer cliente MCP use o seu agente como ferramenta nativa — sem escrever código de integração.

**`serve a2a` / `serve acp`** — protocolos inter-agentes
Para quando o Docker Agent é um nó dentro de um sistema maior, recebendo delegações de outros agentes.

### Deploy

O `serve chat` é um processo HTTP comum — containerize e faça deploy em qualquer infra:

```dockerfile
FROM debian:bookworm-slim
COPY --from=docker/docker-agent:latest /usr/local/bin/docker-agent /usr/local/bin/
COPY pipeline.yaml /app/pipeline.yaml
EXPOSE 8083
CMD ["docker-agent", "serve", "chat", "/app/pipeline.yaml", \
     "--listen", "0.0.0.0:8083", "--api-key-env", "AGENT_TOKEN"]
```

```bash
# Railway, Fly.io, ECS, VPS — qualquer um serve
docker build -t meu-agente .
docker run -e LLM_API_KEY=... -e AGENT_TOKEN=... -p 8083:8083 meu-agente
```

### Limitações honestas para produção

| Limitação | Impacto |
|---|---|
| Sem rate limiting por usuário | Precisar de API gateway na frente (nginx, Traefik, Kong) |
| Auth é um token global | Não serve para SaaS multi-tenant sem camada extra |
| Projeto jovem (v1.70, jun/2025) | API pode mudar — acompanhe o changelog |
| Sem observabilidade nativa | Use `--otel` com OpenTelemetry para traces |

**Conclusão:** adequado para ferramentas internas, produtos B2B com poucos clientes e MVPs. Para SaaS com muitos usuários simultâneos, adicione uma camada de API na frente para auth e rate limiting.

---

## Exemplos de produtos

### Ferramentas internas (baixa complexidade)

**Assistente de code review para o time**
Um time configura um agente que analisa PRs, aplica os padrões da empresa e sugere melhorias. Roda como `serve chat`, integrado ao Slack via webhook ou chamado direto do CI.

**Gerador de documentação técnica**
Recebe código-fonte ou spec, produz ADRs, READMEs e changelogs no padrão da empresa. Distribuído via Docker Hub — cada projeto baixa e roda com `docker agent run empresa/doc-writer`.

**Triagem automática de issues**
Lê issues abertas no GitHub/GitLab, classifica por severidade, preenche campos faltantes e sugere o responsável. Roda como cron job chamando `docker agent run` com a issue como input.

### Produtos B2B (complexidade média)

**Plataforma de análise de contratos**
- `reader`: extrai cláusulas e obrigações do PDF/MD
- `risk-analyzer`: identifica riscos jurídicos e financeiros
- `comparator`: compara com contratos anteriores do mesmo cliente
- Exposto via `serve chat` — o frontend do cliente chama como se fosse ChatGPT

**Pipeline de curadoria de conteúdo** (próximo ao seu caso de uso atual)
- `ingester`: recebe artigos de múltiplas fontes (RSS, upload, API)
- `filter`: avalia relevância por tema configurável
- `extractor`: estrutura metadados e pontos-chave
- `publisher`: formata e envia para o destino (newsletter, banco, CMS)
- Roda como serviço contínuo; clientes configuram seus critérios de relevância via YAML próprio distribuído como OCI

**Assistente de onboarding para SaaS**
- `interviewer`: faz perguntas para entender o perfil e objetivo do novo usuário
- `configurator`: gera configuração inicial personalizada do produto
- `guide`: explica os primeiros passos com base no perfil coletado
- Integrado à página de onboarding via `serve chat` com CORS configurado

### Produtos de nicho com diferencial claro

**Revisor científico automatizado**
Recebe submissões de artigos, roda múltiplos agentes especialistas (metodologia, estatística, redação), consolida um relatório de revisão estruturado. Produto para periódicos e conferências.

**Gerador de briefings executivos**
Ingere relatórios longos, atas, e-mails e dados de dashboards; produz um briefing de 1 página com o que o executivo precisa saber antes da reunião. Alto valor percebido, baixo custo de operação.

**Ferramenta de due diligence para M&A**
- `financial-analyst`: analisa balanços e projeções
- `legal-analyst`: verifica pendências e riscos regulatórios
- `market-analyst`: avalia posição competitiva
- `reporter`: consolida em relatório executivo com seções padronizadas
- Vendido como SaaS B2B para fundos e consultorias

---

## Próximos passos

- [ ] Adicionar toolset `filesystem` para ler arquivos `.md` diretamente (sem colar texto)
- [ ] Adicionar agente `summarizer` para gerar resumo executivo
- [ ] Integrar MCP server para salvar extrações em banco ou arquivo
- [ ] Publicar no Docker Hub e testar `docker agent share pull`
- [ ] Experimentar modelos locais via LM Studio (endpoint OpenAI-compatible)
