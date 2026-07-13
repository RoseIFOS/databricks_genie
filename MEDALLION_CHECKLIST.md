# Checklist Medallion — origem (Neon OLTP) → Silver → Gold

> Fonte: `dbo.*` no Postgres Neon (14 tabelas). Bronze = 1:1 (OVERWRITE, pronto).
> Silver = limpeza conformada 1:1 (cast/trim/snake_case/dedup/auditoria + expectations).
> Gold = modelagem dimensional (star schema) + regra de negócio + comentários p/ Genie.

> **Status geral (2026-07-12):** Silver (14) e Gold (13) implementados e versionados.
> Próximo: **Fase 3 — camada semântica** (comentários, tags, Metric Views, funções UC).

## Dimensões (9) — fazer PRIMEIRO

| # | Origem `dbo.*` | Linhas | Silver `2_silver.*` | Gold `3_gold.*` | Silver | Gold |
|---|---|---|---|---|---|---|
| 1 | customer            | 701 | customer            | dim_customer          | ✅ | ✅ `01_dim_customer.sql` |
| 2 | account             | 35  | account             | dim_account           | ✅ | ✅ `04_dim_account.sql` |
| 3 | account_header      | 10  | account_header      | dim_account_header    | ✅ | ✅ `05_dim_account_header.sql` |
| 4 | organization        | 9   | organization        | dim_organization      | ✅ | ✅ `06_dim_organization.sql` |
| 5 | department_group    | 7   | department_group    | dim_department_group  | ✅ | ✅ `07_dim_department_group.sql` |
| 6 | geography           | 638 | geography           | dim_geography ┐       | ✅ | ✅ `02_dim_geography.sql` |
| 7 | region              | 11  | region              | dim_geography ┘ (join)| ✅ | ✅ `09_dim_region.sql` |
| 8 | product             | 349 | product             | dim_product ┐         | ✅ | ✅ `03_dim_product.sql` |
| 9 | product_sub_category| 18  | product_sub_category| dim_product ┘ (join)  | ✅ | ✅ (join no dim_product) |

> **Extra no Gold:** `08_dim_calendar.sql` — gerada no Gold (não existe na origem OLTP).

## Fatos (5) — depois das dims

| # | Origem `dbo.*` | Linhas | Silver `2_silver.*` | Gold `3_gold.*` | Silver | Gold |
|---|---|---|---|---|---|---|
| 10 | sales_header         | 3.796  | sales_header         | (join no fct_sales_details) | ✅ | ✅ (join no fct_sales_details) |
| 11 | sales_details        | 60.855 | sales_details        | fct_sales_details           | ✅ | ✅ `11_fct_sales_details.sql` |
| 12 | sales_returns        | 3.869  | sales_returns        | fct_sales_returns           | ✅ | ✅ `12_fct_sales_returns.sql` |
| 13 | finance              | 49.944 | finance              | fct_finance                 | ✅ | ✅ `10_fct_finance.sql` |
| 14 | product_cost_history | 12.231 | product_cost_history | fct_product_cost_history    | ✅ | ✅ `13_fct_product_cost_history.sql` |

---

## Decisões que o banco revelou (pra resolver quando chegarmos nos fatos)

1. **Dinheiro veio como texto (`character varying`)** em: `unitprice`, `extendedamount`,
   `amount`, `unitcost`, `totalamount`, `discountamount`, `salesamount`, `returnamount`.
   → Silver faz `CAST(... AS DECIMAL(18,2))`. **Antes precisamos amostrar** os valores
   pra saber o separador (ponto vs vírgula, símbolo de moeda) — CAST direto quebra se
   houver "1.234,56" ou "$". **Só afeta os fatos + sales_header** (por isso dims primeiro).

2. **Datas vieram como texto** em: `transaction_date`, `orderdate`, `duedate`,
   `shipdate`, `returndate`. → `CAST(... AS DATE)` ou `to_date(col, '<formato>')`.
   Precisamos ver o formato antes. Também só afeta fatos/sales_header.

3. **Não existe tabela de calendário na origem.** `dim_calendar` (do PLANO) terá que ser
   **gerada no Gold** (sequência de datas), não vem do OLTP.

4. **Colunas com maiúscula**: `product."Size"` e `product_cost_history."Year"`.
   No Spark precisam de backtick; no Silver já renomeamos p/ snake_case (`size`, `year`).

5. **`finance` já vem em snake_case** e com padrão de chave diferente (`finance_key`,
   `account_key`...). Só conformar, sem inventar renome.

## Convenção Silver (padrão fechado — aplicar em todas)
- `CREATE OR REFRESH MATERIALIZED VIEW` (Bronze é OVERWRITE → recomputa).
- Renomear chaves p/ snake_case: `<x>key` → `<x>_key`.
- `TRIM()` em todo texto; `CAST` explícito de tipos.
- Colunas técnicas com prefixo `_`: `_source_id` (= `id` da origem) e `_silver_loaded_at`.
- Dedup: `QUALIFY ROW_NUMBER() OVER (PARTITION BY <chave> ORDER BY id DESC) = 1`.
- Expectations mínimas: chave `IS NOT NULL` (`ON VIOLATION DROP ROW`); valores que não
  podem ser negativos, quando fizer sentido.
- Comentário só de TABELA no Silver (comentário por coluna fica no Gold, p/ Genie).
