# Databricks notebook source
# MAGIC %md
# MAGIC # 📈 Forecast de Vendas — HPN
# MAGIC
# MAGIC Este notebook treina um modelo de **previsão de vendas mensais**, registra
# MAGIC no **Unity Catalog (via MLflow)** e grava as previsões em uma tabela Delta
# MAGIC que o Genie e o App vão consultar.
# MAGIC
# MAGIC É o equivalente ao node **Forecast (Fase 10)** do projeto de referência,
# MAGIC agora como um modelo gerenciado e servível.
# MAGIC
# MAGIC **Fluxo do notebook:**
# MAGIC 1. Parâmetros (widgets)
# MAGIC 2. Carregar histórico de vendas (camada gold)
# MAGIC 3. Treinar o modelo (Prophet) com rastreamento MLflow
# MAGIC 4. Registrar o modelo no Unity Catalog
# MAGIC 5. Gerar previsões futuras e gravar em Delta
# MAGIC
# MAGIC > Como você vai implementar linha a linha: rode célula por célula (Shift+Enter)
# MAGIC > e inspecione a saída de cada uma antes de seguir.

# COMMAND ----------

# MAGIC %md
# MAGIC ## 0. Instalação de dependências
# MAGIC Se o cluster já tiver as libs (declaradas no job), pode pular. Ao rodar
# MAGIC manualmente num cluster "cru", descomente o %pip abaixo e reinicie o Python.

# COMMAND ----------

# MAGIC %pip install "prophet>=1.1.6" mlflow>=2.16
# MAGIC dbutils.library.restartPython()
# MAGIC

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. Parâmetros (widgets)
# MAGIC Widgets criam caixinhas de input no topo do notebook. Quando o JOB roda,
# MAGIC ele preenche esses widgets com os `base_parameters` do YAML — por isso
# MAGIC não usamos valores "hardcoded" para catálogo/horizonte.

# COMMAND ----------

# Remove widgets
#dbutils.widgets.removeAll()


# Cria os widgets (só na primeira execução; recriar é idempotente).
dbutils.widgets.text("catalog", "hpn", "Catálogo Unity Catalog")
dbutils.widgets.text("horizon_months", "14", "Meses a prever")

# Lê os valores (sempre vêm como string; convertemos o que for número).
CATALOG = dbutils.widgets.get("catalog")
HORIZON = int(dbutils.widgets.get("horizon_months"))
#HORIZON = 14


# Onde vamos gravar o modelo e as previsões.
# ATENÇÃO: no Unity Catalog, modelo registrado e tabela COMPARTILHAM o namespace do
# schema — não podem ter o mesmo nome. Por isso o modelo leva o sufixo _model.
MODEL_NAME = f"{CATALOG}.ml.forecast_sales_model"    # modelo registrado no UC (3 níveis)
OUTPUT_TABLE = f"{CATALOG}.ml.forecast_sales"         # tabela Delta de previsões (nome distinto do modelo)

#cria o schema antes de registrar o modelo (célula 4) e gravar a tabela (célula 5)
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.ml")

