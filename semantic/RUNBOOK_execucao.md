# RUNBOOK — Execução da Camada Semântica (Comercial)

> **Objetivo:** aplicar a camada semântica comercial do zero, na ordem certa, sabendo
> **onde** rodar **cada** script. Siga de cima pra baixo; marque os checkboxes conforme
> avança. Tudo roda no **catálogo `hpn`** (ambiente interativo/dev).

**Onde rodar cada coisa:**
- **SQL Editor** (Databricks → SQL → *SQL Editor*, com um **SQL Warehouse** ligado) → scripts `.sql`.
- **Catalog Explorer** (Databricks → *Catalog*) → criação da **Metric View** (UI).

---

## Passo 0 — Pré-checagem (SQL Editor)  ⏱️ 1 min

Confirmar que o schema semântico existe e o gold está acessível.

```sql
SHOW SCHEMAS IN hpn;                         -- deve listar 3_gold e 4_semantic
SHOW TABLES IN hpn.`3_gold`;                 -- deve listar as 13 tabelas gold
```
- [ ] `4_semantic` existe. Se **não**: `CREATE SCHEMA IF NOT EXISTS hpn.`4_semantic`;`

---

## Passo 1 — Criar a view plana (SQL Editor)  ⏱️ 2 min

**Script:** [`semantic/01_gold_views.sql`](01_gold_views.sql)
**Onde:** SQL Editor → cole o arquivo inteiro → **Run**.

Isso cria `hpn.4_semantic.v_sales_transactions` e aplica os tags de governança.

- [ ] Rodou sem erro.
- [ ] Fumaça rápida:
  ```sql
  SELECT transaction_type, COUNT(*) AS linhas, SUM(gross_amount) AS bruto
  FROM hpn.`4_semantic`.v_sales_transactions
  GROUP BY transaction_type;
  ```
  Espera-se 2 linhas: `sale` e `return`.

---

## Passo 2 — Validar a view ANTES da metric view (SQL Editor)  ⏱️ 5 min

> Estes 3 checks pegam os riscos anotados. **Não pule** — se falharem, a metric view herda
> o erro.

### 2a. Grão único do custo (senão o lookup infla linhas)
```sql
SELECT product_key, year, month_no, country_code, COUNT(*) AS n
FROM hpn.`3_gold`.fct_product_cost_history
GROUP BY product_key, year, month_no, country_code
HAVING COUNT(*) > 1;
```
- [ ] **Voltou vazio** → lookup seguro. Se voltar linhas → o custo duplica vendas; precisa
  dedup no `fct_product_cost_history` antes de confiar nos números.

### 2b. Nenhuma venda foi perdida no JOIN (INNER descarta órfãos)
```sql
SELECT
  (SELECT SUM(gross_sales) FROM hpn.`3_gold`.fct_sales_details)                       AS gold_bruto,
  (SELECT SUM(gross_amount) FROM hpn.`4_semantic`.v_sales_transactions
     WHERE transaction_type = 'sale')                                                 AS view_bruto;
```
- [ ] Os dois valores **batem**. Se `view_bruto` < `gold_bruto` → há vendas com
  cliente/produto órfão sendo descartadas.

### 2c. Quanto de custo ficou NULL (subestima margem)
```sql
SELECT
  COUNT(*)                                        AS linhas_venda,
  COUNT(*) - COUNT(unit_cost)                     AS sem_custo,
  ROUND((COUNT(*) - COUNT(unit_cost)) * 100.0 / COUNT(*), 1) AS pct_sem_custo
FROM hpn.`4_semantic`.v_sales_transactions
WHERE transaction_type = 'sale';
```
- [ ] Anotar `pct_sem_custo`. Se for alto, `Cost of Sales`/`Gross Margin` sairão otimistas
  — decidir regra (excluir? custo default?) antes de liberar pro Genie.

---

## Passo 3 — Criar a Metric View (Catalog Explorer — UI)  ⏱️ 3 min

**Arquivo-fonte:** [`semantic/mv_comercial.yaml`](mv_comercial.yaml)

1. Databricks → **Catalog** → navegar `hpn` → `4_semantic`.
2. Botão **Create** → **Metric View**.
3. Nome: **`mv_comercial`**.
4. Cole **todo** o conteúdo do `mv_comercial.yaml` no editor de definição.
5. **Create / Save**.

- [ ] Criada sem erro de validação (se reclamar de coluna, conferir nome vs a view do Passo 1).

> Alternativa DDL (só se sua versão suportar `CREATE VIEW ... WITH METRICS`): não obrigatória
> pro MVP; a UI é o caminho garantido.

---

## Passo 4 — Paridade vs Power BI (SQL Editor)  ⏱️ 10-15 min

> Query numa metric view usa `MEASURE()` nas medidas e o nome da dimensão direto.
> Rode e **compare cada número com o mesmo gráfico no Power BI**.

### 4a. Medidas base por ano
```sql
SELECT
  `Ano`,
  MEASURE(`Gross Sales`)   AS gross_sales,
  MEASURE(`Discounts`)     AS discounts,
  MEASURE(`Returns`)       AS returns,
  MEASURE(`Net Sales`)     AS net_sales,
  MEASURE(`Cost of Sales`) AS cost_of_sales,
  MEASURE(`Gross Margin`)  AS gross_margin,
  MEASURE(`Quantity`)      AS quantity
FROM hpn.`4_semantic`.mv_comercial
GROUP BY `Ano`
ORDER BY `Ano`;
```

### 4b. Percentuais por ano
```sql
SELECT
  `Ano`,
  MEASURE(`Gross Margin %`) AS gm_pct,
  MEASURE(`Net Margin %`)   AS nm_pct,
  MEASURE(`% Returns`)      AS returns_pct
FROM hpn.`4_semantic`.mv_comercial
GROUP BY `Ano`
ORDER BY `Ano`;
```

**Tabela de conferência (preencher):**

| Medida | Databricks | Power BI | Bate? |
|---|---|---|---|
| Gross Sales (total) | | | |
| Net Sales (total) | | | |
| Returns (total) | | | |
| Gross Margin % | | | |
| % Returns | | | |

- [ ] Todas as medidas batem (ou a diferença é explicada — ex.: custo NULL do Passo 2c).

---

## Passo 5 — Fechar

- [ ] Commit dos scripts (`semantic/`) se ainda não commitado.
- [ ] Se algum check 2a/2b/2c falhou, anotar a correção necessária antes de plugar no Genie.
- [ ] **Próximo (Fase 5):** criar o Genie Space "Comercial" apontando pra `mv_comercial`.

---

### Ordem resumida
```
0. Pré-check schema         → SQL Editor
1. 01_gold_views.sql        → SQL Editor (cria a view)
2. Checks 2a/2b/2c          → SQL Editor (validar view)
3. mv_comercial.yaml        → Catalog Explorer UI (cria a metric view)
4. Paridade vs Power BI     → SQL Editor (MEASURE(...))
5. Commit + Genie Space
```
