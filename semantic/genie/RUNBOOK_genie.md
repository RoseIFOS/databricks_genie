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