print(f"Catálogo: {CATALOG} | Horizonte: {HORIZON} meses")
print(f"Modelo UC: {MODEL_NAME}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. Carregar o histórico de vendas
# MAGIC Agregamos as vendas por mês a partir da camada gold. O Prophet espera um
# MAGIC DataFrame com exatamente duas colunas: **ds** (data) e **y** (valor).

# COMMAND ----------

import pandas as pd

# Consulta o gold via Spark SQL. Somamos vendas brutas por mês.
# Usamos a coluna canônica `gross_sales` (= a definição oficial da camada, igual à
# measure Gross Sales da metric view) em vez de recalcular order_quantity*unit_price.
# Schema com dígito inicial (`3_gold`) exige backtick.
sdf = spark.sql(f"""
    SELECT
        date_trunc('month', s.order_date)  AS ds,
        CAST(SUM(s.gross_sales) AS DOUBLE) AS y
    FROM {CATALOG}.`3_gold`.fct_sales_details s
    GROUP BY date_trunc('month', s.order_date)
    ORDER BY ds
""")

# Prophet roda em pandas (dataset mensal é pequeno), então convertemos.
df = sdf.toPandas()
df["ds"] = pd.to_datetime(df["ds"])
print(f"{len(df)} meses de histórico. Período: {df['ds'].min()} → {df['ds'].max()}")
display(df.tail(12))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. Treinar o modelo com rastreamento MLflow
# MAGIC
# MAGIC **MLflow** registra automaticamente parâmetros, métricas e o próprio modelo
# MAGIC (isso é parte da OBSERVABILIDADE que a TI espera). Abrimos um "run" e tudo
# MAGIC que acontece dentro dele fica versionado e comparável na aba *Experiments*.
# MAGIC
# MAGIC > **Alternativa sem código:** `databricks.automl.forecast(df, target_col="y",
# MAGIC > time_col="ds", horizon=HORIZON, frequency="MS")` treina vários modelos e
# MAGIC > escolhe o melhor sozinho. Aqui usamos Prophet manual por ser mais didático.

# COMMAND ----------

import mlflow
from prophet import Prophet

# Direciona o registro de modelos para o Unity Catalog (e não o registry legado).
mlflow.set_registry_uri("databricks-uc")

with mlflow.start_run(run_name="prophet_forecast_sales") as run:


    # ---- Hiperparâmetros (logados para rastreabilidade) ----
    params = {
        "seasonality_mode": "multiplicative",   # sazonalidade proporcional ao nível
        "yearly_seasonality": True,
        "weekly_seasonality": False,            # dado mensal não tem sazonalidade semanal
        "changepoint_prior_scale": 0.05,        # flexibilidade da tendência
    }
    mlflow.log_params(params)
    mlflow.log_param("horizon_months", HORIZON)

    # ---- Treino ----
    model = Prophet(**params)
    model.fit(df)

    # ---- Métrica simples de aderência no histórico (in-sample) ----
    # Em produção, prefira validação cruzada (prophet.diagnostics.cross_validation).
    in_sample = model.predict(df[["ds"]])
    mae = (in_sample["yhat"].values - df["y"].values).__abs__().mean()
    mlflow.log_metric("mae_in_sample", float(mae))
    print(f"MAE in-sample: {mae:,.2f}")

    # ---- Loga o modelo no MLflow (assinatura ajuda no serving depois) ----
    #mlflow.prophet.log_model(model, artifact_path="model")
    from mlflow.models import infer_signature
    signature = infer_signature(
        df[["ds"]],
        in_sample[["yhat", "yhat_lower", "yhat_upper"]],
    )
    mlflow.prophet.log_model(model, artifact_path="model", signature=signature)


    run_id = run.info.run_id
    print(f"Run MLflow: {run_id}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. Registrar o modelo no Unity Catalog
# MAGIC Promove o modelo treinado a uma **versão versionada** em `catalog.ml.<nome>`.
# MAGIC A partir daí ele pode ser servido (Model Serving) e governado como qualquer
# MAGIC ativo do UC (permissões, lineage).

# COMMAND ----------


result = mlflow.register_model(
    model_uri=f"runs:/{run_id}/model",
    name=MODEL_NAME,
)
print(f"Registrado {MODEL_NAME} versão {result.version}")

# (Opcional) marca a versão como alias 'champion' para o serving apontar sempre
# para a "melhor atual" sem trocar o endpoint.
from mlflow import MlflowClient
MlflowClient().set_registered_model_alias(MODEL_NAME, "champion", result.version)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5. Gerar previsões futuras e gravar em Delta
# MAGIC O App e o Genie leem esta tabela para responder "qual a previsão de vendas
# MAGIC dos próximos meses?" sem precisar chamar o modelo em tempo real.

# COMMAND ----------

# Cria as datas futuras (freq='MS' = início de mês) e prevê.
future = model.make_future_dataframe(periods=HORIZON, freq="MS")
forecast = model.predict(future)

# Selecionamos só o que interessa: data, previsão e intervalo de confiança.
out = forecast[["ds", "yhat", "yhat_lower", "yhat_upper"]].copy()
out = out.rename(columns={
    "yhat": "forecast",
    "yhat_lower": "forecast_lower",
    "yhat_upper": "forecast_upper",
})
out["model_version"] = result.version   # rastreabilidade: qual modelo gerou

# Garante o schema ml e grava (overwrite = substitui a previsão anterior).
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.ml")
(
    spark.createDataFrame(out)
    .write.mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(OUTPUT_TABLE)
)

# Documenta a tabela para o Genie entender o que ela é.
spark.sql(f"""
    COMMENT ON TABLE {OUTPUT_TABLE} IS
    'Previsão de vendas brutas mensais (Prophet). Colunas forecast/_lower/_upper em USD.'
""")

print(f"✅ Previsões gravadas em {OUTPUT_TABLE}")
display(out.tail(HORIZON + 3))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6. Próximos passos (fora deste notebook)
# MAGIC - **Servir o modelo:** crie um endpoint de Model Serving apontando para
# MAGIC   `MODEL_NAME@champion` (o `serving.py` do app já chama por nome).
# MAGIC - **Agendar:** este notebook já é executado pelo job do bundle
# MAGIC   (`resources/ml_forecast_job.yml`), diariamente às 05:00.
# MAGIC - **Cadastrar no Genie:** adicione a tabela `ml.forecast_sales` como
# MAGIC   trusted asset no Genie Space Comercial.
# MAGIC - **Causal / Recomendação:** replique este padrão (treina → registra UC →
# MAGIC   grava tabela/endpoint) para os outros dois modelos da Fase 6.
