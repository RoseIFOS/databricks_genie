# 11 — A interface da Metric View no Catalog Explorer

> **O que é este arquivo:** um tour pela tela que aparece depois que você cria a metric
> view (`hpn.4_semantic.mv_comercial`) colando o [`mv_comercial.yaml`](../../semantic/mv_comercial.yaml).
> A ideia é você entender **de onde vem cada coisa** que a UI mostra e **pra que serve** —
> porque a tela é só uma *leitura visual do YAML que você escreveu*. Nada na UI é mágica:
> tudo tem uma linha correspondente no YAML.

---

## Modelo mental (leia isto primeiro)

A metric view **não guarda dados**. Ela é um contrato semântico:

```
┌─────────────────────────────────────────────────────────┐
│  mv_comercial  (metric view = YAML declarativo)          │
│                                                          │
│   source:     v_sales_transactions   ← de onde lê        │
│   dimensions: 11 (por onde fatiar)    → aba "Fields"     │
│   measures:   13 (o que calcular)     → aba "Measures"   │
└─────────────────────────────────────────────────────────┘
                     │ lê na hora da pergunta
                     ▼
        hpn.4_semantic.v_sales_transactions  (view plana)
                     │
                     ▼
             tabelas gold (fatos + dims)
```

Quando alguém (você no SQL Editor, ou o Genie a partir de uma pergunta) pede
*"margem por país em 2013"*, o Databricks pega a **definição** da measure `Gross Margin`
+ a dimensão `Pais` + filtro `Ano`, e **monta o SQL sozinho** contra a `v_sales_transactions`.
A UT que você está vendo é o inventário desse contrato.

---

## As 4 abas do topo

A barra `Overview | Measures (13) | Fields (11) | Materializations (0)` é a estrutura do
objeto. Os números entre parênteses vêm **direto da contagem do YAML**:

| Aba | Nº | De onde vem no YAML | Pra que serve |
|---|---|---|---|
| **Overview** | — | tudo junto | Visão consolidada + **Preview** dos dados |
| **Measures** | 13 | bloco `measures:` | As medidas (o que calcular / agregar) |
| **Fields** | 11 | bloco `dimensions:` | As dimensões (por onde fatiar/filtrar) |
| **Materializations** | 0 | (nenhuma definida) | Cache opcional pré-calculado (ver adiante) |

> Repare: **13 measures + 11 fields** batem exatamente com o que você colou — 13 itens em
> `measures:` e 11 em `dimensions:`. Se algum número viesse diferente, seria sinal de que o
> YAML não colou inteiro.

---

## Aba **Fields (11)** — as dimensões

Cada linha é um par **Name → Expression**, e é a tradução 1:1 do bloco `dimensions:`:

| Name (rótulo de negócio) | Expression (coluna real na view) |
|---|---|
| Data | `order_date` |
| Ano | `order_year` |
| Mes | `order_month` |
| Cliente | `customer_name` |
| TipoNegocio | `business_type` |
| Regiao | `region_name` |
| Pais | `country_name` |
| Cidade | `city_name` |
| Categoria | `category_name` |
| Subcategoria | `subcategory_name` |
| Produto | `product_name` |

- **Name** = linguagem de negócio (o que o usuário e o Genie enxergam). Por isso está em
  PT-BR e limpo.
- **Expression** = a coluna física na `v_sales_transactions`.
- O **ícone** à esquerda indica o tipo: 📅 = data (`Data`), `1²3` = número (`Ano`, `Mes`),
  `A` = texto (o resto).

**Dimensão não agrega nada** — ela só define os eixos e filtros possíveis. É o equivalente
às colunas que você arrastaria para um eixo ou segmentação no Power BI.

---

## Aba **Measures (13)** — as medidas

Também é **Name → Expression**, vinda do bloco `measures:`. Aqui, ao contrário das
dimensões, a `Expression` **contém a agregação** (`SUM`, `AVG`, `COUNT(DISTINCT ...)`):

| Name | O que faz (resumo) |
|---|---|
| Gross Sales | Soma do bruto só das linhas `transaction_type = 'sale'` |
| Returns | Soma do bruto só das `'return'` |
| Discounts | Soma dos descontos |
| Cost of Sales | Soma de `quantity * unit_cost` das vendas |
| Quantity | Soma da quantidade vendida |
| Customers Current | Contagem distinta de clientes que compraram |
| Net Sales | Gross Sales − Discounts − Returns |
| Gross Margin | Net Sales − Cost of Sales |
| Gross Margin % | (Gross Sales − Cost of Sales) / Gross Sales |
| Net Margin % | (Net Sales − Cost of Sales) / Net Sales |
| % Returns | Returns / Gross Sales |
| Avg Unit Price | Preço unitário médio das vendas |
| Avg Unit Cost | Custo unitário médio das vendas |

