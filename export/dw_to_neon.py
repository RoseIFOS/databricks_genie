# Databricks notebook source
# MAGIC %md
# MAGIC # ⤵️ Reverse ETL — DW (Gold + ML) → Neon Postgres `hpn_dw`
# MAGIC
# MAGIC Este notebook é o **inverso da ingestão**. A ingestão puxa o OLTP do Neon para
# MAGIC o Databricks (`ingestion/1.Control_Ingestion`); aqui **empurramos** a camada
# MAGIC Gold (star schema) + as tabelas de ML de volta para um Postgres — o database
# MAGIC novo `hpn_dw` no mesmo projeto Neon.
# MAGIC
# MAGIC ## Por que servir o DW de um Postgres?
# MAGIC Para o app/BI ler o star schema de um banco **barato e sempre-ligado** (Neon)
# MAGIC em vez de manter um **SQL Warehouse always-on** (custo/cartão — ver a decisão
# MAGIC de FinOps da Fase 9). O Databricks continua sendo a fábrica (medallion + ML);
# MAGIC o Neon vira a **vitrine de serviço** consultável.
# MAGIC
# MAGIC ## Modelo mental (3 pilares)
# MAGIC 1. **Transporte:** Spark JDBC escreve cada tabela Delta no Postgres. Reusa o
# MAGIC    driver `org.postgresql.Driver` que a ingestão já usa (mesmo cofre `hpn-db`).
# MAGIC 2. **Idempotência sem perder estrutura:** `mode("overwrite")` + `truncate=true`
# MAGIC    faz **TRUNCATE** (não DROP+CREATE) — então PKs e índices que adicionamos
# MAGIC    SOBREVIVEM ao refresh. No 1º run a tabela não existe → o Spark cria; nos
# MAGIC    runs seguintes só troca os dados.
# MAGIC 3. **Serving-grade:** como o alvo é servir app/BI, aplicamos **tipos corretos**
# MAGIC    (o Spark mapeia DECIMAL→numeric, DATE→date, etc.), **PKs** e **índices** nas
# MAGIC    FKs/datas dos fatos. Sem FKs entre tabelas de propósito (quebrariam o
# MAGIC    TRUNCATE e a ordem de carga) — índices dão a performance de join sem o
# MAGIC    acoplamento.

# COMMAND ----------

# 0. Dependências
# psycopg2 via %pip (serverless bloqueia _jvm/Py4J);
# restartPython ativa a lib → vem ANTES de definir variáveis.

%pip install psycopg2-binary

dbutils.library.restartPython()

# COMMAND ----------

# MAGIC %md
# MAGIC ## 0. Dependências
# MAGIC O transporte de DADOS é Spark JDBC (não precisa de lib). Mas o DDL (criar
# MAGIC schema/PK/índice) precisa de um cliente Postgres direto: `psycopg2`. Em compute
# MAGIC **serverless** o acesso ao JVM (`_jvm`/Py4J) é bloqueado, então usamos psycopg2
# MAGIC via `%pip` (biblioteca notebook-scoped). O `restartPython` ativa a lib — por
# MAGIC isso esta célula vem ANTES de definir qualquer variável.

# COMMAND ----------

# MAGIC %pip install psycopg2-binary
# MAGIC dbutils.library.restartPython()

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. Parâmetros e conexão
# MAGIC Credenciais vêm do secret scope `hpn-db` (host/user/pwd) — as MESMAS da
# MAGIC ingestão. Só o **database** muda: apontamos para `hpn_dw` (o secret
# MAGIC `kv-postgres-db` guarda o nome do OLTP de origem, então sobrescrevemos aqui).

# COMMAND ----------

dbutils.widgets.text("catalog", "hpn", "Catálogo Unity Catalog")
dbutils.widgets.text("target_db", "hpn_dw", "Database de destino no Neon")

CATALOG   = dbutils.widgets.get("catalog")
TARGET_DB = dbutils.widgets.get("target_db")

# host/user/pwd: iguais aos da ingestão (a usuária confirmou que só o db mudou).
HOST = dbutils.secrets.get("hpn-db", "kv-postgres-host")
USER = dbutils.secrets.get("hpn-db", "kv-postgres-user")
PWD  = dbutils.secrets.get("hpn-db", "kv-postgres-pwd")

# reWriteBatchedInserts=true → o driver agrupa INSERTs (mais rápido em carga batch).
URL = f"jdbc:postgresql://{HOST}:5432/{TARGET_DB}?sslmode=require&reWriteBatchedInserts=true"

