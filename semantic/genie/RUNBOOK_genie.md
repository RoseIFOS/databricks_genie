# RUNBOOK — Setup do Genie Space (UI) · Fase 5

> Passo-a-passo para criar e curar os Genie Spaces na UI do Databricks, e referência
> dos tipos de instrução disponíveis. Os artefatos de conteúdo (instruções e trusted
> queries) ficam nos arquivos irmãos desta pasta:
> - `comercial_instructions.md` / `comercial_trusted_queries.sql`
> - `financeiro_instructions.md` / `financeiro_trusted_queries.sql` (Fase 5.2)

---

## Onde criar (navegação)

Na **barra lateral esquerda**, procure **Genie** (o produto se chama "AI/BI Genie").
Dependendo da versão do workspace ele aparece:
- direto como **Genie**, ou
- agrupado embaixo de **SQL** → **Genie**, ou
- como **Genie Agents**.

É o mesmo lugar. Clica nele → botão **New** (ou **+ New Genie space**).

> Se não achar: usa a busca do topo (Ctrl+P / a lupa) e digita "Genie".

---

## Sequência completa (Space Comercial)

**1. Criar o Space**
- Genie → **New**
- **SQL Warehouse**: escolhe o **serverless** (é o motor que roda as queries — sem ele
  o Space não responde).
- **Título**: `Comercial — HPN`

**2. Adicionar os data assets** (aba/painel **Data**)
Adiciona **só estes 4** (navega em `hpn` → `4_semantic`):
- `mv_comercial` ← metric view (fonte primária)
- `v_sales_time_intelligence` ← MoM/YoY
- `dim_customer_rfm` ← segmentos RFM
- `v_sales_transactions` ← view plana (detalhe/fallback)

⚠️ **Não** adiciona os fatos/dims crus do `3_gold` — menos ativos e mais curados =
respostas melhores.

