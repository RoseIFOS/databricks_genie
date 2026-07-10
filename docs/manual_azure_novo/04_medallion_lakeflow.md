# 04 — Medallion com Lakeflow Declarative Pipelines

> Substitui: *"Bronze Ingestion"* e os notebooks `1.Bronze / 2.Silver / 3.Gold`
> de *"Processamento com Databricks"*.

## A mudança de mentalidade

No manual antigo, cada camada era um **notebook imperativo**:
`spark.read.parquet(...) → withColumn('bronze_ingestion_timestamp', ...) →
saveAsTable('hive_metastore.olist_bronze.Customers')`, rodado célula a célula, na
mão. Você escrevia o *como* (ler, transformar, salvar, na ordem certa) para cada
tabela.

> Os exemplos abaixo usam o star schema **HPN** (fonte OLTP → `fct_sales_details`,
> `dim_customer`, etc.), o mesmo modelo da camada semântica em
> [`../../semantic/01_gold_views.sql`](../../semantic/01_gold_views.sql).

Com **Lakeflow Declarative Pipelines** (o antigo DLT) você escreve o *o quê* em
**SQL**, e o motor cuida de: ordem de dependências, incremental, retries,
lineage e **qualidade de dados** (expectations). **Isso é o que tira a
necessidade do notebook** — o exemplo que você citou.

| Antigo (notebook) | Novo (declarative pipeline) |
|---|---|
| `spark.read.parquet(mount_path)` | `read_files(volume_path)` (Auto Loader) |
| `.withColumn('...timestamp', current_timestamp())` | `_metadata.file_modification_time` (grátis) |
| `df.write...saveAsTable('hive_metastore...')` | `CREATE STREAMING TABLE hpn_dev.bronze...` |
| você chama função por tabela | motor resolve dependências e grão automaticamente |
| qualidade = confiança | `CONSTRAINT ... EXPECT (...)` explícito |

## Bronze — streaming tables com Auto Loader

Uma célula SQL por tabela (ou geradas em loop). Ingere incrementalmente da
landing e carimba a origem:

```sql
CREATE OR REFRESH STREAMING TABLE hpn_dev.bronze.sales_order_detail
  COMMENT 'Ingestão bruta do detalhe de pedidos de venda (fonte OLTP HPN).'
AS SELECT
     *,
     _metadata.file_path              AS _source_file,
     _metadata.file_modification_time AS bronze_ingestion_ts
   FROM STREAM read_files(
     '/Volumes/hpn_dev/bronze/landing/sales_order_detail/',
     format => 'parquet'
   );
```

> `STREAM read_files(...)` é o Auto Loader: processa só os arquivos novos, com
> schema evolution. Substitui o `spark.read.format('parquet').load(...)` +
> `saveAsTable` do antigo, e o `bronze_ingestion_timestamp` manual vira
> `_metadata` nativo.

## Silver — materialized views + expectations (qualidade)

Limpeza, tipagem, dedup e **regras de qualidade** declaradas:

```sql
CREATE OR REFRESH MATERIALIZED VIEW hpn_dev.silver.sales_order_detail (
  CONSTRAINT valid_order    EXPECT (sales_order_number IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT positive_price EXPECT (unit_price >= 0)
)
  COMMENT 'Detalhe de vendas limpo e tipado. Grão: linha de pedido.'
AS SELECT
     sales_order_number,
     CAST(order_date AS DATE) AS order_date,
     customer_key,
     product_key,
     order_quantity,
     unit_price,
     unit_cost,
     discount_amount
   FROM hpn_dev.bronze.sales_order_detail;
```

> `CONSTRAINT ... EXPECT (...) ON VIOLATION DROP ROW` é o `@dlt.expect` que a
> Fase 2 do plano cita — qualidade vira parte da definição da tabela, com
> métricas de violação visíveis no pipeline.

## Gold — star schema (materialized views)

O modelo dimensional final que a camada semântica e o Genie consomem. O fato de
vendas vem direto da silver; a dimensão de cliente segue o mesmo padrão a partir
de `hpn_dev.silver.customer`:

```sql
-- Fato de vendas (grão: linha de pedido)
CREATE OR REFRESH MATERIALIZED VIEW hpn_dev.gold.fct_sales_details
  COMMENT 'Detalhe de vendas por item de pedido. Grão: sales_order_number x product_key.'
AS SELECT
     sales_order_number,
     order_date,
     customer_key,
     product_key,
     order_quantity,
     unit_price,
     unit_cost,
     discount_amount
   FROM hpn_dev.silver.sales_order_detail;

-- Dimensão cliente (region governa a RLS regional da Fase 4)
CREATE OR REFRESH MATERIALIZED VIEW hpn_dev.gold.dim_customer
  COMMENT 'Cadastro de clientes. Coluna region governa a RLS regional.'
AS SELECT
     customer_key,
     customer,
     region
   FROM hpn_dev.silver.customer;

-- fct_sales_returns, fct_finance, dim_product, dim_calendar, dim_account...
-- seguem o mesmo padrão, espelhando o star schema do PLANO e de semantic/.
```

## Como isso roda
- No workspace: **Pipelines → Create pipeline**, aponte para o(s) notebook(s)/arquivo(s)
  SQL, escolha o **catálogo alvo** (`hpn_dev`) e compute **serverless**.
- O pipeline monta o **DAG** sozinho (bronze → silver → gold) pela referência
  entre tabelas — você não ordena nada na mão.
- Ele é disparado pelo **Lakeflow Job** do capítulo [05](05_orquestracao.md).

## PK/FK e otimização (para lineage e Genie)
```sql
ALTER TABLE hpn_dev.gold.dim_customer
  ADD CONSTRAINT pk_dim_customer PRIMARY KEY (customer_key);
```
Defina PK/FK (informacional) — ajuda o Genie a entender os joins — e use
**Liquid Clustering** nas fatos por data.

## Checklist de saída
- [ ] Pipeline declarativo com bronze (streaming) → silver → gold em `hpn_dev`.
- [ ] Expectations de qualidade nas tabelas silver.
- [ ] PK/FK definidas nas dimensões/fatos gold.
- [ ] Zero notebook imperativo de `saveAsTable` por camada.