print(f"Catálogo origem: {CATALOG} | Destino Neon: {TARGET_DB} @ {HOST}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. Manifesto das tabelas (config-driven)
# MAGIC Uma lista declara O QUE mover e QUAIS chaves aplicar. Adicionar/remover tabela
# MAGIC = editar esta lista, nada mais. Convenção:
# MAGIC - `src` — tabela de origem no Databricks (schema `3_gold` exige backtick).
# MAGIC - `dst` — destino no Neon: `schema.tabela` (schemas `gold` e `ml`).
# MAGIC - `pk`  — colunas da PRIMARY KEY (surrogate/BK das dims e fatos).
# MAGIC - `idx` — colunas para índice simples (FKs e datas dos fatos → aceleram joins).
# MAGIC - `uq`  — listas de colunas para índice ÚNICO (ex.: `full_date` do calendário).

# COMMAND ----------

TABLES = [
    # ── Dimensões (Gold) ──────────────────────────────────────────────────────
    {"src": "hpn.`3_gold`.dim_customer",         "dst": "gold.dim_customer",
     "pk": ["customer_key"],         "idx": ["geography_key"]},
    {"src": "hpn.`3_gold`.dim_geography",        "dst": "gold.dim_geography",
     "pk": ["geography_key"],        "idx": ["region_key"]},
    {"src": "hpn.`3_gold`.dim_product",          "dst": "gold.dim_product",
     "pk": ["product_key"],          "idx": ["product_subcategory_key"]},
    {"src": "hpn.`3_gold`.dim_account",          "dst": "gold.dim_account",
     "pk": ["account_key"],          "idx": ["account_header_key"]},
    {"src": "hpn.`3_gold`.dim_account_header",   "dst": "gold.dim_account_header",
     "pk": ["account_header_key"]},
    {"src": "hpn.`3_gold`.dim_organization",     "dst": "gold.dim_organization",
     "pk": ["organization_key"]},
    {"src": "hpn.`3_gold`.dim_department_group", "dst": "gold.dim_department_group",
     "pk": ["department_group_key"]},
    {"src": "hpn.`3_gold`.dim_calendar",         "dst": "gold.dim_calendar",
     "pk": ["date_key"],             "uq": [["full_date"]]},
    {"src": "hpn.`3_gold`.dim_region",           "dst": "gold.dim_region",
     "pk": ["region_key"]},

    # ── Fatos (Gold) ──────────────────────────────────────────────────────────
    {"src": "hpn.`3_gold`.fct_sales_details",    "dst": "gold.fct_sales_details",
     "pk": ["sales_details_key"],
     "idx": ["customer_key", "product_key", "region_key", "sales_header_key", "order_date"]},
    {"src": "hpn.`3_gold`.fct_sales_returns",    "dst": "gold.fct_sales_returns",
     "pk": ["return_key"],
     "idx": ["customer_key", "product_key", "return_date"]},
    {"src": "hpn.`3_gold`.fct_finance",          "dst": "gold.fct_finance",
     "pk": ["finance_key"],
     "idx": ["account_key", "organization_key", "department_group_key", "transaction_date"]},
    {"src": "hpn.`3_gold`.fct_product_cost_history", "dst": "gold.fct_product_cost_history",
     "pk": ["product_key", "year", "month_no", "country_code"],
     "idx": ["product_key"]},

    # ── ML (Fase 6) ───────────────────────────────────────────────────────────
    {"src": "hpn.ml.forecast_sales",         "dst": "ml.forecast_sales",
     "pk": ["ds"]},
    {"src": "hpn.ml.reco_customer_actions",  "dst": "ml.reco_customer_actions",
     "pk": ["customer_key"],  "idx": ["segment", "priority"]},
    {"src": "hpn.ml.pvm_drivers",            "dst": "ml.pvm_drivers",
     "pk": ["comparison_type", "year_month", "subcategory"],
     "idx": ["subcategory"]},
]

print(f"{len(TABLES)} tabelas no manifesto "
      f"({sum(t['dst'].startswith('gold.') for t in TABLES)} gold + "
      f"{sum(t['dst'].startswith('ml.') for t in TABLES)} ml).")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. Helper de DDL (psycopg2)
# MAGIC O Spark JDBC só escreve DADOS; para rodar DDL (criar schema, PK, índice) abrimos
# MAGIC uma conexão Postgres direta com `psycopg2` (no driver do notebook). `autocommit`
# MAGIC garante que cada comando persista. Serverless bloqueia o acesso ao JVM, por isso
# MAGIC não dá para reusar o driver JDBC via Py4J aqui.

# COMMAND ----------

import psycopg2

def run_ddl(statements):
<<<<<<< Updated upstream
    """Executa uma lista de comandos DDL/SQL no Postgres de destino."""
=======
>>>>>>> Stashed changes
    conn = psycopg2.connect(
        host=HOST, port=5432, dbname=TARGET_DB,
        user=USER, password=PWD, sslmode="require",
    )
    try:
        conn.autocommit = True
        with conn.cursor() as cur:
            for s in statements:
                cur.execute(s)
    finally:
        conn.close()


# Smoke test da conexão + criação dos schemas de destino.
run_ddl([
    "CREATE SCHEMA IF NOT EXISTS gold",
    "CREATE SCHEMA IF NOT EXISTS ml",
])
print("Conexão OK — schemas gold e ml garantidos no Neon.")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. Carga: escreve dados + aplica PK/índices
# MAGIC Para cada tabela:
# MAGIC 1. Lê a Delta do Databricks e escreve no Neon (`overwrite` + `truncate`).
# MAGIC    - `coalesce(1)`: 1 partição = 1 conexão sequencial. Volume é pequeno e o
# MAGIC      Neon tem teto de conexões — evita saturar o pool.
# MAGIC 2. Aplica PK e índices de forma **idempotente** (só cria se ainda não existem),
# MAGIC    porque no 2º+ refresh o TRUNCATE preserva o que já foi criado.

# COMMAND ----------

# DBTITLE 1,Cell 10
def write_data(src, dst):
    (spark.table(src).coalesce(1).write.format("postgresql")
        .option("host", HOST).option("port", "5432").option("database", TARGET_DB)
        .option("user", USER).option("password", PWD)
        .option("dbtable", dst)
        .option("truncate", "true")   # overwrite = TRUNCATE (preserva PK/índices)
        .option("batchsize", 5000)
        .mode("overwrite")
        .save())

def apply_keys(t):
    dst = t["dst"]
    tbl = dst.split(".")[-1]
    slug = dst.replace(".", "_")
    ddls = []

    if t.get("pk"):
        cols  = ", ".join(f'"{c}"' for c in t["pk"])
        cname = f"{tbl}_pkey"
        # DO block: adiciona a PK só se a constraint ainda não existe (idempotente).
        ddls.append(
            "DO $$ BEGIN "
            f"IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '{cname}') THEN "
            f"ALTER TABLE {dst} ADD CONSTRAINT {cname} PRIMARY KEY ({cols}); "
            "END IF; END $$;"
        )
    for c in t.get("idx", []):
        ddls.append(f'CREATE INDEX IF NOT EXISTS ix_{slug}_{c} ON {dst} ("{c}");')
    for cols in t.get("uq", []):
        cs = ", ".join(f'"{x}"' for x in cols)
        ddls.append(
            f'CREATE UNIQUE INDEX IF NOT EXISTS ux_{slug}_{"_".join(cols)} ON {dst} ({cs});'
        )
    if ddls:
        run_ddl(ddls)

for t in TABLES:
    write_data(t["src"], t["dst"])
    apply_keys(t)
    print(f"✅ {t['dst']:<32} carregada + chaves aplicadas")

print("\n🎉 Reverse ETL concluído.")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5. Validação — contagem origem × destino
# MAGIC Confere que cada tabela do Neon tem a MESMA contagem de linhas da origem Delta.
# MAGIC `status` = OK quando batem.

# COMMAND ----------

def neon_count(dst):
    return (spark.read.format("jdbc")
        .option("url", URL).option("user", USER).option("password", PWD)
        .option("driver", "org.postgresql.Driver")
        .option("dbtable", dst).load().count())

rows = []
for t in TABLES:
    src_cnt = spark.table(t["src"]).count()
    dst_cnt = neon_count(t["dst"])
    rows.append((t["dst"], src_cnt, dst_cnt, "OK" if src_cnt == dst_cnt else "DIVERGE"))

report = spark.createDataFrame(
    rows, "target string, source_rows long, neon_rows long, status string"
)
display(report.orderBy("status", "target"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6. Próximos passos
# MAGIC - **Agendar:** transformar num job do Asset Bundle (padrão do
# MAGIC   `resources/ml_forecast_job.yml`), rodando DEPOIS do refresh da Gold/ML.
# MAGIC - **Apontar o app:** configurar o app para ler `gold.*` / `ml.*` do Neon
# MAGIC   (`hpn_dw`) em vez do SQL Warehouse — economia de FinOps.
# MAGIC - **Gotcha:** se o schema de uma Delta MUDAR (coluna nova), o `truncate=true`
# MAGIC   mantém a estrutura antiga e o insert falha. Nesse caso, dropar a tabela no
# MAGIC   Neon uma vez para o Spark recriá-la com o schema novo.