**3. General Instructions** (aba **Instructions**)
- Cola o bloco de texto de `comercial_instructions.md` (a partir de *"Você é o
  assistente..."* — o topo com `>` é só nota, não cola).

**4. Example SQL queries** (em **Instructions** → seção **Examples**)
- Para **cada** bloco de `comercial_trusted_queries.sql`: **Add → Example query**.
  A linha `-- P:` vira a **pergunta**, o SQL abaixo vai no **corpo**.

**5. Sample questions** (opcional, mesma aba)
- Adiciona 3-5 perguntas modelo (ex.: "Vendas líquidas por região", "Quais os 10
  produtos com maior venda?").

**6. Testar**
- Volta pro chat do Space e roda o benchmark (Fase 5.3). Ajusta as instruções conforme
  errar.

**7. Permissões** (depois, junto com o RLS)
- **Share** → restringe ao grupo comercial + admin. Deixa pro fim (ver `RUNBOOK_rls.md`).

> **Validar antes de cadastrar em massa:** roda **1 query** (ex.: "vendas líquidas por
> região") no **SQL Editor** apontando pra `mv_comercial`. Se o `MEASURE(...)` retornar
> valor, a sintaxe de metric view está validada e cadastramos as demais com confiança.

---

## Tipos de instrução (menu "Add" da seção Examples)

A versão nova do Genie tem instruções **granulares**, não só "Example SQL":

| Tipo (botão Add) | O que faz | Usamos? |
|---|---|---|
| **Example query** | Par pergunta → SQL (o "trusted asset" clássico) | ✅ **Sim** — as trusted queries |
| **Join** | Ensina o Genie **como juntar** duas tabelas (chaves) | ✅ **Sim** — `dim_customer_rfm` ↔ `v_sales_transactions` por `customer_key`. Sem isso o Genie chuta o join pra buscar nome do cliente |
| **Field** | Anota **uma coluna** (descrição + sinônimos) | ⚠️ Opcional — a metric view já tem `synonyms`/`comment`. Útil só nas views cruas (RFM/time intelligence) que não têm metadados |
| **Filter** | Filtro nomeado reutilizável (ex.: "só vendas", "só At Risk") | ⚠️ Opcional — a metric view já resolve `transaction_type` nas measures |
| **Measure** | Definir uma measure **em texto** | ❌ **Não** — nossas measures vivem na metric view (`mv_comercial`). Esse slot serve pra quem **não** tem metric view |

**Ordem de cadastro recomendada:**
1. **Joins** primeiro (RFM↔transações; time intelligence é standalone).
2. **Example queries** (as trusted queries).
3. **Fields** só nas 2 views cruas, se valer a pena (senão as instructions gerais cobrem).

> **Por que ignorar o "Measure":** nosso diferencial é ter a metric view pronta
> (`mv_comercial` / `mv_financeiro`), que é mais robusta e versionada. O slot Measure
> existe pra Spaces sem metric view.

---

## Detalhe do "Example query": Parameters e Usage Guidance

Ao criar um **Example query**, além de pergunta+SQL, há duas seções que deixam o
exemplo muito mais potente:

### Parameters — transforma 1 exemplo num template reutilizável
Em vez do valor ficar "chumbado" no SQL, declara-se um **parâmetro** que o Genie
preenche conforme a pergunta. Um exemplo vira molde pra várias perguntas.

Exemplo — clientes por segmento RFM:
```sql
-- chumbado:
WHERE rfm.segment = 'At Risk'
-- parametrizado:
WHERE rfm.segment = :segmento
```
A **mesma** trusted query passa a responder "clientes At Risk", "Champions",
"Hibernating"… O Genie identifica o segmento na pergunta e injeta em `:segmento`.
Bons candidatos: filtro por `Regiao`, `Ano`, `Categoria`, `segmento`.

### Usage Guidance — ensina QUANDO usar aquele exemplo
Texto livre que diz ao Genie em que situação o exemplo é o certo. Serve pra
**desambiguar** exemplos parecidos.

Exemplo — temos duas fontes de "vendas por tempo":
- metric view (`mv_comercial`, dimensão `Ano`) → série simples
- `v_sales_time_intelligence` → variação MoM/YoY

Na query de time intelligence, o Usage Guidance seria:
> "Use quando a pergunta for sobre **crescimento, tendência ou variação** ao longo do
> tempo (mês a mês / ano a ano). Para totais por ano sem variação %, prefira a metric
> view."

Isso evita o Genie usar a view de LAG numa pergunta simples, ou vice-versa.

---

## Formato enriquecido das trusted queries

Para aproveitar Parameters + Usage Guidance, cada bloco dos arquivos
`*_trusted_queries.sql` carrega (quando aplicável):
- `-- P:`    → a pergunta (campo pergunta/título)
- `-- GUIA:` → o Usage Guidance
- `-- PARAM:`→ os parâmetros (troca o literal por `:nome`)
- o SQL      → o corpo do Example query

---

## Conceitos e decisões (FAQ)

### 1. Por que definir measures no arquivo de metric view é melhor do que criar measures pela UI do Genie?

A UI do Genie permite declarar uma "Measure" em texto direto no Space. Evitamos isso de
propósito — a metric view (`mv_comercial` / `mv_financeiro`) é superior por:

- **É fonte única de verdade.** A lógica da measure (ex.: "Net Sales = Gross − Desc −
  Dev") vive em UM lugar. Measure na UI do Genie fica presa àquele Space; se o outro
  Space, um dashboard ou o app (Fase 7) precisar da mesma measure, tem que reescrever —
  e as versões divergem com o tempo.
- **É versionada em Git.** Histórico, code review, rollback e diff (foi assim que o bug
  do NULL foi corrigido e rastreado). Measure na UI não tem histórico.
- **Tem governança do Unity Catalog.** Lineage, permissões, tags de domínio e
  descoberta no Catalog Explorer. Measure na UI é opaca fora do Space.
- **É reutilizável por qualquer consumidor.** SQL Editor, dashboards, Genie e o app
  consomem a MESMA metric view com `MEASURE(...)`. Consistência garantida entre canais.
- **Tem composabilidade (formato 1.1).** `MEASURE(\`Nome\`)` reaproveita measures base
  sem duplicar fórmula; metadata (`display_name`, `synonyms`, `format`) melhora tanto o
  Genie quanto dashboards.

> Regra do projeto: measures vivem na metric view. O slot "Measure" da UI do Genie só
> existe para Spaces que NÃO têm metric view — não é o nosso caso.

### 2. O campo "Instructions": que tipo de prompt é, impacto de deixar em branco, e estrutura recomendada

- **Que tipo de prompt é:** é texto livre em linguagem natural que funciona como o
  *system prompt* / contexto de negócio do Space. É a camada semântica "humana" —
  ensina vocabulário, regras e convenções que o schema sozinho não expressa.
- **Impacto de deixar em branco:** o Genie fica só com os metadados técnicos (nomes de
  coluna e `comment` das tabelas). Sem glossário nem regras ele: não entende
  jargão de negócio ("faturamento", "CMV"), pode escolher a measure errada, formata mal
  (não sabe que é USD, que contagem é inteiro), não sabe convenções (bruto vs líquido,
  período fiscal) e alucina mais. As respostas ficam tecnicamente possíveis, porém menos
  confiáveis.
- **Estrutura padrão recomendada** (a que usamos em `*_instructions.md`):
  1. **Papel / persona + idioma** ("Você é o assistente Comercial… responda em PT-BR").
  2. **Fonte primária** (qual metric view usar e a sintaxe `MEASURE(...)`).
  3. **Regras de formatação** (moeda USD, quantidade inteira, % com 1 casa).
  4. **Glossário / sinônimos** (termo de negócio → measure correta).
  5. **Definições de negócio** (o que é "vendas", devolução como transação separada…).
  6. **Tempo** (dimensões e âncora histórica, não `current_date`).
  7. **Casos especiais / armadilhas** (% VA, sinal contábil, paridade esperada).
  8. **Estilo de resposta** (número primeiro; declarar suposições).

### 3. O que acontece se eu não cadastrar queries de exemplo?

O Genie continua funcionando — ele gera SQL do zero a partir do schema + instruções.
Mas os Example queries são o "few-shot" que ancora os padrões que ele NÃO deduz sozinho:

- **Padrões complexos quebram ou saem inconsistentes:** time intelligence (MoM/YoY),
  RFM e a análise vertical (% VA) dificilmente saem certos sem um exemplo.
- **Ambiguidade de fonte:** sem exemplo + Usage Guidance, ele não sabe escolher entre a
  metric view (série simples) e a view de time intelligence (variação %).
- **Joins arriscados:** sem exemplo/join declarado, ele pode juntar tabelas pela chave
  errada e duplicar linhas.

Resumo: perguntas simples ("total de vendas") saem bem só com instruções; as complexas
dependem dos exemplos. Sem eles, a acurácia cai justamente nas perguntas que dão valor.

### 4. Como as abas Monitor e Benchmark contribuem para as áreas técnica e de negócio?

- **Monitor (observabilidade):** registra as perguntas reais dos usuários, o SQL que o
  Genie gerou, sucesso/erro e o feedback (👍/👎).
  - *Técnico:* debugar respostas ruins, achar gaps de curadoria, medir uso e custo.
  - *Negócio:* enxergar o que o time realmente pergunta → priorizar quais dados/measures
    curar em seguida.
- **Benchmark (qualidade repetível):** um conjunto curado de perguntas com resposta
  esperada, rodado sempre que as instruções mudam.
  - *Técnico:* funciona como teste de regressão da curadoria — mudou uma instrução,
    reroda e vê se algo quebrou. Métrica objetiva de acurácia antes de liberar.
  - *Negócio:* dá confiança/SLA de que o assistente responde certo o suficiente para ir
    para produção, com um número (% de acerto) em vez de "achismo".

> Em conjunto: o Benchmark garante qualidade ANTES de liberar; o Monitor alimenta a
> próxima rodada de melhoria DEPOIS de liberar (o que errou vira novo Example query ou
> ajuste de instrução). É o ciclo de melhoria contínua da camada semântica conversacional.

### 5. Diferença entre "Chat" e "Agent"

> Os rótulos exatos variam por versão do workspace (o menu pode aparecer como "Genie
> Agents"). O que importa é a distinção conceitual abaixo — ela não muda.

Um mesmo Genie Space pode ser consumido de duas formas:

- **Chat** — a experiência **conversacional interativa** para pessoas. Um usuário digita
  perguntas em linguagem natural e recebe tabela/SQL/gráfico. É **stateful**: guarda o
  contexto da conversa, então dá para fazer perguntas de acompanhamento ("e por região?"
  depois de "quanto vendemos?"). É a superfície que estamos curando e testando na Fase 5.

- **Agent** — o mesmo Genie **consumido programaticamente**, como um componente de
  software, não por uma pessoa numa tela. Duas materializações:
  1. Via **Genie Conversation API** (`start-conversation` / `create-message` / poll),
     que é como o **Databricks App da Fase 7** vai enviar perguntas e receber respostas
     para renderizar no frontend próprio (React + FastAPI).
  2. Como **ferramenta dentro de um sistema multi-agente** (Mosaic AI Agent Framework):
     um LLM orquestrador decide quando chamar o Genie (pergunta factual sobre dados) vs
     outras ferramentas — forecast, análise causal, recomendação (Fase 6). É exatamente o
     roteamento condicional que o projeto original fazia no LangGraph.

**Mapa para as fases do projeto:**

| | Chat | Agent |
|---|---|---|
| Quem usa | Pessoa, na UI do Genie | App / outro agente, via API |
| Estado | Conversa com contexto | Chamada programática (a app gerencia o histórico) |
| Onde no plano | Fase 5 (curar e validar) | Fase 6 (roteamento) e Fase 7 (app) |
| Depende de | Instructions + trusted queries | O MESMO Space curado na Fase 5 |

> Ponto-chave: **os dois usam a mesma curadoria**. Tudo que investimos aqui (instructions,
> example queries, joins, metric views) vale igual quando o Space é chamado como Agent
> pela app. Curar bem o Chat na Fase 5 é pré-requisito para o Agent funcionar na Fase 7.

### 6. O Genie aprende com o uso? (aprendizado curado, não automático)

**Não automaticamente.** O Genie NÃO faz fine-tuning nem "aprende" das conversas por
conta própria. Cada pergunta é resolvida do zero a partir de: schema + instructions +
example queries + contexto da conversa atual.

O aprendizado é **human-in-the-loop**:
- Feedback (👍/👎) e as perguntas reais aparecem no **Monitor**.
- Uma pergunta boa (com o SQL certo) você **promove manualmente** a Example query /
  verified query / instrução.
- Só então o Genie "melhora" — porque você melhorou a curadoria.

Dentro de UMA conversa ele lembra o contexto (permite follow-ups como "e por região?"),
mas isso não persiste como aprendizado entre sessões. Resumo: **o Genie não evolui
sozinho; você evolui a camada semântica e ele passa a acertar mais.**

### 7. Latência: de onde vem e como reduzir

A latência de uma resposta tem 3 componentes:

| Componente | O que é | Impacto |
|---|---|---|
| 1. LLM (NL → SQL) | O modelo raciocinando p/ gerar a query | Alguns segundos, inerente |
| 2. Warehouse | Ligar/aquecer o SQL Warehouse | **Cold start** — a 1ª query após ocioso é a mais lenta |
| 3. Execução SQL | Rodar a query nos dados | Depende de volume/joins |

**Diagnóstico rápido:** rode a mesma pergunta 2-3× seguidas. Se só a 1ª é lenta → é
cold start (normal). Se TODAS são lentas → investigar query/warehouse.

**Como reduzir:**
- **Serverless SQL Warehouse** (startup em segundos). Warehouse *classic* tem cold start
  de minutos → evitar.
- **Auto-stop** não muito curto durante testes (senão desliga entre perguntas e toda
  pergunta paga cold start).
- **Poucos data assets** (mantivemos 4) → menos schema p/ o LLM processar.
- **Instructions enxutas e focadas.**
- Se persistir com warehouse quente, investigar a view base (`v_sales_transactions`);
  materializar se for pesada. Só relevante se as queries no SQL Editor também estiverem lentas.

### 8. Cache e similaridade semântica (como o Genie recupera o que já existe)

O Genie tem, sim, mecanismos de cache/recuperação — em **camadas distintas**:

- **Cache de resultado (nível Databricks SQL, não do Genie):** o warehouse tem *query
  result cache* — se o **mesmo SQL exato** rodar de novo, o resultado volta do cache, sem
  reprocessar. Também há *disk cache* de dados quentes. Vale para o SQL gerado; se o Genie
  gerar um SQL levemente diferente, o cache não bate.

- **Similaridade semântica (aqui é do Genie):** ao receber a pergunta, o Genie NÃO empilha
  todos os exemplos no prompt — faz *matching semântico* entre a pergunta e os ativos
  curados (instructions, example queries, verified queries) e **recupera os mais
  relevantes** como few-shot. Por isso:
  - "clientes em risco" casa com o exemplo "clientes At Risk" sem palavras idênticas
    (é retrieval, não palavra-chave);
  - adicionar muitos exemplos NÃO deixa linearmente mais lento — só os relevantes entram
    no prompt.

- **Verified / trusted answers (quase um "cache de Q→SQL"):** ao marcar uma pergunta+SQL
  como verificada, perguntas muito parecidas podem **reutilizar aquele SQL certificado**
  direto, em vez de gerar do zero — mais rápido e mais confiável (o Genie sinaliza
  "resposta baseada em query verificada").

**Como isso concilia com "não aprende sozinho" (FAQ 6):** não é contradição. O
cache/semântica é mecanismo de *recuperação* do que **já existe** (seus exemplos, SQL
idêntico anterior); "não aprende sozinho" = ele não *cria* curadoria nova a partir do uso.
O retrieval semântico é justamente o que faz a sua curadoria "pegar" em perguntas
parecidas — quanto melhor curar, mais o matching acerta.

> Nota de honestidade: os internals exatos (modelo de embedding, TTL do cache, limiar de
> similaridade) a Databricks não documenta em detalhe — o descrito é o comportamento
> observável e a arquitetura geral.
