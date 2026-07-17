# RUNBOOK — Reverse ETL: DW → Neon (`hpn_dw`)

Empurra a camada **Gold (star schema)** + as tabelas de **ML (Fase 6)** do Databricks
para um Postgres barato/always-on no Neon (`hpn_dw`), para servir app/BI sem manter um
SQL Warehouse always-on (decisão de FinOps da Fase 9).

Notebook: [`export/dw_to_neon.py`](dw_to_neon.py) (formato Databricks-source, célula a célula).

## Pré-requisitos
- Database `hpn_dw` criado no mesmo projeto Neon (mesmas credenciais do OLTP; só o nome muda).
- Secret scope `hpn-db` com `kv-postgres-host` / `-user` / `-pwd` (os mesmos da ingestão).
- Driver `org.postgresql.Driver` no cluster para o Spark JDBC de dados (a ingestão já depende dele).
- Compute **serverless**: o DDL usa `psycopg2` via `%pip` (o notebook instala sozinho na célula 0),
  porque serverless bloqueia acesso ao JVM/Py4J.

## Como rodar
1. Abrir `export/dw_to_neon.py` como notebook no Databricks (Git folder).
2. Conferir os widgets: `catalog=hpn`, `target_db=hpn_dw`.
3. Rodar célula a célula (Shift+Enter). A validação (§5) deve mostrar `status = OK`
   em todas as tabelas (contagem origem = destino).

## Desenho (o porquê das escolhas)
| Tema | Escolha | Motivo |
|---|---|---|
| Transporte | Spark JDBC | Delta gerenciada só é alcançável de dentro do Databricks. |
| Modo | `overwrite` + `truncate=true` | TRUNCATE (não DROP) → **PK e índices sobrevivem** ao refresh. |
| DDL | `psycopg2` (`%pip`) | Serverless bloqueia o JVM/Py4J → cliente Postgres direto p/ criar schema/PK/índice. |
| Schemas Neon | `gold`, `ml` | Espelha a medalhão sem o prefixo-dígito (`3_gold`). |
| Integridade | Só PK + índices, **sem FK** | FK quebraria o TRUNCATE e a ordem de carga. Índices dão o join rápido. |
| Conexões | `coalesce(1)` | Volume pequeno + teto de conexões do Neon → 1 conexão sequencial. |

## Tabelas (16) e chaves
- **9 dims** (`gold.dim_*`): PK na surrogate key; índice na FK quando há hierarquia.
- **4 fatos** (`gold.fct_*`): PK na BK; índices nas FKs e datas.
  `fct_product_cost_history` tem PK composta (produto × ano × mês × país).
- **3 ML** (`ml.*`): `forecast_sales` (PK `ds`), `reco_customer_actions` (PK `customer_key`),
  `pvm_drivers` (PK `comparison_type` × `year_month` × `subcategory`).

## Gotchas
- **Mudança de schema na Delta:** com `truncate=true`, se uma coluna nova aparecer, o
  insert falha (estrutura antiga preservada). Dropar a tabela no Neon uma vez → o Spark
  recria com o schema novo no próximo run.
- **1ª execução:** a tabela ainda não existe → o Spark a cria (não trunca). PK/índices
  são adicionados logo após, e passam a ser preservados nos refreshes seguintes.

## Próximos passos
- Virar job do Asset Bundle, encadeado após o refresh Gold/ML.
- Apontar o app (`app/serving.py`) para ler `gold.*`/`ml.*` do Neon em vez do warehouse.