Dois detalhes importantes:

1. **O `CASE WHEN transaction_type = ...`** existe porque venda e devolução moram na
   **mesma** view (unidas por `UNION ALL`). Então cada measure *base* precisa dizer *de qual
   tipo de linha* ela soma. É o preço de ter uma view única — em troca, a governança fica simples.
2. **Measure PODE referenciar outra measure** (composabilidade — `version: 1.1`). Assim como
   no DAX você escreve `[Gross Margin] = [Net Sales] - [Cost of Sales]`, aqui as measures
   compostas usam `MEASURE(\`Nome\`)`:
   ```yaml
   - name: Net Sales
     expr: MEASURE(`Gross Sales`) - MEASURE(`Discounts`) - MEASURE(`Returns`)
   - name: Gross Margin
     expr: MEASURE(`Net Sales`) - MEASURE(`Cost of Sales`)
   ```
   Só as **base** (Gross Sales, Returns, Discounts, Cost of Sales, Quantity, Customers Current)
   têm o `CASE WHEN`; as **derivadas** reaproveitam as base. Se você mudar a lógica de uma base,
   todas as derivadas herdam a mudança automaticamente — sem duplicação.

> ⚠️ Isso só vale a partir da **`version: 1.1`** do formato. Na `0.1` (versão antiga) não havia
> `MEASURE()` e era preciso reescrever a fórmula inteira em cada measure. Se você abrir um YAML
> velho e vir fórmulas repetidas, é disso que se trata.

> `Gross Margin %` e `% Returns` usam `NULLIF(..., 0)` no denominador: se o Gross Sales de
> um recorte for zero, em vez de erro de divisão por zero o resultado vira `NULL`.

> **Metadata que o Genie usa** (também 1.1): além de `comment:`, cada item pode ter
> `display_name:` (rótulo bonito no dashboard), `synonyms:` (formas alternativas de o usuário
> perguntar — "CMV", "COGS", "custo") e `format:` (moeda USD, percentual, nº de casas). Quanto
> mais rico, melhor o Genie interpreta e melhor o número aparece formatado.

---

## Aba **Overview** — o painel consolidado + **Preview**

A Overview junta a lista de Measures e Fields do lado esquerdo e, à direita, um **Preview**:
uma amostra de linhas já com as dimensões resolvidas. Serve para você **conferir na hora**
que as expressões apontam pras colunas certas (ex.: ver que `Cliente` mostra "Supplements
Gun", `Pais`/`TipoNegocio` vêm preenchidos). É um sanity-check visual, não o dado final —
os números "de verdade" saem quando você consulta com `MEASURE(...)` (o Passo 4 do runbook).

---

## Aba **Materializations (0)** — e por que está zerada (de propósito)

Uma *materialization* seria um **cache pré-calculado** de uma combinação de measures +
dimensions, para acelerar consultas pesadas. É **opcional** e, para o nosso MVP, deixamos
**0** de propósito:

- O volume é pequeno (~64 mil linhas); a view calcula na hora sem dor.
- Materializar cedo demais adiciona custo de storage e de atualização sem ganho real.
- Se um dia uma pergunta do Genie ficar lenta, aí sim criamos uma materialization
  específica. Otimização é resposta a um problema medido, não profilaxia.

`No materializations defined` = tudo certo, nada a fazer aqui agora.

---

## Os botões do canto (o que são e o que **não** vamos usar agora)

- **+ Add** (dentro de Measures/Fields) — adicionar dimensão/measure pela UI em vez do YAML.
  Evite: a **fonte de verdade é o YAML versionado** no git (`mv_comercial.yaml`). Editar pela
  UI cria *drift* (a UI e o arquivo divergem). Se precisar mudar, muda o YAML e recola.
- **+ Add parameter** — cria parâmetros dinâmicos (ex.: uma meta que o usuário digita). Não
  precisamos para o comercial.
- **Join** — permitiria a metric view juntar outra tabela. **Não usamos** — foi decisão de
  projeto: a `v_sales_transactions` **já vem denormalizada** (todos os joins foram feitos na
  view). Por isso o YAML não tem `joins:` e a metric view é "plana". Menos junção = menos
  chance de o Genie errar cardinalidade.

---

## Resumo de uma linha

A tela inteira é o **espelho visual do `mv_comercial.yaml`**: `Fields` = suas dimensões,
`Measures` = suas medidas, `Preview` = amostra pra conferência, `Materializations` = cache
opcional (vazio de propósito). A fonte de verdade continua sendo o YAML no git — a UI só
o lê e o executa.

> **Próximo passo (runbook Passo 4):** validar a paridade dos números contra o Power BI
> consultando `MEASURE(...)` no SQL Editor.
